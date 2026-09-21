import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'rider_logic.dart';


class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String customerName;
  final String address;
  final double? customerLat;
  final double? customerLng;
  final RiderController riderController;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.customerName,
    required this.address,
    required this.customerLat,
    required this.customerLng,
    required this.riderController,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  
  static const primary = Color(0xFFA70000); 
  static const creamText = Color(0xFFFEF9E7);
  static const bg = Colors.white; 
  static const bannerBg = Color(0xFFFFF6DA);
  static const orangeAccent = Color(0xFFFF8A00); 

  GoogleMapController? _mapController;
  LatLng? _riderLatLng;
  bool _isUpdating = false;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStreamSub;
  BitmapDescriptor? _riderDotIcon;

  // 👈 Google Directions API key — must have the "Directions API" enabled
  // on the same Google Cloud project as your Maps API key. Put your real
  // key here (can reuse the Maps key if Directions API is enabled on it).
  static const String _directionsApiKey =
      'AIzaSyDDTpx9ZaDEsDzGIOnrsWLQL3vHKz7DZU4';

  // Same sequence used elsewhere in the app — keep in sync with
  // functions/index.js STATUS_MESSAGES and rider_logic.dart's queries.
  static const List<String> _statusSequence = [
    'Accepted',
    'Picked Up',
    'On the Way',
    'Delivered',
  ];

  @override
  void initState() {
    super.initState();
    _createRiderDotIcon();
    _startLiveLocation();
  }

  // 👈 FIX: previously used a real-world-meters Circle for the rider's
  // location — that shrinks to invisible once the map zooms out (which
  // happens automatically to fit both rider and customer pins on screen).
  // A Marker's icon, by contrast, always stays the same pixel size no
  // matter the zoom — same as how the default red pin never disappears.
  // So instead we draw our own small blue-dot bitmap once and use it as
  // a normal Marker icon, which behaves like Google's native "my
  // location" dot but is guaranteed visible at any zoom level.
  Future<void> _createRiderDotIcon() async {
    const double size = 60;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);

    // Soft outer halo
    canvas.drawCircle(
      center,
      size / 2,
      Paint()..color = Colors.blue.withValues(alpha: 0.25),
    );
    // White border ring
    canvas.drawCircle(center, size / 3.2, Paint()..color = Colors.white);
    // Solid blue dot
    canvas.drawCircle(center, size / 4, Paint()..color = Colors.blue);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    if (mounted && bytes != null) {
      setState(() {
        _riderDotIcon = BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
      });
    }
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    super.dispose();
  }

  // 👈 UPDATED: instead of polling every 20s (which made the blue dot
  // jump in big steps), this now listens to a continuous GPS stream —
  // the dot moves smoothly/live as soon as a new fix comes in (usually
  // every 1-3s while actually moving). Route re-fetching stays cheap: it
  // still only calls the Directions API when the rider has moved at
  // least ~30m since the last successful route (see _fetchRoute), so the
  // frequent position updates don't multiply your Directions API cost.
  Future<void> _startLiveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
        return;
      }

      // One immediate reading so the dot appears right away, instead of
      // waiting for the stream's first event.
      final initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(
          () =>
              _riderLatLng = LatLng(initialPos.latitude, initialPos.longitude),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitPinsOnScreen());
        _fetchRoute();
      }

      // Live stream — distanceFilter: 3 means it fires roughly every time
      // the rider moves ~3 meters, which in practice ends up being every
      // couple of seconds while actually riding, giving smooth movement.
      _positionStreamSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen((Position pos) {
            if (!mounted) return;
            setState(() => _riderLatLng = LatLng(pos.latitude, pos.longitude));
            _fetchRoute(); // internally throttled — only calls API if moved 30m+
          });
    } catch (e) {
      debugPrint('Error starting live location: $e');
      // Map still works fine with just the customer marker if this fails.
    }
  }

  // 👈 Remembers where we last successfully fetched a route FROM, so tiny
  // GPS jitter (a few meters of noise) doesn't keep re-triggering the
  // Directions API and flipping the line between different nearby roads.
  LatLng? _lastRouteOrigin;
  static const double _minMetersBeforeReroute = 30;

  // 👈 Calls Google's Directions API to get the actual road-following
  // route between rider and customer (like the "Drive" screen in the
  // Google Maps app), then decodes it into a list of LatLng points to
  // draw as a Polyline on the map.
  Future<void> _fetchRoute() async {
    final hasCustomerLoc =
        widget.customerLat != null && widget.customerLng != null;
    if (_riderLatLng == null || !hasCustomerLoc) return;

    // Skip re-fetching if the rider has barely moved since the last route
    // — GPS readings wobble by a few meters even when standing still, and
    // re-asking Directions for an almost-identical start point can return
    // a completely different nearby road, making the line flicker.
    if (_lastRouteOrigin != null) {
      final movedMeters = Geolocator.distanceBetween(
        _lastRouteOrigin!.latitude,
        _lastRouteOrigin!.longitude,
        _riderLatLng!.latitude,
        _riderLatLng!.longitude,
      );
      if (movedMeters < _minMetersBeforeReroute) return;
    }

    final origin = '${_riderLatLng!.latitude},${_riderLatLng!.longitude}';
    final destination = '${widget.customerLat},${widget.customerLng}';
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin&destination=$destination&key=$_directionsApiKey',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint('Directions API error: HTTP ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('Directions API status: ${data['status']}');
        return;
      }

      final points = data['routes'][0]['overview_polyline']['points'] as String;
      final decoded = _decodePolyline(points);

      if (mounted) {
        setState(() {
          _routePoints = decoded;
          _lastRouteOrigin = _riderLatLng;
        });
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
      // Map still works fine with just the two pins if this fails.
    }
  }

  // Standard Google polyline decoding algorithm — turns the compact
  // encoded string from the Directions API into actual LatLng points.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dLng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  void _fitPinsOnScreen() {
    if (_mapController == null || _riderLatLng == null) return;

    final hasCustomerLoc =
        widget.customerLat != null && widget.customerLng != null;
    if (!hasCustomerLoc) {
      // Only the rider's own location is known — just center on that.
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_riderLatLng!, 15),
      );
      return;
    }

    final destLatLng = LatLng(widget.customerLat!, widget.customerLng!);
    final minLat = _riderLatLng!.latitude < destLatLng.latitude
        ? _riderLatLng!.latitude
        : destLatLng.latitude;
    final maxLat = _riderLatLng!.latitude > destLatLng.latitude
        ? _riderLatLng!.latitude
        : destLatLng.latitude;
    final minLng = _riderLatLng!.longitude < destLatLng.longitude
        ? _riderLatLng!.longitude
        : destLatLng.longitude;
    final maxLng = _riderLatLng!.longitude > destLatLng.longitude
        ? _riderLatLng!.longitude
        : destLatLng.longitude;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isUpdating = true);
    final success = await widget.riderController.updateOrderStatus(
      widget.orderId,
      newStatus,
    );
    if (!mounted) return;
    setState(() => _isUpdating = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Status updated: $newStatus' : 'Failed to update status',
        ),
        // 👈 Every button-click message uses the app's maroon theme color
        // now, instead of green/red, for a consistent look.
        backgroundColor: primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (success && newStatus == 'Delivered') {
      Navigator.pop(context);
    }
  }

  Widget _buildStatusButton({
    required String label,
    required Color color,
    required int statusIndex, // index of this status in _statusSequence
    required int currentIndex,
  }) {
    final isDone = statusIndex <= currentIndex;
    final isActive = statusIndex == currentIndex + 1;
    final isReachable = isDone || isActive;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (isActive && !_isUpdating)
            ? () => _updateStatus(_statusSequence[statusIndex])
            : null,
        style: ElevatedButton.styleFrom(
          // 👈 Light shade of the same color when not yet reachable,
          // full solid color once it's active or already done — no
          // separate green "done" tint, as requested.
          backgroundColor: isReachable ? color : color.withValues(alpha: 0.35),
          disabledBackgroundColor: isReachable
              ? color
              : color.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: isActive ? 3 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomerLoc =
        widget.customerLat != null && widget.customerLng != null;
    final customerLatLng = hasCustomerLoc
        ? LatLng(widget.customerLat!, widget.customerLng!)
        : const LatLng(33.6844, 73.0479); // fallback if coords missing

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Address',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final currentStatus = data?['order_status']?.toString() ?? 'Accepted';
          final rawIndex = _statusSequence.indexOf(currentStatus);
          final currentIndex = rawIndex == -1 ? 0 : rawIndex;

          return Column(
            children: [
              // ── Map (top) ──────────────────────────────────────
              Expanded(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: customerLatLng,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    _fitPinsOnScreen();
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  polylines: {
                    if (_routePoints.isNotEmpty)
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: _routePoints,
                        color: primary,
                        width: 5,
                      ),
                  },
                  markers: {
                    // Customer stays a standard pin marker.
                    Marker(
                      markerId: const MarkerId('customer'),
                      position: customerLatLng,
                      infoWindow: InfoWindow(
                        title: widget.customerName,
                        snippet: widget.address,
                      ),
                    ),
                    // 👈 Rider uses our custom-drawn blue dot icon (a
                    // Marker, not a Circle) so it stays a fixed, visible
                    // size regardless of zoom level — a meters-based
                    // Circle shrinks to invisible once the map zooms out
                    // to fit both pins.
                    if (_riderLatLng != null && _riderDotIcon != null)
                      Marker(
                        markerId: const MarkerId('rider'),
                        position: _riderLatLng!,
                        icon: _riderDotIcon!,
                        anchor: const Offset(0.5, 0.5),
                        infoWindow: const InfoWindow(title: 'You'),
                      ),
                  },
                ),
              ),

              // ── Info banner + status buttons ─────────────────
              SafeArea(
                top: false,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
                        color: bannerBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'Update status to notify customer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Column(
                        children: [
                          _buildStatusButton(
                            label: 'PICKED UP',
                            color: primary,
                            statusIndex: 1,
                            currentIndex: currentIndex,
                          ),
                          const SizedBox(height: 8),
                          _buildStatusButton(
                            label: 'ON THE WAY',
                            color: primary,
                            statusIndex: 2,
                            currentIndex: currentIndex,
                          ),
                          const SizedBox(height: 8),
                          _buildStatusButton(
                            label: 'DELIVERED',
                            color: orangeAccent,
                            statusIndex: 3,
                            currentIndex: currentIndex,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
