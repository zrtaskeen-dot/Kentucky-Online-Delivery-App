import 'package:cloud_firestore/cloud_firestore.dart';

class OrderModel {
  final String orderId;
  final String branchId;
  final List<dynamic> items; // Har item ka name, qty, price, image isme hogi
  final double totalPrice;
  final String status; // pending, preparing, out_for_delivery, delivered
  final DateTime timestamp;

  OrderModel({
    required this.orderId,
    required this.branchId,
    required this.items,
    required this.totalPrice,
    required this.status,
    required this.timestamp,
  });

  // Firestore Map data ko OrderModel object mein convert karne ke liye
  factory OrderModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return OrderModel(
      orderId: doc.id,
      branchId: data['branchId'] ?? '',
      items: data['items'] ?? [],
      totalPrice: (data['totalPrice'] ?? 0).toDouble(),
      status: data['status'] ?? 'pending',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}