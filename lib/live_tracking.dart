import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String orderId;
  const LiveTrackingScreen({super.key, required this.orderId});

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  static const primary = Color(0xFFA70000);
  static const accentOrange = Color(0xFFFF8A00);
  static const fieldBg = Color(0xFFFFFDFA);
  static const bgColor = Colors.white;

  GoogleMapController? _mapController;

  // Custom blue "dot" used for the rider's live location. A Marker icon keeps
  // the same pixel size at every zoom level, so the rider never disappears
  // when the map zooms out (a meters-based Circle alone would).
  BitmapDescriptor? _riderDotIcon;

  // The camera is fitted to "rider + delivery address" only ONCE. After that
  // the rider dot just moves, so the customer can zoom/pan freely without the
  // map snapping back on every location update. The recenter button re-fits.
  bool _initialFitDone = false;
  LatLng? _lastRiderLatLng;
  LatLng? _lastDestLatLng;

  @override
  void initState() {
    super.initState();
    _createRiderDotIcon();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _createRiderDotIcon() async {
    const double size = 64;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);

    // Soft outer halo
    canvas.drawCircle(
      center,
      size / 2,
      Paint()..color = Colors.blue.withValues(alpha: 0.25),
    );
    // White ring
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

  Future<void> _callRider(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider phone number is not available'),
          backgroundColor: primary,
        ),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone.trim());
    final launched = await launchUrl(uri);

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the phone dialer'),
          backgroundColor: primary,
        ),
      );
    }
  }

  // If the rider moves out of the visible part of the map, pan the camera so
  // the customer keeps seeing the rider (without resetting their zoom).
  Future<void> _keepRiderInView(LatLng rider) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      final region = await controller.getVisibleRegion();
      if (!region.contains(rider)) {
        controller.animateCamera(CameraUpdate.newLatLng(rider));
      }
    } catch (_) {}
  }

  void _fitTwoPinsOnScreen(LatLng riderLatLng, LatLng? destLatLng) {
    final controller = _mapController;
    if (controller == null) return;

    // Only the rider is known (or both are at the same spot): just center.
    if (destLatLng == null || destLatLng == riderLatLng) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(riderLatLng, 16));
      return;
    }

    final double minLat = riderLatLng.latitude < destLatLng.latitude
        ? riderLatLng.latitude
        : destLatLng.latitude;
    final double maxLat = riderLatLng.latitude > destLatLng.latitude
        ? riderLatLng.latitude
        : destLatLng.latitude;
    final double minLng = riderLatLng.longitude < destLatLng.longitude
        ? riderLatLng.longitude
        : destLatLng.longitude;
    final double maxLng = riderLatLng.longitude > destLatLng.longitude
        ? riderLatLng.longitude
        : destLatLng.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Track Order',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          // The rider app writes "orderStatus" (camelCase); the old
          // "order_status" is only kept as a fallback for very old orders.
          final String status =
              (data['orderStatus'] ?? data['order_status'] ?? 'Accepted')
                  .toString();

          // Rider live location (written by the rider app).
          final double? riderLat = (data['riderLat'] as num?)?.toDouble();
          final double? riderLng = (data['riderLng'] as num?)?.toDouble();
          // Customer's delivery address location (saved when the order was placed).
          final double? destLat = (data['latitude'] as num?)?.toDouble();
          final double? destLng = (data['longitude'] as num?)?.toDouble();

          final String riderName = data['riderName'] ?? 'Rider';
          final String? riderPhone =
              (data['riderPhone'] ?? data['phone_number']) as String?;

          final bool hasRiderLocation = riderLat != null && riderLng != null;
          final bool hasDestination = destLat != null && destLng != null;

          if (status.toLowerCase() == 'delivered') {
            return _buildDeliveredView(context, riderName);
          }

          if (!hasRiderLocation) {
            return _buildWaitingForLocationView(context, riderName);
          }

          final riderLatLng = LatLng(riderLat, riderLng);
          final LatLng? destLatLng = hasDestination
              ? LatLng(destLat, destLng)
              : null;

          _lastRiderLatLng = riderLatLng;
          _lastDestLatLng = destLatLng;

          // Fit the camera the first time only (map may not exist yet on the
          // very first build - onMapCreated handles that case).
          if (!_initialFitDone && _mapController != null) {
            _initialFitDone = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitTwoPinsOnScreen(riderLatLng, destLatLng);
            });
          } else if (_initialFitDone) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _keepRiderInView(riderLatLng);
            });
          }

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          (riderLat + (destLat ?? riderLat)) / 2,
                          (riderLng + (destLng ?? riderLng)) / 2,
                        ),
                        zoom: 14,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                        if (!_initialFitDone) {
                          _initialFitDone = true;
                          _fitTwoPinsOnScreen(riderLatLng, destLatLng);
                        }
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      // Rider = circle (blue dot with a soft halo) that moves live.
                      circles: {
                        Circle(
                          circleId: const CircleId('rider_halo'),
                          center: riderLatLng,
                          radius: 40,
                          fillColor: Colors.blue.withValues(alpha: 0.15),
                          strokeColor: Colors.blue.withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                      },
                      markers: {
                        // Rider dot: always visible at any zoom level.
                        Marker(
                          markerId: const MarkerId('rider'),
                          position: riderLatLng,
                          icon:
                              _riderDotIcon ??
                              BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueAzure,
                              ),
                          anchor: const Offset(0.5, 0.5),
                          flat: true,
                          infoWindow: InfoWindow(title: 'Rider: $riderName'),
                        ),
                        // Customer = red pin at the delivery address.
                        if (destLatLng != null)
                          Marker(
                            markerId: const MarkerId('destination'),
                            position: destLatLng,
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed,
                            ),
                            infoWindow: const InfoWindow(
                              title: 'Delivery Address',
                            ),
                          ),
                      },
                    ),
                    // Re-fit button: shows both rider and delivery address again.
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'recenter_tracking',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          final r = _lastRiderLatLng;
                          if (r != null) {
                            _fitTwoPinsOnScreen(r, _lastDestLatLng);
                          }
                        },
                        child: const Icon(
                          Icons.center_focus_strong_rounded,
                          color: primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: primary.withValues(alpha: 0.12),
                        child: const Icon(
                          Icons.delivery_dining,
                          color: primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              riderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: _statusColor(status),
                                  size: 8,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  status,
                                  style: TextStyle(
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => _callRider(context, riderPhone),
                        borderRadius: BorderRadius.circular(50),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWaitingForLocationView(BuildContext context, String riderName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(
                      color: accentOrange,
                      strokeWidth: 3,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delivery_dining,
                      color: primary,
                      size: 32,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                "$riderName hasn't turned on location yet",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Live tracking will start here automatically once the rider turns on GPS.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveredView(BuildContext context, String riderName) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade700,
                size: 72,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Order Delivered!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$riderName has successfully delivered your order.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Back',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Picked Up':
        return Colors.blue.shade700;
      case 'On The Way':
      case 'On the Way':
        return Colors.orange.shade700;
      case 'Delivered':
        return Colors.green.shade700;
      default:
        return primary;
    }
  }
}