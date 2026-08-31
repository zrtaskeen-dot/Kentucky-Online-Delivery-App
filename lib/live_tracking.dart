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
  static const primary = Color(0xFFA62600);
  static const bgColor = Color(0xFFFFFDF0);

  GoogleMapController? _mapController;

  Future<void> _callRider(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rider number available nahi hai'),
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
          content: Text('Call open nahi ho saka'),
          backgroundColor: primary,
        ),
      );
    }
  }

  // 🧭 Dono Pins ko Screen mein auto-fit karne ka logic
  void _fitTwoPinsOnScreen(LatLng riderLatLng, LatLng destLatLng) {
    if (_mapController == null) return;

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

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding for clear view
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Track Order',
          style: TextStyle(
            color: Colors.black87,
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
          final status = data['order_status'] ?? 'Accepted';

          // Firestore Coordinates Parsing
          final double? riderLat = (data['riderLat'] as num?)?.toDouble();
          final double? riderLng = (data['riderLng'] as num?)?.toDouble();
          final double? destLat = (data['latitude'] as num?)?.toDouble();
          final double? destLng = (data['longitude'] as num?)?.toDouble();

          final String riderName = data['riderName'] ?? 'Rider';
          // Rider Phone fallback (riderPhone or phone_number)
          final String? riderPhone =
              (data['riderPhone'] ?? data['phone_number']) as String?;

          final bool hasRiderLocation = riderLat != null && riderLng != null;
          final bool hasDestination = destLat != null && destLng != null;

          if (status == 'Delivered') {
            return _buildDeliveredView(context, riderName);
          }

          if (!hasRiderLocation) {
            return _buildWaitingForLocationView(context, riderName);
          }

          final riderLatLng = LatLng(riderLat, riderLng);
          final destLatLng = hasDestination ? LatLng(destLat, destLng) : null;

          // Camera Bounds Update Frame ke baad
          if (destLatLng != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitTwoPinsOnScreen(riderLatLng, destLatLng);
            });
          }

          return Column(
            children: [
              Expanded(
                child: GoogleMap(
                  // Center between coordinates on load with wider zoom (10)
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      (riderLat + (destLat ?? riderLat)) / 2,
                      (riderLng + (destLng ?? riderLng)) / 2,
                    ),
                    zoom: 10,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (destLatLng != null) {
                      _fitTwoPinsOnScreen(riderLatLng, destLatLng);
                    }
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  markers: {
                    // 1. Rider Marker (Orange)
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: riderLatLng,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                      infoWindow: InfoWindow(title: 'Rider: $riderName'),
                    ),

                    // 2. Customer Destination Marker (Red)
                    if (destLatLng != null)
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: destLatLng,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                        infoWindow: const InfoWindow(title: 'Delivery Address'),
                      ),
                  },
                ),
              ),

              // Rider Details Bottom Card
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
                      const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFFEEEEEE),
                        child: Icon(
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: primary),
            const SizedBox(height: 24),
            Text(
              '$riderName ne abhi apni location enable nahi ki',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rider ke GPS on karte hi live tracking yahan\nautomatically shuru ho jayegi.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
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
              '$riderName ne aapka order successfully deliver kar diya hai.',
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
      case 'On the Way':
        return Colors.orange.shade700;
      case 'Delivered':
        return Colors.green.shade700;
      default:
        return primary;
    }
  }
}
