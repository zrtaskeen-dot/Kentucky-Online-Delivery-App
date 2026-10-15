import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'order_tracker.dart' show OrderFeedbackDialog;
import 'notification_service.dart';
import 'main.dart'show navigatorKey;


final ValueNotifier<bool> customerHomeReady = ValueNotifier<bool>(false);


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


String _resolveStatus(Map<String, dynamic> data) {
  final camel = (data['orderStatus'] ?? '').toString().toLowerCase();
  final snake = (data['order_status'] ?? '').toString().toLowerCase();
  if (snake.isNotEmpty && snake != 'pending') return snake;
  if (camel.isNotEmpty && camel != 'pending') return camel;
  return camel.isNotEmpty ? camel : snake;
}






class GlobalFeedbackListener extends StatefulWidget {
  final Widget child;

  const GlobalFeedbackListener({super.key, required this.child});

  @override
  State<GlobalFeedbackListener> createState() => _GlobalFeedbackListenerState();
}

class _GlobalFeedbackListenerState extends State<GlobalFeedbackListener> {
  StreamSubscription<User?>? _authSubscription;
  String? _activeUserId;

 
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  final List<String> _pendingOrderIds = [];
  bool _isDialogShowing = false;

  
  bool _homeReady = false;

  
  bool _fallbackElapsed = false;

  bool get _readyToShowDialogs => _homeReady || _fallbackElapsed;

  // Payment reminders 
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

    customerHomeReady.addListener(_onHomeReadyChanged);
    if (customerHomeReady.value) _onHomeReadyChanged();

    Future.delayed(const Duration(seconds: 12), () {
      if (!mounted) return;
      _fallbackElapsed = true;
      _tryShowNextDialog();
    });
  }

  void _onHomeReadyChanged() {
    if (!customerHomeReady.value) {
      _homeReady = false;
      return;
    }
   
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || !customerHomeReady.value) return;
      _homeReady = true;
      _tryShowNextDialog();
    });
  }

  @override
  void dispose() {
    customerHomeReady.removeListener(_onHomeReadyChanged);
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
   
    _stopListening();
    _activeUserId = user?.uid;
    if (user == null) return;

    if (await _isRider(user.uid)) return;
   
    if (!mounted || _activeUserId != user.uid) return;

    _listenForDeliveredOrders(user.uid);
    _listenForPaymentReminders(user.uid);
  }

  
  Future<bool> _isRider(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return false; 
      final roleId = (data['roleId'] ?? '').toString();
      final legacyRole = (data['role'] ?? '').toString().toLowerCase();
      return roleId == 'R002' || legacyRole == 'rider';
    } catch (e) {
      debugPrint('GlobalFeedbackListener: role check failed: $e');
      return false;
    }
  }

  //  Feedback for delivered orders

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
    if (!_readyToShowDialogs || _isDialogShowing || _pendingOrderIds.isEmpty) {
      return;
    }

    
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

    
    _tryShowNextDialog();
  }

  // Payment Reminder

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

    
    _paymentReminderTicker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkPaymentReminders(userId),
    );
  }

  bool _isPaymentReminderCandidate(Map<String, dynamic> data) {
    
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

      
      if (now.isBefore(scheduledAt.subtract(_receiptWindow))) continue;
      if (!now.isBefore(scheduledAt)) {
        _paymentReminderCandidates.remove(orderId);
        continue;
      }

      
      _paymentReminderCandidates.remove(orderId);

      final String shortId = orderId
          .substring(0, orderId.length > 6 ? 6 : orderId.length)
          .toUpperCase();

      try {
       
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .update({'paymentReminderSent': true});

        await NotificationService.notifyCustomer(
          customerId: userId,
          title: "Payment Now Available",
          body:
              "You can now upload your payment receipt for order #$shortId. "
              "Please complete the payment-your order will only be "
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