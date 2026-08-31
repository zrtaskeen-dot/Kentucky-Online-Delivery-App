import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// Update this import path to match where you keep the tracker file.
import 'ordertracker.dart' show OrderFeedbackDialog;

// ==========================================
// GLOBAL FEEDBACK LISTENER
//
// Mount this ONCE, wrapping the customer app's shell (e.g. around
// the home screen / bottom-nav scaffold in main.dart) so it stays
// active no matter which screen the customer is on.
//
// It watches every order belonging to the current customer where
// order_status == 'delivered' and isFeedbackSubmitted == false,
// and shows one feedback popup at a time — queuing the rest so a
// customer with several orders delivered the same day gets a
// popup for each order, not just the last one they happened to
// be viewing.
//
// Requires a Firestore composite index on:
//   orders: customerId (asc), order_status (asc), isFeedbackSubmitted (asc)
// Firestore will show a direct "create index" link in the console
// or debug log the first time this query runs if it's missing.
// ==========================================
class GlobalFeedbackListener extends StatefulWidget {
  final Widget child;

  const GlobalFeedbackListener({super.key, required this.child});

  @override
  State<GlobalFeedbackListener> createState() => _GlobalFeedbackListenerState();
}

class _GlobalFeedbackListenerState extends State<GlobalFeedbackListener> {
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  final List<String> _pendingOrderIds = [];
  bool _isDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _listenForDeliveredOrders();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  void _listenForDeliveredOrders() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    _ordersSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: currentUserId)
        .where('order_status', isEqualTo: 'Delivered')
        .where('isFeedbackSubmitted', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
          for (final doc in snapshot.docs) {
            if (!_pendingOrderIds.contains(doc.id)) {
              _pendingOrderIds.add(doc.id);
            }
          }
          _tryShowNextDialog();
        });
  }

  Future<void> _tryShowNextDialog() async {
    if (_isDialogShowing || _pendingOrderIds.isEmpty || !mounted) return;

    _isDialogShowing = true;
    final orderId = _pendingOrderIds.removeAt(0);
    debugPrint(
      'GlobalFeedbackListener: showing popup for order $orderId '
      '(${_pendingOrderIds.length} still queued)',
    );

    if (!mounted) {
      _isDialogShowing = false;
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrderFeedbackDialog(orderId: orderId),
    );

    debugPrint('GlobalFeedbackListener: closed popup for order $orderId');
    _isDialogShowing = false;

    // Show the next queued popup, if the customer had more than
    // one order delivered without feedback.
    _tryShowNextDialog();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
