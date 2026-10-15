
// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


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

            
            final String status = (data['order_status'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final bool isFeedbackSubmitted =
                data['isFeedbackSubmitted'] ?? false;

            final String? currentUserId =
                FirebaseAuth.instance.currentUser?.uid;

         
            final String orderCustomerId =
                (data['customerId'] ?? data['userId'] ?? data['user_id'] ?? '')
                    .toString();

            
            final bool isMyOrder =
                currentUserId != null && currentUserId == orderCustomerId;

            
          
          }
        });
  }

  void _showOrderFeedbackDialog(BuildContext context, String orderId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return OrderFeedbackDialog(orderId: orderId);
      },
    );
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
            const Text(
              'Your order is being processed...\nFeedback popup will appear automatically once delivered.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}


// Order Feedback Popup

class OrderFeedbackDialog extends StatefulWidget {
  final String orderId;

  const OrderFeedbackDialog({super.key, required this.orderId});

  @override
  State<OrderFeedbackDialog> createState() => _OrderFeedbackDialogState();
}

class _OrderFeedbackDialogState extends State<OrderFeedbackDialog> {
  int _selectedRating = 1; 
  final TextEditingController _feedbackController = TextEditingController();
  bool _isLoading = false;

  static const  dialogBgColor = Colors.white;
  static const Color fieldBgColor = Color(0xFFFFFDFA);
  static const Color maroonColor = Color(0xFF800000);
  static const Color orangeColor = Colors.orange;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

 
  Future<void> _dismissWithoutRating() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({'isFeedbackSubmitted': true});
    } catch (e) {
      debugPrint('Failed to dismiss feedback prompt: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _submitFeedback() async {
    setState(() => _isLoading = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;

      // Update  order document
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
            'rating': _selectedRating,
            'feedback': _feedbackController.text.trim(),
            'isFeedbackSubmitted': true,
            'feedbackSubmittedAt': FieldValue.serverTimestamp(),
          });

      // Insert record into reviews collection
      await FirebaseFirestore.instance.collection('reviews').add({
        'orderId': widget.orderId,
        'userId': currentUserId,
        'rating': _selectedRating,
        'comment': _feedbackController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false, 
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

    
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final double maxDialogHeight =
        MediaQuery.of(context).size.height - keyboardHeight - 48;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: dialogBgColor,
      elevation: 8,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight > 200 ? maxDialogHeight : 200,
        ),
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _isLoading ? null : _dismissWithoutRating,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: Colors.black45,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Dismiss',
                ),
              ),
              const Text(
                'Order Delivered!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'How was your food?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 14),

             
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: fieldBgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade100, width: 1),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedRating = starIndex;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Icon(
                              starIndex <= _selectedRating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: Colors.amber,
                              size: 22,
                            ),
                          ),
                        );
                      }),
                    ),
                    Text(
                      ratingLabels[_selectedRating] ?? '',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: maroonColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _feedbackController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Comments (optional)...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
                  filled: true,
                  fillColor: fieldBgColor,
                  contentPadding: const EdgeInsets.all(10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.amber.shade100,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: maroonColor,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color>((
                      Set<WidgetState> states,
                    ) {
                      if (states.contains(WidgetState.pressed)) {
                        return orangeColor;
                      }
                      return maroonColor;
                    }),
                    foregroundColor: WidgetStateProperty.all<Color>(
                      Colors.white,
                    ),
                    shape: WidgetStateProperty.all<RoundedRectangleBorder>(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    elevation: WidgetStateProperty.all(0),
                  ),
                  onPressed: _isLoading ? null : _submitFeedback,
                  icon: _isLoading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.send_rounded, size: 16),
                  label: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Text(
                          'Submit Feedback',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}