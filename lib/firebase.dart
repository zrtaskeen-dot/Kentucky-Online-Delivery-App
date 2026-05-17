import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final CollectionReference orders = FirebaseFirestore.instance.collection('orders');

  Future<void> saveOrder({
    required String name,
    required String phone,
    required String address,
    required double totalAmount,
    required String deliveryTime,
    required String paymentMethod,
    required List<dynamic> cartItems,
  }) async {
    try {
      // Cart items ko map mein convert karna
      List<Map<String, dynamic>> itemsList = cartItems.map((item) => {
        'name': item.name,
        'quantity': item.quantity,
        'price': item.price,
      }).toList();

      await orders.add({
        'customer_name': name,
        'phone_number': phone,
        'delivery_address': address,
        'total_bill': totalAmount,
        'delivery_time': deliveryTime,
        'payment_method': paymentMethod,
        'items': itemsList,
        'order_status': 'Pending',
        'order_date': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception("Firestore Error: $e");
    }
  }
}