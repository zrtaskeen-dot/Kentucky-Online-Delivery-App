import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../notification_service.dart';

class RiderController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  StreamSubscription<Position>? _positionStreamSubscription;

  // Builds a friendly in-app notification for the customer based on the
  // new order status. For 'Accepted' it looks up the rider's name so the
  // message can say who accepted the order.
  Future<void> _notifyCustomerOfStatus({
    required String customerId,
    required String status,
    String? riderId,
  }) async {
    if (customerId.isEmpty) return;

    String body;
    switch (status) {
      case 'Accepted':
        String riderName = 'A rider';
        if (riderId != null && riderId.isNotEmpty) {
          final riderDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(riderId)
              .get();
          riderName = riderDoc.data()?['name'] ?? riderName;
        }
        body = '$riderName has accepted your order and will pick it up soon.';
        break;
      case 'Delivery Started':
        body = 'Your rider has started heading your way.';
        break;
      case 'Picked Up':
        body = 'Your order has been picked up and is on its way.';
        break;
      case 'On the Way':
        body = 'Your rider is on the way to you 🛵';
        break;
      case 'Delivered':
        body = 'Your order has been delivered. Enjoy your meal!';
        break;
      default:
        body = 'Your order status is now: $status';
    }

    await NotificationService.notifyCustomer(
      customerId: customerId,
      title: 'Order Status Update',
      body: body,
    );
  }

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
        .where('orderStatus', isEqualTo: 'Pending')
        .snapshots();
  }

  // 2. Accepted Orders Stream
  Stream<QuerySnapshot> getAcceptedOrders(String riderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('riderId', isEqualTo: riderId)
        .where(
          'orderStatus',
          whereIn: ['Accepted', 'Delivery Started', 'Picked Up', 'On the Way'],
        )
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
  // No restriction here — a rider can accept as many orders as they want
  // (they just sit in "Accepted" state). The one-active-delivery rule is
  // enforced separately in updateOrderStatus() when a rider tries to
  // actually START a delivery (transition to "Picked Up").
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
            'orderStatus': 'Accepted',
            'riderId': riderId,
            'acceptedAt': FieldValue.serverTimestamp(),
          });

      // In-app notification to the customer, with the rider's name.
      await _notifyCustomerOfStatus(
        customerId: customerId,
        status: 'Accepted',
        riderId: riderId,
      );

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      debugPrint('Error accepting order: $e');
      _setLoading(false);
      return false;
    }
  }

  // 4b. Update Order Status (Picked Up / On the Way / Delivered / etc.)
  // Writes the new status to Firestore, then sends the customer an in-app
  // notification (no Cloud Functions / backend server involved — it's
  // just a document written to the `notifications` collection, which
  // NotificationScreen listens to live).
  //
  // One-active-delivery rule: a rider can have many orders sitting in
  // "Accepted", but can only be actually OUT delivering one at a time.
  // So the check happens specifically on the transition into "Picked Up"
  // — that's the moment a delivery actually "starts". Once an order is
  // already Picked Up, moving it on to "On the Way" / "Delivered" never
  // hits this check (it's the same delivery continuing).
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    _setLoading(true);
    _setError('');
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId);

      // Read first so we know the riderId/customerId before writing.
      final orderSnap = await orderRef.get();
      final orderData = orderSnap.data();
      final riderId = (orderData?['riderId'] ?? '').toString();
      final customerId =
          (orderData?['customerId'] ?? orderData?['userId'] ?? '').toString();

      // One-active-delivery rule: a rider can have many orders sitting in
      // "Accepted", but can only be actually OUT delivering one at a
      // time. "Delivery Started" is the moment a delivery actually
      // begins (rider tapped "Start Delivery"), so the check happens
      // right there — not later at "Picked Up". Once a delivery has
      // started, moving it on to "Picked Up" / "On the Way" / "Delivered"
      // never hits this check again (it's the same delivery continuing).
      if (newStatus == 'Delivery Started' && riderId.isNotEmpty) {
        final activeSnap = await FirebaseFirestore.instance
            .collection('orders')
            .where('riderId', isEqualTo: riderId)
            .where(
              'orderStatus',
              whereIn: ['Delivery Started', 'Picked Up', 'On the Way'],
            )
            .get();
        final hasOtherActiveDelivery = activeSnap.docs.any(
          (d) => d.id != orderId,
        );

        if (hasOtherActiveDelivery) {
          _setError(
            'You already have a delivery in progress. Please complete it before starting another.',
          );
          _setLoading(false);
          return false;
        }
      }

      await orderRef.update({
        'orderStatus': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Fire-and-forget: notifying the customer (and whatever network
      // call that involves) should never hold up the rider's own
      // confirmation. Awaiting this before returning was what caused a
      // noticeable delay before the "Order marked as ..." message
      // appeared on screen.
      _notifyCustomerOfStatus(
        customerId: customerId,
        status: newStatus,
      ).catchError((e) => debugPrint('Error notifying customer: $e'));

      if (newStatus == 'Picked Up') {
        // Rider has the food in hand now — begin GPS tracking.
        startLiveLocationTracking(orderId);
      } else if (newStatus == 'Delivered') {
        stopLiveLocationTracking();
      }

      debugPrint('Order $orderId status updated to: $newStatus');
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      debugPrint('Error updating order status: $e');
      _setLoading(false);
      return false;
    }
  }

  // 5. Launch Maps Navigation for Customer Address
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

  // 6. Live GPS Location Tracking
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

  // 7. Stop Live Location Tracking
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
