import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class RiderController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  StreamSubscription<Position>? _positionStreamSubscription;

  // ⚠️ IP ADDRESS CONFIGURATION:
  // - Real Device / Wi-Fi: Use your laptop's IPv4 address (e.g., http://192.168.1.7:3000)
  // - Android Emulator: http://10.0.2.2:3000
  // 👈 FIX: this was previously named "baseUrl" (with the "/send-notification"
  // path already attached) but the code below referenced "_backendBaseUrl",
  // which didn't exist — that mismatch caused the notification call to fail.
  final String _backendBaseUrl = 'http://192.168.1.36:3000';

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String msg) {
    _error = msg;
    notifyListeners();
  }

  // 1. Pending Orders Stream
  Stream<QuerySnapshot> getPendingOrders(String riderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('order_status', isEqualTo: 'Pending')
        .snapshots();
  }

  // 2. Accepted Orders Stream
  Stream<QuerySnapshot> getAcceptedOrders(String riderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('riderId', isEqualTo: riderId)
        .where('order_status', whereIn: ['Accepted', 'On The Way'])
        .snapshots();
  }

  // 3. Toggle Rider Availability Status
  Future<void> toggleAvailability(String riderId, bool newStatus) async {
    _setLoading(true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(riderId).update({
        'isAvailable': newStatus,
      });
      debugPrint('Rider availability updated to: $newStatus');
    } catch (e) {
      debugPrint('Error updating availability: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 4. Accept Order Method
  Future<bool> acceptOrder(
    String orderId,
    String riderId,
    String customerId,
  ) async {
    _setLoading(true);
    _setError('');

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({
            'order_status': 'Accepted',
            'riderId': riderId,
            'acceptedAt': FieldValue.serverTimestamp(),
          });

      // Send FCM notification to Customer
      if (customerId.isNotEmpty) {
        await notifyCustomerForStatus(customerId, 'Accepted');
      }

      // Start real-time GPS tracking
      startLiveLocationTracking(orderId);
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      debugPrint( 'Error accepting order: $e');
      _setLoading(false);
      return false;
    }
  }

  // 5. Send Push Notification via Node.js Backend
  Future<void> notifyCustomerForStatus(String customerId, String status) async {
    try {
      debugPrint('Fetching FCM token for Customer ID: $customerId');

      // Fetch Customer user doc from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .get();

      if (!userDoc.exists) {
        debugPrint('Customer user document does not exist!');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>?;
      String? customerToken = userData?['fcmToken'];

      if (customerToken == null || customerToken.isEmpty) {
        debugPrint('Customer fcmToken is missing or empty in Firestore!');
        return;
      }

      debugPrint('Sending notification request to backend...');

      final response = await http.post(
        Uri.parse('$_backendBaseUrl/send-notification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fcmToken': customerToken,
          'title': 'Order Status Update 🛵',
          'body': 'Your order status is now: $status',
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM Notification Sent: ${response.body}');
      } else {
        debugPrint(
          'Backend API Error [${response.statusCode}]: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Exception sending notification request: $e');
    }
  }

  // 6. Launch Maps Navigation for Customer Address
  Future<void> launchCustomerNavigation({
    required double? lat,
    required double? lng,
    required String fallbackAddress,
  }) async {
    Uri mapUri;

    if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      mapUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    } else {
      final query = Uri.encodeComponent(fallbackAddress);
      mapUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$query',
      );
    }

    try {
      if (await canLaunchUrl(mapUri)) {
        await launchUrl(mapUri, mode: LaunchMode.externalApplication);
      } else {
        final webUri = Uri.parse(
          lat != null && lng != null
              ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
              : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(fallbackAddress)}',
        );
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching maps navigation: $e');
    }
  }

  // 7. Live GPS Location Tracking
  void startLiveLocationTracking(String orderId) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions denied.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint(' Location permissions permanently denied.');
      return;
    }

    _positionStreamSubscription?.cancel();

    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          FirebaseFirestore.instance
              .collection('orders')
              .doc(orderId)
              .update({
                'riderLatitude': position.latitude,
                'riderLongitude': position.longitude,
                'lastLocationUpdate': FieldValue.serverTimestamp(),
              })
              .catchError((e) {
                debugPrint('Error updating live location: $e');
              });
        });
  }

  // 8. Stop Live Location Tracking
  void stopLiveLocationTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    debugPrint(' Live location tracking stopped.');
  }

  @override
  void dispose() {
    stopLiveLocationTracking();
    super.dispose();
  }
}