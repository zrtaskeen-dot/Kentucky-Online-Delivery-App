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

    required String branchId,
    String?
    receiptImageUrl, 
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

     
      final bool isScheduledOnline =
          deliveryTime != 'Standard Delivery' &&
          paymentMethod != 'Cash On Delivery';

     
      final docRef = await orders.add({
        'customerName': name,
        'phone': phone,
        'deliveryAddress': address,
        'totalAmount': totalAmount,
        'deliveryTime': deliveryTime,
        'paymentMethod': paymentMethod,
        'latitude': latitude,
        'longitude': longitude,
        'items': itemsList,
        'orderStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'branchId': branchId,
        'customerId': currentUserId,
        'isFeedbackSubmitted': false,
       
        if (receiptImageUrl != null) 'receiptImageUrl': receiptImageUrl,
       
        if (isScheduledOnline) 'paymentReminderSent': false,
      });

      print("Order successfully dispatched to Firestore! 🎉");
      return docRef.id;
    } catch (e) {
      print("Firestore Save Error: $e");
      rethrow;
    }
  }
}