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
  static const _pendingRed = Color(0xFFD32F2F);

  GoogleMapController? _mapController;
  LatLng? _riderLatLng;
  bool _isUpdating = false;
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStreamSub;
  BitmapDescriptor? _riderDotIcon;
  bool _weakSignalShown = false;

  // 👈 Google Directions API key — must have the "Directions API" enabled
  // on the same Google Cloud project as your Maps API key. Put your real
  // key here (can reuse the Maps key if Directions API is enabled on it).
  static const String _directionsApiKey =
      'AIzaSyDDTpx9ZaDEsDzGIOnrsWLQL3vHKz7DZU4';

  // Same sequence used elsewhere in the app — keep in sync with
  // functions/index.js STATUS_MESSAGES and rider_logic.dart's queries.
  // The rider's flow is: Accepted -> On the Way -> Delivered (there is no
  // "Start Delivery" or "Picked Up" step any more).
  static const List<String> _statusSequence = [
    'Accepted',
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
  void _showLocationProblem(
    String message, {
    String? actionLabel,
    Future<bool> Function()? action,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _pendingRed,
        duration: const Duration(seconds: 8),
        action: (actionLabel != null && action != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: () => action(),
              )
            : null,
      ),
    );
  }

  Future<void> _startLiveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        _showLocationProblem(
          'GPS is turned off, so the customer cannot see you. Turn it on.',
          actionLabel: 'Open settings',
          action: Geolocator.openLocationSettings,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permission denied.');
          _showLocationProblem(
            'Location permission is denied, so the customer cannot see you.',
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
        _showLocationProblem(
          'Location permission is blocked. Allow it in the app settings.',
          actionLabel: 'Open settings',
          action: Geolocator.openAppSettings,
        );
        return;
      }

      // NOTE: uploading the rider's location to Firestore is handled by
      // RiderController for every order that is "On the Way" (so several
      // customers can see the same live location). This screen only needs
      // the position to draw the rider's own blue dot and the route.

      // Step 1: start the live stream FIRST. Before, the stream only started
      // after getCurrentPosition() finished - and if that call hung or threw
      // (weak GPS fix, indoors) the stream never started and nothing was
      // ever uploaded. distanceFilter: 3 fires roughly every time the rider
      // moves ~3 meters.
      _positionStreamSub?.cancel();
      _positionStreamSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 3,
            ),
          ).listen((Position pos) {
            // Ignore weak GPS readings (they can be hundreds of meters off).
            if (!isReliableRiderFix(pos)) {
              if (!_weakSignalShown) {
                _weakSignalShown = true;
                _showLocationProblem(
                  'GPS signal is weak (accuracy about ${pos.accuracy.round()} m). '
                  'Move to an open area so the customer sees your exact position.',
                );
              }
              return;
            }
            _weakSignalShown = false;
            if (!mounted) return;
            setState(() => _riderLatLng = LatLng(pos.latitude, pos.longitude));
            _fetchRoute(); // internally throttled - only calls API if moved 30m+
          }, onError: (e) => debugPrint('Location stream error: $e'));

      // Step 2: one immediate reading so the dot appears right
      // away instead of waiting for the rider to move. Has a time limit and
      // falls back to the last known position, so it can never block.
      Position? firstPos;
      try {
        firstPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('No fresh GPS fix yet, checking last known position: $e');
        // A cached position is only trusted if it is recent - an old one can
        // be kilometers away from where the rider really is.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && isFreshFix(last)) firstPos = last;
      }

      if (firstPos != null &&
          isReliableRiderFix(firstPos, maxAccuracyMeters: 100)) {
        if (mounted) {
          final pos = firstPos;
          setState(() => _riderLatLng = LatLng(pos.latitude, pos.longitude));
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _fitPinsOnScreen(),
          );
          _fetchRoute();
        }
      }
    } catch (e) {
      debugPrint('Error starting live location: $e');
      _showLocationProblem('Could not start live location: $e');
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

    // Shown at the TOP of the screen (maroon) so it's easy to see.
    _showTopBanner(
      context,
      success ? 'Order marked as $newStatus' : 'Failed to update status',
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

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (isActive && !_isUpdating)
            ? () => _updateStatus(_statusSequence[statusIndex])
            : null,
        style: ElevatedButton.styleFrom(
          // Red until tapped (faded while still locked), orange once done.
          backgroundColor: isDone
              ? orangeAccent
              : (isActive ? _pendingRed : _pendingRed.withValues(alpha: 0.45)),
          disabledBackgroundColor: isDone
              ? orangeAccent
              : (isActive ? _pendingRed : _pendingRed.withValues(alpha: 0.45)),
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
          final currentStatus =
              (data?['orderStatus'] ?? data?['order_status'])?.toString() ??
              'Accepted';
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
                            label: 'ON THE WAY',
                            color: primary,
                            statusIndex: _statusSequence.indexOf('On the Way'),
                            currentIndex: currentIndex,
                          ),
                          const SizedBox(height: 8),
                          _buildStatusButton(
                            label: 'DELIVERED',
                            color: orangeAccent,
                            statusIndex: _statusSequence.indexOf('Delivered'),
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

// ── Top-of-screen message banner ─────────────────────────────────────
// Shown on the ROOT overlay so it sits above bottom sheets/dialogs, at
// the top of the screen where it's easy to see (a normal SnackBar
// renders at the bottom, hidden behind the order-details bottom sheet).
void _showTopBanner(
  BuildContext context,
  String message, {
  Color color = const Color(0xFFA70000), // app maroon
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _TopBanner(message: message, color: color, onDone: entry.remove),
  );
  overlay.insert(entry);
}

class _TopBanner extends StatefulWidget {
  final String message;
  final Color color;
  final VoidCallback onDone;
  const _TopBanner({
    required this.message,
    required this.color,
    required this.onDone,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 14,
      right: 14,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _ctrl,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.6),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Rider's delivery map
//
// Shows EVERY order of this rider that is currently "On the Way":
//   • each customer gets their own pin with the customer's NAME and the
//     estimated travel time drawn on it
//   • a route line (following the roads) from the rider to each customer,
//     each customer in their own colour
//   • a list at the bottom with every customer's name, time and distance
//   • the rider's own live location is the blue dot (the same live GPS that
//     every On the Way customer sees on their tracking map)
// ═════════════════════════════════════════════════════════════════════

// One colour per customer: used for the pin, the route line and the list dot.
const List<Color> _kCustomerColors = [
  Color(0xFFD32F2F), // red
  Color(0xFF2E7D32), // green
  Color(0xFF6A1B9A), // purple
  Color(0xFFEF6C00), // orange
  Color(0xFF00838F), // teal
  Color(0xFF5D4037), // brown
];

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

class _OnTheWayCustomer {
  final String orderId;
  final String name;
  final String address;
  final LatLng? position; // null when the order has no saved coordinates
  final Color color;
  const _OnTheWayCustomer({
    required this.orderId,
    required this.name,
    required this.address,
    required this.position,
    required this.color,
  });
}

class _RouteInfo {
  final List<LatLng> points;
  final String durationText; // e.g. "12 mins"
  final String distanceText; // e.g. "4.2 km"
  final LatLng fetchedFrom; // where the rider was when this route was fetched
  final DateTime fetchedAt;
  const _RouteInfo({
    required this.points,
    required this.durationText,
    required this.distanceText,
    required this.fetchedFrom,
    required this.fetchedAt,
  });
}

class RiderDeliveriesMapScreen extends StatefulWidget {
  final String riderId;
  final RiderController riderController;

  const RiderDeliveriesMapScreen({
    super.key,
    required this.riderId,
    required this.riderController,
  });

  @override
  State<RiderDeliveriesMapScreen> createState() =>
      _RiderDeliveriesMapScreenState();
}

class _RiderDeliveriesMapScreenState extends State<RiderDeliveriesMapScreen> {
  static const primary = Color(0xFFA70000);

  // Route re-fetch limits, so the Directions API (which costs money) is not
  // called on every GPS update: a route is refreshed only after the rider has
  // moved this far AND at least this much time has passed.
  static const double _minMetersBeforeRefetch = 50;
  static const Duration _minRefetchGap = Duration(seconds: 20);

  GoogleMapController? _mapController;
  BitmapDescriptor? _riderDotIcon;

  // Customer pin images (pin + name + time), by label text and colour.
  final Map<String, BitmapDescriptor> _pins = {};
  final Set<String> _pinsBeingBuilt = {};

  // Latest road route (line + time + distance) for each order.
  final Map<String, _RouteInfo> _routes = {};
  final Set<String> _fetching = {};
  final Map<String, DateTime> _lastAttemptAt = {};

  // Used for the rider's dot until the first live GPS reading arrives.
  LatLng? _fallbackRiderLatLng;

  // Latest values, so onMapCreated / the recenter button can fit the camera.
  List<_OnTheWayCustomer> _latestCustomers = const [];
  LatLng? _latestRider;
  String _lastFitKey = '';

  late final Stream<QuerySnapshot> _ordersStream = FirebaseFirestore.instance
      .collection('orders')
      .where('riderId', isEqualTo: widget.riderId)
      .where('orderStatus', isEqualTo: 'On the Way')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _buildRiderDot();
    _loadFallbackLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _buildRiderDot() async {
    final icon = await _buildRiderDotBitmap();
    if (mounted && icon != null) setState(() => _riderDotIcon = icon);
  }

  // Returns the pin image for these label lines, or null while it is still
  // being drawn (the marker then falls back to the default red pin).
  BitmapDescriptor? _pinFor(List<String> lines, Color color) {
    final key = '${color.toARGB32()}|${lines.join('|')}';
    final cached = _pins[key];
    if (cached != null) return cached;

    if (!_pinsBeingBuilt.contains(key)) {
      _pinsBeingBuilt.add(key);
      _buildNamedPinBitmap(lines, color).then((icon) {
        _pinsBeingBuilt.remove(key);
        if (mounted && icon != null) setState(() => _pins[key] = icon);
      });
    }
    return null;
  }

  // Shows the rider's dot right away, before the shared live stream has
  // produced its first reading.
  Future<void> _loadFallbackLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          isFreshFix(last, maxAge: const Duration(minutes: 5))) {
        if (mounted) {
          setState(
            () => _fallbackRiderLatLng = LatLng(last.latitude, last.longitude),
          );
        }
        return;
      }
      final now = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted && isReliableRiderFix(now, maxAccuracyMeters: 100)) {
        setState(
          () => _fallbackRiderLatLng = LatLng(now.latitude, now.longitude),
        );
      }
    } catch (_) {
      // No permission / no fix: the map still shows the customers.
    }
  }

  List<_OnTheWayCustomer> _parseCustomers(QuerySnapshot snap) {
    // Sorted by order id so every customer keeps the same colour.
    final docs = snap.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
    final list = <_OnTheWayCustomer>[];
    for (int i = 0; i < docs.length; i++) {
      final d = docs[i];
      final data = d.data() as Map<String, dynamic>;
      final lat = _toDouble(data['latitude']);
      final lng = _toDouble(data['longitude']);
      final hasCoords = lat != null && lng != null && !(lat == 0 && lng == 0);
      list.add(
        _OnTheWayCustomer(
          orderId: d.id,
          name: (data['customerName'] ?? data['customer_name'] ?? 'Customer')
              .toString(),
          address: (data['deliveryAddress'] ?? data['delivery_address'] ?? '')
              .toString(),
          position: hasCoords ? LatLng(lat, lng) : null,
          color: _kCustomerColors[i % _kCustomerColors.length],
        ),
      );
    }
    return list;
  }

  // Fetches / refreshes the road route from the rider to each customer.
  void _refreshRoutes(List<_OnTheWayCustomer> customers, LatLng rider) {
    if (!mounted) return;
    final now = DateTime.now();
    for (final c in customers) {
      final dest = c.position;
      if (dest == null || _fetching.contains(c.orderId)) continue;

      final lastAttempt = _lastAttemptAt[c.orderId];
      if (lastAttempt != null && now.difference(lastAttempt) < _minRefetchGap) {
        continue;
      }

      final existing = _routes[c.orderId];
      if (existing != null) {
        final moved = Geolocator.distanceBetween(
          existing.fetchedFrom.latitude,
          existing.fetchedFrom.longitude,
          rider.latitude,
          rider.longitude,
        );
        if (moved < _minMetersBeforeRefetch) continue;
      }

      _lastAttemptAt[c.orderId] = now;
      _fetchRoute(c.orderId, dest, rider);
    }
  }

  Future<void> _fetchRoute(String orderId, LatLng dest, LatLng rider) async {
    _fetching.add(orderId);
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${rider.latitude},${rider.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&key=${_OrderTrackingScreenState._directionsApiKey}',
      );
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

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final duration = (leg['duration'] as Map<String, dynamic>?)?['text'];
      final distance = (leg['distance'] as Map<String, dynamic>?)?['text'];
      final points = _decodePolylinePoints(
        route['overview_polyline']['points'] as String,
      );

      if (!mounted) return;
      setState(() {
        _routes[orderId] = _RouteInfo(
          points: points,
          durationText: (duration ?? '').toString(),
          distanceText: (distance ?? '').toString(),
          fetchedFrom: rider,
          fetchedAt: DateTime.now(),
        );
      });
    } catch (e) {
      debugPrint('Error fetching route for $orderId: $e');
    } finally {
      _fetching.remove(orderId);
    }
  }

  void _fitAll() {
    final controller = _mapController;
    if (controller == null) return;

    final points = <LatLng>[
      for (final c in _latestCustomers)
        if (c.position != null) c.position!,
      if (_latestRider != null) _latestRider!,
    ];
    if (points.isEmpty) return;

    if (points.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100,
      ),
    );
  }

  // Bottom list: one row per On the Way order (even ones that have no map
  // location, so it is always clear how many orders the rider has).
  Widget _buildCustomerList(List<_OnTheWayCustomer> customers) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          itemCount: customers.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = customers[i];
            final route = _routes[c.orderId];
            final String trailing;
            if (c.position == null) {
              trailing = 'No map location';
            } else if (route != null && route.durationText.isNotEmpty) {
              trailing = '${route.durationText} · ${route.distanceText}';
            } else {
              trailing = 'Calculating…';
            }

            return InkWell(
              onTap: c.position == null
                  ? null
                  : () => _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(c.position!, 16),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          if (c.address.isNotEmpty)
                            Text(
                              c.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trailing,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: c.position == null ? Colors.grey : c.color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Delivery Map',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your orders.'));
          }

          final customers = snapshot.hasData
              ? _parseCustomers(snapshot.data!)
              : <_OnTheWayCustomer>[];

          // Forget routes of orders that are no longer On the Way.
          _routes.removeWhere(
            (id, _) => !customers.any((c) => c.orderId == id),
          );

          return ValueListenableBuilder<Position?>(
            valueListenable: widget.riderController.riderPosition,
            builder: (context, pos, _) {
              final LatLng? rider = pos != null
                  ? LatLng(pos.latitude, pos.longitude)
                  : _fallbackRiderLatLng;

              _latestCustomers = customers;
              _latestRider = rider;

              if (rider != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _refreshRoutes(customers, rider),
                );
              }

              // Re-fit the camera whenever the SET of On the Way orders (or
              // whether the rider's position is known) changes - not on every
              // GPS update, so the rider can still pan/zoom freely.
              final ids = customers.map((c) => c.orderId).toList()..sort();
              final fitKey = '${ids.join(',')}|${rider != null}';
              if (fitKey != _lastFitKey && _mapController != null) {
                _lastFitKey = fitKey;
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
              }

              // Customers at the SAME place share one pin (otherwise one pin
              // would hide the other); their names are stacked on it.
              final groups = <String, List<_OnTheWayCustomer>>{};
              for (final c in customers) {
                final p = c.position;
                if (p == null) continue;
                final key =
                    '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
                groups.putIfAbsent(key, () => []).add(c);
              }

              final markers = <Marker>{};
              groups.forEach((key, list) {
                final lines = list.map((c) {
                  final eta = _routes[c.orderId]?.durationText ?? '';
                  return eta.isEmpty ? c.name : '${c.name} • $eta';
                }).toList();

                markers.add(
                  Marker(
                    markerId: MarkerId('group_$key'),
                    position: list.first.position!,
                    icon:
                        _pinFor(lines, list.first.color) ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                    // Bottom-center of the pin sits exactly on the address.
                    anchor: const Offset(0.5, 1.0),
                    infoWindow: InfoWindow(
                      title: list.map((c) => c.name).join(', '),
                      snippet: list.first.address,
                    ),
                  ),
                );
              });

              if (rider != null) {
                markers.add(
                  Marker(
                    markerId: const MarkerId('rider'),
                    position: rider,
                    icon:
                        _riderDotIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                    anchor: const Offset(0.5, 0.5),
                    infoWindow: const InfoWindow(title: 'You'),
                  ),
                );
              }

              final polylines = <Polyline>{
                for (final c in customers)
                  if (_routes[c.orderId] != null)
                    Polyline(
                      polylineId: PolylineId('route_${c.orderId}'),
                      points: _routes[c.orderId]!.points,
                      color: c.color,
                      width: 5,
                    ),
              };

              LatLng initialTarget = const LatLng(33.6844, 73.0479);
              for (final c in customers) {
                if (c.position != null) {
                  initialTarget = c.position!;
                  break;
                }
              }
              if (customers.every((c) => c.position == null) && rider != null) {
                initialTarget = rider;
              }

              // Keeps Google's logo / map controls above the list.
              final double listPadding = customers.isEmpty
                  ? 0
                  : (customers.length * 62.0 + 20).clamp(0, 190).toDouble();

              final String chipText = !snapshot.hasData
                  ? 'Loading orders…'
                  : customers.isEmpty
                  ? 'No orders are marked "On the Way" right now.'
                  : 'On the Way: ${customers.length} '
                        '${customers.length == 1 ? 'order' : 'orders'}';

              return Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: 13,
                    ),
                    padding: EdgeInsets.only(bottom: listPadding),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _lastFitKey = '${ids.join(',')}|${rider != null}';
                      _fitAll();
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: markers,
                    polylines: polylines,
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 64,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: Text(
                          chipText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter_deliveries_map',
                      backgroundColor: Colors.white,
                      onPressed: _fitAll,
                      child: const Icon(
                        Icons.center_focus_strong_rounded,
                        color: primary,
                      ),
                    ),
                  ),
                  if (customers.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildCustomerList(customers),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// Same decoding as in the single-order screen: turns the compact encoded
// string from the Directions API into the points of the route line.
List<LatLng> _decodePolylinePoints(String encoded) {
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
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}

// Blue "you are here" dot (a Marker icon keeps the same size at any zoom).
Future<BitmapDescriptor?> _buildRiderDotBitmap() async {
  try {
    const double size = 60;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size / 2,
      Paint()..color = Colors.blue.withValues(alpha: 0.25),
    );
    canvas.drawCircle(center, size / 3.2, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 4, Paint()..color = Colors.blue);

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  } catch (e) {
    debugPrint('Could not draw rider dot: $e');
    return null;
  }
}

// A pin in [color] with a white label above it holding one line per customer
// (name and travel time), drawn as one image so the text is always visible on
// the map (a normal marker only shows its title after being tapped).
Future<BitmapDescriptor?> _buildNamedPinBitmap(
  List<String> lines,
  Color color,
) async {
  try {
    final double dpr =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final double fontSize = 13 * dpr;
    final double padH = 9 * dpr;
    final double padV = 5 * dpr;
    final double gap = 2 * dpr;
    final double pinR = 8 * dpr; // radius of the pin head
    final double tail = 9 * dpr; // pointed bottom of the pin
    final double maxTextW = 190 * dpr;

    final paragraph =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: TextAlign.center,
                  maxLines: lines.length,
                  ellipsis: '…',
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  color: const Color(0xFF222222),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              )
              ..addText(lines.join('\n')))
            .build();
    paragraph.layout(ui.ParagraphConstraints(width: maxTextW));
    // Second pass with the real text width so the text sits centered in the
    // label instead of in the (wider) maximum-width box.
    final double textW = paragraph.longestLine.ceilToDouble() + 1;
    paragraph.layout(ui.ParagraphConstraints(width: textW));

    final double labelW = textW + padH * 2;
    final double labelH = paragraph.height + padV * 2;
    final double pinH = pinR * 2 + tail;
    final double w = labelW;
    final double h = labelH + gap + pinH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Label
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, labelH),
      Radius.circular(lines.length > 1 ? 14 * dpr : labelH / 2),
    );
    canvas.drawRRect(bubble, Paint()..color = Colors.white);
    canvas.drawRRect(
      bubble,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * dpr,
    );
    canvas.drawParagraph(paragraph, Offset(padH, padV));

    // Pin (head + pointed tail); the tip is the bottom-center of the image.
    final double cx = w / 2;
    final double headCy = labelH + gap + pinR;
    final pinPaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, headCy), pinR, pinPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx - pinR * 0.75, headCy + pinR * 0.55)
        ..lineTo(cx, h)
        ..lineTo(cx + pinR * 0.75, headCy + pinR * 0.55)
        ..close(),
      pinPaint,
    );
    canvas.drawCircle(
      Offset(cx, headCy),
      pinR * 0.38,
      Paint()..color = Colors.white,
    );

    final image = await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  } catch (e) {
    debugPrint('Could not draw customer pin: $e');
    return null;
  }
}
