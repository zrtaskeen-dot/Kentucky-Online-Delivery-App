
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../notification_service.dart';



bool isReliableRiderFix(Position p, {double maxAccuracyMeters = 50}) {
  if (p.accuracy > 0 && p.accuracy > maxAccuracyMeters) return false;
  return true;
}


bool isFreshFix(Position p, {Duration maxAge = const Duration(seconds: 60)}) {
  final DateTime ts = p.timestamp;
  return DateTime.now().difference(ts) <= maxAge;
}

class RiderController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  StreamSubscription<Position>? _positionStreamSubscription;

  
  final Set<String> _trackedOrderIds = {};
  Position? _lastPosition;
  bool _startingStream = false;

 
  final ValueNotifier<Position?> riderPosition = ValueNotifier<Position?>(null);

 
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
      case 'On the Way':
        body = 'Your rider is on the way to you ';
        break;
      case 'Delivered':
        body = 'Your order has been delivered. Enjoy your meal!';
        break;
      case 'Undelivered':
        body =
            'We could not deliver your order. Please contact the restaurant for details.';
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

 
  Stream<QuerySnapshot> getPendingOrders(String riderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('orderStatus', isEqualTo: 'Pending')
        .snapshots();
  }

  
  Stream<QuerySnapshot> getAcceptedOrders(String riderId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('riderId', isEqualTo: riderId)
        .where('orderStatus', whereIn: ['Accepted', 'Picked Up', 'On the Way'])
        .snapshots();
  }

 
  Future<void> toggleAvailability(String riderId, bool newStatus) async {
    _setLoading(true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(riderId).update({
        'isAvailable': newStatus,
       
        'lastSeen': FieldValue.serverTimestamp(),
      });
      debugPrint('Rider availability updated to: $newStatus');
    } catch (e) {
      debugPrint('Error updating availability: $e');
    } finally {
      _setLoading(false);
    }
  }

  
  Future<void> sendHeartbeat(String riderId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(riderId).update({
        'isAvailable': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Heartbeat failed: $e');
    }
  }

  
  static bool isRiderOnline(
    Map<String, dynamic> data, {
    Duration maxAge = const Duration(milliseconds: 2500),
  }) {
    if (data['isAvailable'] != true) return false;
    final seen = data['lastSeen'];
    if (seen is! Timestamp) return false;
    return DateTime.now().difference(seen.toDate()) <= maxAge;
  }

  // Accept Order 
  
  Future<bool> acceptOrder(
    String orderId,
    String riderId,
    String customerId,
  ) async {
    _setLoading(true);
    _setError('');

    try {
      
      String riderName = '';
      String riderPhone = '';
      try {
        final riderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(riderId)
            .get();
        riderName = (riderDoc.data()?['name'] ?? '').toString();
        riderPhone = (riderDoc.data()?['phone'] ?? '').toString();
      } catch (e) {
        debugPrint('Could not read rider profile for the order: $e');
      }

      await FirebaseFirestore.instance.collection('orders').doc(orderId).update(
        {
         
          'orderStatus': 'Accepted',
          'order_status': FieldValue.delete(),
          'riderId': riderId,
          if (riderName.isNotEmpty) 'riderName': riderName,
          if (riderPhone.isNotEmpty) 'riderPhone': riderPhone,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
      );

      // In-app notification to the customer, with the rider's name
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

 
  String _statusOf(Map<String, dynamic>? data) {
    final camel = (data?['orderStatus'] ?? '').toString();
    final snake = (data?['order_status'] ?? '').toString();
    if (snake.isNotEmpty && snake.toLowerCase() != 'pending') return snake;
    if (camel.isNotEmpty && camel.toLowerCase() != 'pending') return camel;
    return camel.isNotEmpty ? camel : snake;
  }

  bool _isFinalStatus(String status) {
    final s = status.toLowerCase().trim();
    return s == 'delivered' ||
        s == 'undelivered' ||
        s == 'cancelled' ||
        s == 'canceled';
  }

  bool _canMove(String current, String target) {
    final c = current.toLowerCase().trim();
    switch (target) {
      case 'On the Way':
        return c == 'accepted' || c == 'picked up';
      case 'Delivered':
        return c == 'on the way' || c == 'picked up';
      default:
        return !_isFinalStatus(current);
    }
  }

  
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    _setLoading(true);
    _setError('');
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId);

      String customerId = '';
      String blockedBy = '';

      final String outcome = await FirebaseFirestore.instance
          .runTransaction<String>((tx) async {
            final snap = await tx.get(orderRef);
            final data = snap.data();
            if (data == null) return 'missing';

            customerId = (data['customerId'] ?? data['userId'] ?? '')
                .toString();
            final current = _statusOf(data);

            if (current == newStatus) return 'same'; 
            if (!_canMove(current, newStatus)) {
              blockedBy = current;
              return 'blocked';
            }

            tx.update(orderRef, {
              'orderStatus': newStatus,
              'order_status': FieldValue.delete(),
              'statusUpdatedAt': FieldValue.serverTimestamp(),
            });
            return 'applied';
          });

      if (outcome == 'missing') {
        _setError('Order not found');
        _setLoading(false);
        return false;
      }
      if (outcome == 'blocked') {
        _setError(
          _isFinalStatus(blockedBy)
              ? 'Order is already $blockedBy'
              : 'Order must be On the Way first',
        );
        _setLoading(false);
        return false;
      }
      if (outcome == 'same') {
        _setLoading(false);
        return true; 
      }

      
      _notifyCustomerOfStatus(
        customerId: customerId,
        status: newStatus,
      ).catchError((e) => debugPrint('Error notifying customer: $e'));

      if (newStatus == 'On the Way') {
        // Live location is written to this order until it is delivered
        startLiveLocationTracking(orderId);
      } else if (newStatus == 'Delivered') {
        // Only this order stops being track
        stopTrackingOrder(orderId);
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

  
  Future<bool> markUndelivered(
    String orderId,
    String reason, {
    String note = '',
  }) async {
    _setLoading(true);
    _setError('');
    try {
      final orderRef = FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId);

      String customerId = '';
      String blockedBy = '';

      
      final String outcome = await FirebaseFirestore.instance
          .runTransaction<String>((tx) async {
            final snap = await tx.get(orderRef);
            final data = snap.data();
            if (data == null) return 'missing';

            customerId = (data['customerId'] ?? data['userId'] ?? '')
                .toString();
            final current = _statusOf(data);
            final c = current.toLowerCase().trim();

            if (c == 'undelivered') return 'same'; // already saved
            if (c != 'accepted' && c != 'on the way' && c != 'picked up') {
              blockedBy = current;
              return 'blocked';
            }

            tx.update(orderRef, {
              'orderStatus': 'Undelivered',
              'order_status': FieldValue.delete(),
              'undeliveredReason': reason,
              if (note.trim().isNotEmpty) 'undeliveredNote': note.trim(),
              'undeliveredAt': FieldValue.serverTimestamp(),
              'statusUpdatedAt': FieldValue.serverTimestamp(),
            });
            return 'applied';
          });

      if (outcome == 'missing') {
        _setError('Order not found');
        _setLoading(false);
        return false;
      }
      if (outcome == 'blocked') {
        _setError('Order is already $blockedBy');
        _setLoading(false);
        return false;
      }
      if (outcome == 'same') {
        _setLoading(false);
        return true;
      }

      _notifyCustomerOfStatus(
        customerId: customerId,
        status: 'Undelivered',
      ).catchError((e) => debugPrint('Error notifying customer: $e'));

      // No more live location for this order
      stopTrackingOrder(orderId);

      debugPrint('Order $orderId marked Undelivered: $reason');
      _setLoading(false);
      return true;
    } catch (e) {
      _setError(e.toString());
      debugPrint('Error marking order undelivered: $e');
      _setLoading(false);
      return false;
    }
  }

  
 

  
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

  // Live GPS Location Tracking works for many orders 
 
  Future<void> startLiveLocationTracking(String orderId) async {
    _trackedOrderIds.add(orderId);

    if (_positionStreamSubscription == null) {
      await _ensureLocationStream();
    } else if (_lastPosition != null) {
      _writeLocationToOrder(orderId, _lastPosition!);
    }
  }

  // Stops tracking order  after it is delivered
  void stopTrackingOrder(String orderId) {
    _trackedOrderIds.remove(orderId);
    if (_trackedOrderIds.isEmpty) {
      stopLiveLocationTracking();
    }
  }

  
  void syncOnTheWayOrders(Iterable<String> onTheWayOrderIds) {
    final wanted = onTheWayOrderIds.toSet();
    final added = wanted.difference(_trackedOrderIds);

    _trackedOrderIds
      ..clear()
      ..addAll(wanted);

    if (wanted.isEmpty) {
      stopLiveLocationTracking();
      return;
    }

    if (_positionStreamSubscription == null) {
      _ensureLocationStream();
    } else if (_lastPosition != null) {
      for (final id in added) {
        _writeLocationToOrder(id, _lastPosition!);
      }
    }
  }

  
  Future<void> _ensureLocationStream() async {
    if (_positionStreamSubscription != null || _startingStream) return;
    _startingStream = true;

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
          debugPrint('Location permissions denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions permanently denied.');
        return;
      }

      
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: _backgroundLocationSettings(),
          ).listen((Position position) {
            if (!isReliableRiderFix(position)) return; // skip weak GPS
            _onNewPosition(position);
          }, onError: (e) => debugPrint('Location stream error: $e'));

     
      try {
        Position? firstPosition;
        try {
          firstPosition = await Geolocator.getCurrentPosition(
            // ignore: deprecated_member_use
            desiredAccuracy: LocationAccuracy.high,
            // ignore: deprecated_member_use
            timeLimit: const Duration(seconds: 10),
          );
        } catch (_) {
          
          final last = await Geolocator.getLastKnownPosition();
          if (last != null && isFreshFix(last)) firstPosition = last;
        }
        if (firstPosition != null &&
            isReliableRiderFix(firstPosition, maxAccuracyMeters: 100)) {
          _onNewPosition(firstPosition);
        }
      } catch (e) {
        debugPrint('Error getting first location: $e');
      }
    } catch (e) {
      debugPrint('Error starting live location: $e');
    } finally {
      _startingStream = false;
    }
  }

  
  void _onNewPosition(Position position) {
    _lastPosition = position;
    riderPosition.value = position;
    for (final orderId in _trackedOrderIds.toList()) {
      _writeLocationToOrder(orderId, position);
    }
  }

  
  LocationSettings _backgroundLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Delivery in progress',
          notificationText: 'Sharing your live location with the customer',
          notificationChannelName: 'Delivery tracking',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );
  }

  void _writeLocationToOrder(String orderId, Position position) {
    FirebaseFirestore.instance
        .collection('orders')
        .doc(orderId)
        .update({'riderLat': position.latitude, 'riderLng': position.longitude})
        .catchError((e) {
          debugPrint('Error updating live location for $orderId: $e');
        });
  }

  
  void stopLiveLocationTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _trackedOrderIds.clear();
    _lastPosition = null;
    riderPosition.value = null;
    debugPrint(' Live location tracking stopped.');
  }

  @override
  void dispose() {
    stopLiveLocationTracking();
    riderPosition.dispose();
    super.dispose();
  }
}
