import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ==========================================
// 1. SINGLE-ORDER TRACKING SCREEN
// Shows live status for one order. It no longer decides when to
// show the feedback popup — that is now owned by
// GlobalFeedbackListener, so every delivered order gets a popup,
// not just the one currently on screen.
// ==========================================
class CustomerOrderTrackerScreen extends StatefulWidget {
  final String orderId;

  const CustomerOrderTrackerScreen({super.key, required this.orderId});

  @override
  State<CustomerOrderTrackerScreen> createState() =>
      _CustomerOrderTrackerScreenState();
}

class _CustomerOrderTrackerScreenState
    extends State<CustomerOrderTrackerScreen> {
  StreamSubscription<DocumentSnapshot>? _orderSubscription;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _listenToOrderStatus();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  void _listenToOrderStatus() {
    _orderSubscription = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((documentSnapshot) {
      if (documentSnapshot.exists && mounted) {
        final data = documentSnapshot.data();
        if (data == null) return;

        final String status =
            (data['order_status'] ?? '').toString().trim().toLowerCase();

        setState(() => _status = status);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.directions_bike,
              size: 80,
              color: Color(0xFF800000),
            ),
            const SizedBox(height: 16),
            Text(
              'Order ID: ${widget.orderId}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _status.isEmpty ? 'Loading status...' : 'Status: $_status',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. ORDER FEEDBACK POPUP DIALOG
// Unchanged behavior — still shown by whoever calls it
// (now GlobalFeedbackListener instead of this screen).
// ==========================================
class OrderFeedbackDialog extends StatefulWidget {
  final String orderId;

  const OrderFeedbackDialog({super.key, required this.orderId});

  @override
  State<OrderFeedbackDialog> createState() => _OrderFeedbackDialogState();
}

class _OrderFeedbackDialogState extends State<OrderFeedbackDialog> {
  int _selectedRating = 5;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isLoading = false;

  static const Color dialogBgColor = Color(0xFFFCF8DD);
  static const Color fieldBgColor = Color(0xFFFFFFF0);
  static const Color maroonColor = Color(0xFF800000);
  static const Color orangeColor = Colors.orange;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    setState(() => _isLoading = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'rating': _selectedRating,
        'feedback': _feedbackController.text.trim(),
        'isFeedbackSubmitted': true,
        'feedbackSubmittedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('reviews').add({
        'orderId': widget.orderId,
        'userId': currentUserId,
        'rating': _selectedRating,
        'comment': _feedbackController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! Your feedback has been submitted.'),
            backgroundColor: maroonColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit feedback: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const ratingLabels = {
      1: 'Poor',
      2: 'Fair',
      3: 'Good',
      4: 'Very Good',
      5: 'Excellent',
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: dialogBgColor,
      elevation: 12,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [maroonColor, Color(0xFFB33A1A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: maroonColor.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delivery_dining_rounded,
                  size: 46,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Order Delivered!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your order has arrived! How was your food?\nYour feedback helps us serve you better.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: fieldBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade100, width: 1.2),
                ),
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        return IconButton(
                          onPressed: () {
                            setState(() {
                              _selectedRating = starIndex;
                            });
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: 20,
                          icon: AnimatedScale(
                            scale: starIndex <= _selectedRating ? 1.0 : 0.88,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              starIndex <= _selectedRating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: Colors.amber,
                              size: 32,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Text(
                        ratingLabels[_selectedRating] ?? '',
                        key: ValueKey(_selectedRating),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: maroonColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Additional comments (optional)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _feedbackController,
                maxLines: 3,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Tell us what you liked or what we can improve...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: fieldBgColor,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.amber.shade100,
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: maroonColor,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: maroonColor.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith<Color>(
                          (Set<WidgetState> states) {
                        if (states.contains(WidgetState.pressed)) {
                          return orangeColor;
                        }
                        return maroonColor;
                      }),
                      foregroundColor:
                          WidgetStateProperty.all<Color>(Colors.white),
                      shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      elevation: WidgetStateProperty.all(0),
                    ),
                    onPressed: _isLoading ? null : _submitFeedback,
                    icon: _isLoading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.send_rounded, size: 18),
                    label: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Submit Feedback',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}