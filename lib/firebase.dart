import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'cart_provider.dart';

class FirestoreService {
  Future<String> saveOrder({
    required String name,
    required String phone,
    required String address,
    required double latitude,
    required double longitude,
    required double totalAmount,
    required String deliveryTime,
    required String paymentMethod,
    required List<CartItem> cartItems,
    required String transactionId,
    required String branchId,
    String?
    receiptImageUrl, // 👈 ADDED: Cloudinary URL of the payment receipt (Online payments only; null for COD)
  }) async {
    try {
      List<Map<String, dynamic>> itemsList = cartItems.map((item) {
        return {
          'name': item.name,
          'imageUrl': item.imageUrl,
          'price': item.price,
          'category': item.category,
          'quantity': item.quantity,
        };
      }).toList();

      final String currentUserId =
          FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

      final CollectionReference orders = FirebaseFirestore.instance.collection(
        'orders',
      );

      // 👈 CHANGED: ab har field camelCase (no underscores) hai, taake
      // branchId/customerId/createdAt/isFeedbackSubmitted jaisi existing
      // fields ke naming style ke saath consistent rahe.
      // ⚠️ IMPORTANT: agar koi doosri screen (OrderHistoryScreen, admin
      // panel, Cloud Functions, etc.) purane snake_case field names
      // (customer_name / phone_number / delivery_address / delivery_time /
      // payment_method / transaction_id / order_status) se query ya read
      // kar rahi hai, wahan bhi naam update karne honge — warna woh
      // screens data read/query nahi kar paayengi. Yeh sirf saveOrder ka
      // write side hai.
      final docRef = await orders.add({
        'customerName': name,
        'phoneNumber': phone,
        'deliveryAddress': address,
        'totalAmount': totalAmount,
        'deliveryTime': deliveryTime,
        'paymentMethod': paymentMethod,
        'transactionId': transactionId,
        'latitude': latitude,
        'longitude': longitude,
        'items': itemsList,
        'orderStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'branchId': branchId,
        'customerId': currentUserId,
        'isFeedbackSubmitted': false,
        // 👈 ADDED: only written when a receipt was actually uploaded
        // (Online payment) — COD orders simply won't have this field.
        if (receiptImageUrl != null) 'receiptImageUrl': receiptImageUrl,
      });

      print("Order successfully dispatched to Firestore! 🎉");
      return docRef.id;
    } catch (e) {
      print("Firestore Save Error: $e");
      rethrow;
    }
  }
}