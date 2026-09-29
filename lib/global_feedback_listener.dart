import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// Update this import path to match where you keep the tracker file.
import 'order_tracker.dart' show OrderFeedbackDialog;
import 'notification_service.dart';
import 'main.dart' show navigatorKey;

// Parses delivery_type.dart's "6 Sep 2026 at 05:30 PM" schedule label
// back into a DateTime — same format/parsing rules as
// order_history_detail.dart's `_scheduledDateTime` getter. Returns null
// if it can't be parsed (or isn't actually a scheduled label at all).
DateTime? _parseScheduledDateTime(String deliveryTime) {
  if (deliveryTime == "Standard Delivery") return null;
  try {
    final parts = deliveryTime.split(' at ');
    if (parts.length != 2) return null;

    final dateSegs = parts[0].trim().split(' ');
    if (dateSegs.length != 3) return null;
    final day = int.tryParse(dateSegs[0]);
    final year = int.tryParse(dateSegs[2]);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months.indexOf(dateSegs[1]) + 1;
    if (day == null || year == null || month == 0) return null;

    final timeMatch = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(parts[1].trim());
    if (timeMatch == null) return null;

    int hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final period = timeMatch.group(3)!.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return DateTime(year, month, day, hour, minute);
  } catch (e) {
    return null;
  }
}

// An order document can carry both 'orderStatus' (camelCase) and the
// legacy 'order_status' (snake_case) with different values, e.g.
// orderStatus: 'pending' / order_status: 'Assigned'. Trust whichever one
// isn't still sitting at the just-created 'pending' default.
String _resolveStatus(Map<String, dynamic> data) {
  final camel = (data['orderStatus'] ?? '').toString().toLowerCase();
  final snake = (data['order_status'] ?? '').toString().toLowerCase();
  if (snake.isNotEmpty && snake != 'pending') return snake;
  if (camel.isNotEmpty && camel != 'pending') return camel;
  return camel.isNotEmpty ? camel : snake;
}

// ==========================================
// GLOBAL FEEDBACK + PAYMENT-REMINDER LISTENER
//
// Mount this ONCE, wrapping the customer app's shell (main.dart) so it
// stays active no matter which screen the customer is on.
//
// 1. FEEDBACK: watches the signed-in customer's orders that are
//    delivered and have isFeedbackSubmitted == false, and shows one
//    feedback popup at a time — queuing the rest so a customer with
//    several orders delivered the same day gets a popup for each.
//
// 2. PAYMENT REMINDER: for each scheduled ('Deliver Later'), online-
//    payment order that has no receipt yet, the moment it enters its
//    1h30m-before-delivery upload window, sends a one-time in-app
//    notification. Only orders that checkout flagged with
//    paymentReminderSent == false are considered (older orders without
//    the field are left alone), and nothing is sent once the scheduled
//    time has passed, since the window is closed by then.
//
// AUTH-AWARE: everything is tied to whoever is signed in RIGHT NOW. When
// the user logs out / switches account (e.g. customer -> rider), the
// old subscriptions are cancelled and the queue is cleared, so a rider
// can never be shown a customer's feedback popup. Rider accounts get no
// subscriptions at all.
//
// The status is matched client-side (both status fields, case-
// insensitive), so this query needs no composite index: it filters only
// on customerId + isFeedbackSubmitted equality.
// ==========================================
class GlobalFeedbackListener extends StatefulWidget {
  final Widget child;

  const GlobalFeedbackListener({super.key, required this.child});

  @override
  State<GlobalFeedbackListener> createState() => _GlobalFeedbackListenerState();
}

class _GlobalFeedbackListenerState extends State<GlobalFeedbackListener> {
  StreamSubscription<User?>? _authSubscription;
  String? _activeUserId;

  // ── Feedback ──
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  final List<String> _pendingOrderIds = [];
  bool _isDialogShowing = false;

  // ── Payment reminders ──
  StreamSubscription<QuerySnapshot>? _paymentReminderSubscription;
  Timer? _paymentReminderTicker;
  Map<String, Map<String, dynamic>> _paymentReminderCandidates = {};
  static const List<String> _pastStatuses = ['delivered', 'cancelled'];
  static const Duration _receiptWindow = Duration(hours: 1, minutes: 30);

  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthChanged,
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    _ordersSubscription?.cancel();
    _ordersSubscription = null;
    _paymentReminderSubscription?.cancel();
    _paymentReminderSubscription = null;
    _paymentReminderTicker?.cancel();
    _paymentReminderTicker = null;
    _pendingOrderIds.clear();
    _paymentReminderCandidates = {};
  }

  Future<void> _onAuthChanged(User? user) async {
    // Whoever was signed in before is gone — drop their subscriptions and
    // any queued popups before anything else.
    _stopListening();
    _activeUserId = user?.uid;
    if (user == null) return;

    if (await _isRider(user.uid)) return;
    // The account may have changed again while we were checking the role.
    if (!mounted || _activeUserId != user.uid) return;

    _listenForDeliveredOrders(user.uid);
    _listenForPaymentReminders(user.uid);
  }

  // Riders share the 'users' collection with customers. They have no
  // customer orders, and must never get customer popups/reminders.
  Future<bool> _isRider(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return false; // e.g. guest — treat as customer
      final roleID = (data['roleID'] ?? '').toString();
      final legacyRole = (data['role'] ?? '').toString().toLowerCase();
      return roleID == 'R002' || legacyRole == 'rider';
    } catch (e) {
      debugPrint('GlobalFeedbackListener: role check failed: $e');
      return false;
    }
  }

  // ── FEEDBACK ────────────────────────────────────────────────────

  void _listenForDeliveredOrders(String userId) {
    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: userId)
        .where('isFeedbackSubmitted', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          if (_activeUserId != userId) return;
          for (final doc in snapshot.docs) {
            final status = _resolveStatus(doc.data());
            if (status == 'delivered' && !_pendingOrderIds.contains(doc.id)) {
              _pendingOrderIds.add(doc.id);
            }
          }
          _tryShowNextDialog();
        });
  }

  Future<void> _tryShowNextDialog() async {
    if (_isDialogShowing || _pendingOrderIds.isEmpty) return;

    // This widget now lives ABOVE the app's Navigator (mounted via
    // MaterialApp's `builder`, see main.dart), so its own `context`
    // doesn't have a Navigator ancestor to show a dialog on — using the
    // app-wide navigatorKey instead reaches the Navigator directly,
    // works no matter which screen is currently on top, and doesn't
    // depend on this widget's own BuildContext at all.
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) return;

    _isDialogShowing = true;
    final orderId = _pendingOrderIds.removeAt(0);
    debugPrint(
      'GlobalFeedbackListener: showing popup for order $orderId '
      '(${_pendingOrderIds.length} still queued)',
    );

    await showDialog(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => OrderFeedbackDialog(orderId: orderId),
    );

    debugPrint('GlobalFeedbackListener: closed popup for order $orderId');
    _isDialogShowing = false;

    // Show the next queued popup, if the customer had more than
    // one order delivered without feedback.
    _tryShowNextDialog();
  }

  // ── PAYMENT REMINDERS ───────────────────────────────────────────

  void _listenForPaymentReminders(String userId) {
    _paymentReminderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
          if (_activeUserId != userId) return;
          final Map<String, Map<String, dynamic>> candidates = {};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (_isPaymentReminderCandidate(data)) {
              candidates[doc.id] = data;
            }
          }
          _paymentReminderCandidates = candidates;
          _checkPaymentReminders(userId);
        });

    // Crossing a time threshold isn't a Firestore change, so re-check on
    // a timer (runs while the app process is alive).
    _paymentReminderTicker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkPaymentReminders(userId),
    );
  }

  bool _isPaymentReminderCandidate(Map<String, dynamic> data) {
    // Only orders checkout explicitly flagged as "reminder not sent yet".
    // Older orders without the field are skipped instead of suddenly
    // notifying about them.
    if (data['paymentReminderSent'] != false) return false;

    if (_pastStatuses.contains(_resolveStatus(data))) return false;

    final String deliveryTime =
        (data['deliveryTime'] ?? data['delivery_time'] ?? '—').toString();
    if (deliveryTime == "Standard Delivery") return false;

    final String paymentMethod =
        (data['paymentMethod'] ?? data['payment_method'] ?? '—').toString();
    if (paymentMethod == "Cash On Delivery") return false;

    final String receiptUrl =
        (data['receiptImageUrl'] ?? data['receipt_url'] ?? '').toString();
    if (receiptUrl.isNotEmpty) return false;

    return _parseScheduledDateTime(deliveryTime) != null;
  }

  Future<void> _checkPaymentReminders(String userId) async {
    if (_activeUserId != userId || _paymentReminderCandidates.isEmpty) return;

    final DateTime now = DateTime.now();

    for (final entry in _paymentReminderCandidates.entries.toList()) {
      final String orderId = entry.key;
      final data = entry.value;
      final String deliveryTime =
          (data['deliveryTime'] ?? data['delivery_time'] ?? '—').toString();
      final DateTime? scheduledAt = _parseScheduledDateTime(deliveryTime);
      if (scheduledAt == null) continue;

      // Window = [scheduled - 1h30m, scheduled). Not open yet -> wait.
      // Already closed -> the receipt can no longer be uploaded, so a
      // "payment now available" message would be wrong; drop it.
      if (now.isBefore(scheduledAt.subtract(_receiptWindow))) continue;
      if (!now.isBefore(scheduledAt)) {
        _paymentReminderCandidates.remove(orderId);
        continue;
      }

      // Remove from the local cache first so an overlapping tick or
      // snapshot can't fire this twice while the write is in flight.
      _paymentReminderCandidates.remove(orderId);

      final String shortId = orderId
          .substring(0, orderId.length > 6 ? 6 : orderId.length)
          .toUpperCase();

      try {
        // Flip the flag first so a failure below can never cause repeat
        // notifications.
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .update({'paymentReminderSent': true});

        await NotificationService.notifyCustomer(
          customerId: userId,
          title: "Payment Now Available",
          body:
              "You can now upload your payment receipt for order #$shortId. "
              "Please complete the payment — your order will only be "
              "confirmed once payment is received.",
        );
      } catch (e) {
        debugPrint(
          'GlobalFeedbackListener: failed to send payment reminder '
          'for order $orderId: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}