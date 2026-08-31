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

      // 👈 CHANGED: field names ab OrderHistoryScreen ke saath match karte hain
      // (customerId / status / totalAmount / createdAt), taake "My Orders"
      // query aur data reads sahi se kaam karein.
      final docRef = await orders.add({
        'customer_name': name,
        'phone_number': phone,
        'delivery_address': address,
        'totalAmount': totalAmount, // 👈 was 'total_bill'
        'delivery_time': deliveryTime,
        'payment_method': paymentMethod,
        'transaction_id': transactionId,
        'latitude': latitude,
        'longitude': longitude,
        'items': itemsList,
        'order_status':
            'pending', // 👈 CHANGED: ab sirf 'order_status' likha jata hai, 'status' nahi
        'createdAt': FieldValue.serverTimestamp(), // 👈 was 'order_date'
        'branchId': branchId,
        'customerId': currentUserId, // 👈 was 'userId'
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
