import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../notification_service.dart';

/// A GPS reading reports how accurate it is (radius in meters). Weak readings
/// (indoors, cell-tower/Wi-Fi based) can be hundreds of meters or even
/// kilometers off, which is what made the rider appear in a wrong area on the
/// customer's map. Only readings tighter than [maxAccuracyMeters] are uploaded.
bool isReliableRiderFix(Position p, {double maxAccuracyMeters = 50}) {
  if (p.accuracy > 0 && p.accuracy > maxAccuracyMeters) return false;
  return true;
}

/// A cached "last known" position can be hours old and far away, so it is only
/// used if it is recent.
bool isFreshFix(Position p, {Duration maxAge = const Duration(seconds: 60)}) {
  final DateTime? ts = p.timestamp;
  if (ts == null) return false;
  return DateTime.now().difference(ts) <= maxAge;
}

class RiderController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String _error = '';
  String get error => _error;

  StreamSubscription<Position>? _positionStreamSubscription;

  // Orders that are currently "On the Way". ONE GPS stream is shared by all of
  // them: every new reading is written to every order in this set, so each
  // customer sees the same live rider location on their own tracking map.
  final Set<String> _trackedOrderIds = {};
  Position? _lastPosition;
  bool _startingStream = false;

  // Latest reliable rider position, for screens that draw the rider (the
  // rider's delivery map). A ValueNotifier, so GPS updates only rebuild the
  // widgets that listen to it instead of the whole app.
  final ValueNotifier<Position?> riderPosition = ValueNotifier<Position?>(null);

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
      case 'On the Way':
        body = 'Your rider is on the way to you 🛵';
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
        .where('orderStatus', whereIn: ['Accepted', 'Picked Up', 'On the Way'])
        .snapshots();
  }

  // 3. Toggle Rider Availability Status
  Future<void> toggleAvailability(String riderId, bool newStatus) async {
    _setLoading(true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(riderId).update({
        'isAvailable': newStatus,
        // Every availability change also counts as a check-in.
        'lastSeen': FieldValue.serverTimestamp(),
      });
      debugPrint('Rider availability updated to: $newStatus');
    } catch (e) {
      debugPrint('Error updating availability: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 3b. Heartbeat — called every ~1s while the app is in the foreground — WARNING: this writes to Firestore once per second per online rider, which is costly at scale and close to Firestore's recommended per-document write rate limit.
  // A closed/killed app can't reliably write "isAvailable: false" (the
  // OS may kill it before the write goes out, or the phone may be
  // offline), so the manager side must NOT trust isAvailable alone.
  // It should also check that `lastSeen` is recent — see isRiderOnline().
  // Deliberately does not touch _isLoading so the UI doesn't rebuild.
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

  // Use this everywhere the manager lists or assigns riders. A rider is
  // online only if they flagged themselves available AND their app has
  // checked in within [maxAge] (a couple missed 1s heartbeats by default).
  static bool isRiderOnline(
    Map<String, dynamic> data, {
    Duration maxAge = const Duration(milliseconds: 2500),
  }) {
    if (data['isAvailable'] != true) return false;
    final seen = data['lastSeen'];
    if (seen is! Timestamp) return false;
    return DateTime.now().difference(seen.toDate()) <= maxAge;
  }

  // 4. Accept Order Method
  // No restriction here — a rider can accept as many orders as they want
  // (they just sit in "Accepted" state until the rider taps "On the Way").
  Future<bool> acceptOrder(
    String orderId,
    String riderId,
    String customerId,
  ) async {
    _setLoading(true);
    _setError('');

    try {
      // The rider's name and phone are copied onto the order, so the
      // customer's tracking screen can show the name and call the rider
      // without having to read the rider's profile.
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
          // Only ever write the camelCase field now. The stray
          // 'order_status' (snake_case) some other part of the system
          // writes is what caused a document to end up with two
          // conflicting status fields — deleting it here cleans up any
          // order the rider touches, on top of the one-time migration
          // that cleans up everything else already in the database.
          'orderStatus': 'Accepted',
          'order_status': FieldValue.delete(),
          'riderId': riderId,
          if (riderName.isNotEmpty) 'riderName': riderName,
          if (riderPhone.isNotEmpty) 'riderPhone': riderPhone,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
      );

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

  // 4b. Update Order Status (On the Way / Delivered / etc.)
  // Writes the new status to Firestore, then sends the customer an in-app
  // notification (no Cloud Functions / backend server involved — it's
  // just a document written to the `notifications` collection, which
  // NotificationScreen listens to live).
  //
  // There is NO one-delivery-at-a-time rule: a rider can mark as many orders
  // "On the Way" as they like. Every "On the Way" order gets the rider's live
  // GPS location (see startLiveLocationTracking below); "Delivered" removes
  // just that one order from tracking.
  // Status as stored on the order (same rule as resolveOrderStatus on the
  // home screen).
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

  // Accepted -> On the Way -> Delivered. A final status never changes.
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

  // Reads the order's CURRENT status from Firestore and writes the new one in
  // the same transaction, so a stale button or a double tap can never move an
  // order backwards (e.g. Delivered -> anything else).
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

            if (current == newStatus) return 'same'; // already done
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
        return true; // nothing to do, no second notification
      }

      // Fire-and-forget: the customer notification must never delay the
      // rider's own confirmation.
      _notifyCustomerOfStatus(
        customerId: customerId,
        status: newStatus,
      ).catchError((e) => debugPrint('Error notifying customer: $e'));

      if (newStatus == 'On the Way') {
        // Live location is written to this order until it is delivered.
        startLiveLocationTracking(orderId);
      } else if (newStatus == 'Delivered') {
        // Only this order stops being tracked.
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

  // 4c. Mark an order as Undelivered (the rider could not hand it over).
  // Saves WHY (picked by the rider from a list) so the manager can see it:
  //   orderStatus        -> 'Undelivered'
  //   undeliveredReason  -> the reason the rider selected
  //   undeliveredNote    -> free text, only when the reason is "Other"
  //   undeliveredAt      -> when
  // Live tracking of this order stops. Returns true on success.
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

      // Only an order that is still open (Accepted / On the Way) can become
      // Undelivered; a Delivered or Cancelled order can never be changed.
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

      // No more live location for this order.
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

  // ── ONE-TIME CLEANUP ──────────────────────────────────────────────
  // Scans every order in the database and removes the stray
  // 'order_status' (snake_case) field, keeping only 'orderStatus'
  // (camelCase) as the single source of truth. Safe to run more than
  // once — orders that only have 'orderStatus' are left untouched.
  //
  // Run this ONCE (e.g. from a temporary debug button), then it can be
  // removed. Note: this only cleans up existing data — if whatever part
  // of the system currently WRITES 'order_status' (order assignment,
  // outside this file) isn't also updated to stop, that field will keep
  // reappearing on newly-assigned orders.
  Future<int> migrateOrderStatusField() async {
    final firestore = FirebaseFirestore.instance;
    final snapshot = await firestore.collection('orders').get();

    int migratedCount = 0;
    WriteBatch batch = firestore.batch();
    int opsInBatch = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (!data.containsKey('order_status')) continue;

      final camel = (data['orderStatus'] ?? '').toString();
      final snake = (data['order_status'] ?? '').toString();

      // Same "trust whichever isn't still 'pending'" rule used to read
      // these fields elsewhere in the app, so the value that survives
      // is the correct/current one, not whichever field happened to be
      // written first.
      String resolved;
      if (snake.isNotEmpty && snake.toLowerCase() != 'pending') {
        resolved = snake;
      } else if (camel.isNotEmpty && camel.toLowerCase() != 'pending') {
        resolved = camel;
      } else {
        resolved = camel.isNotEmpty ? camel : snake;
      }

      batch.update(doc.reference, {
        'orderStatus': resolved,
        'order_status': FieldValue.delete(),
      });
      migratedCount++;
      opsInBatch++;

      // Firestore batches cap at 500 writes.
      if (opsInBatch == 450) {
        await batch.commit();
        batch = firestore.batch();
        opsInBatch = 0;
      }
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    debugPrint('Migration done: cleaned $migratedCount order(s).');
    return migratedCount;
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

  // 6. Live GPS Location Tracking (works for many orders at once)
  //
  // Marks [orderId] as "On the Way" for tracking purposes. The shared GPS
  // stream is started if it isn't running yet; if it already is (another
  // order is On the Way), the latest known position is simply written to the
  // new order straight away, so its customer sees the rider immediately.
  Future<void> startLiveLocationTracking(String orderId) async {
    _trackedOrderIds.add(orderId);

    if (_positionStreamSubscription == null) {
      await _ensureLocationStream();
    } else if (_lastPosition != null) {
      _writeLocationToOrder(orderId, _lastPosition!);
    }
  }

  // Stops tracking ONE order (e.g. after it is delivered). The GPS stream
  // itself only stops when no order is On the Way any more.
  void stopTrackingOrder(String orderId) {
    _trackedOrderIds.remove(orderId);
    if (_trackedOrderIds.isEmpty) {
      stopLiveLocationTracking();
    }
  }

  // Makes the set of tracked orders exactly match the orders that are
  // currently "On the Way" in Firestore. The rider home screen calls this on
  // every change, which also RESUMES tracking after the app was closed and
  // reopened (the in-memory set is lost when the app restarts).
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

  // Starts the single shared GPS stream (if it isn't already running).
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

      // Start the live stream FIRST, so a slow/failed first GPS fix can never
      // stop tracking from starting.
      _positionStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: _backgroundLocationSettings(),
          ).listen((Position position) {
            if (!isReliableRiderFix(position)) return; // skip weak GPS
            _onNewPosition(position);
          }, onError: (e) => debugPrint('Location stream error: $e'));

      // The stream has a 3 m distanceFilter, so it stays silent until the
      // rider moves. Take one reading right now (with a time limit and a
      // fresh-only last-known fallback) so customers see the rider at once.
      try {
        Position? firstPosition;
        try {
          firstPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
        } catch (_) {
          // Only trust a cached position if it is recent (an old one can be
          // kilometers away from where the rider really is).
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

  // One new reading -> remember it, publish it to listening screens, and
  // write it to EVERY order that is currently On the Way.
  void _onNewPosition(Position position) {
    _lastPosition = position;
    riderPosition.value = position;
    for (final orderId in _trackedOrderIds.toList()) {
      _writeLocationToOrder(orderId, position);
    }
  }

  // Location settings that keep the updates coming even when the rider's
  // app is in the background - e.g. while the rider is driving with Google
  // Maps open (launchCustomerNavigation opens Google Maps as a separate app,
  // which puts this app in the background). Without a foreground service,
  // Android pauses the app's location updates as soon as that happens, which
  // is why the customer saw the rider "stuck" after the rider started moving.
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

  // 7. Stop ALL live location tracking (no order is On the Way any more, or
  // the rider logged out).
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
