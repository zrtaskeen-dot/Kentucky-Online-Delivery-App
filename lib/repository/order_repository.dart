// ── DATA LAYER (Repository) ──────────────────────────────────
// All direct Firestore access lives here. The presentation layer
// (screens) never touches FirebaseFirestore/FirebaseAuth directly —
// it calls methods on OrderRepository instead. This is what makes it
// possible to later swap Firestore for another backend, or mock this
// repository in tests, without touching any UI code.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../logic/price_u.dart';

class OrderRepository {
  OrderRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      _firestore.collection('orders').withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => snap.data() ?? {},
            toFirestore: (data, _) => data,
          );

  CollectionReference<Map<String, dynamic>> get _cartsRef =>
      _firestore.collection('carts').withConverter<Map<String, dynamic>>(
            fromFirestore: (snap, _) => snap.data() ?? {},
            toFirestore: (data, _) => data,
          );

  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Live stream of the current user's orders (all statuses).
  /// Sorting into active/past and by recency is a presentation concern
  /// and stays in the screen — this just returns the raw stream.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamMyOrders() {
    return _ordersRef.where('customerId', isEqualTo: _currentUserId).snapshots();
  }

  /// Re-adds a past order's items to the user's cart, merging
  /// quantities with any existing cart line for the same item name.
  /// Price always comes from [readItemPrice] (domain layer) so a
  /// differently-named or nested price field never silently becomes 0.
  Future<void> reorderItems(List<Map<String, dynamic>> items) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

    for (final item in items) {
      final name = (item['name'] ?? '').toString();
      if (name.isEmpty) continue;

      final imageUrl = (item['imageUrl'] ?? '').toString();
      final category = (item['category'] ?? '').toString();
      final price = readItemPrice(item);
      final quantity = readItemQuantity(item).round();

      final existing = await _cartsRef
          .where('userId', isEqualTo: userId)
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final doc = existing.docs.first;
        final existingData = doc.data();
        final currentQty = int.tryParse(existingData['quantity'].toString()) ?? 1;
        final currentPrice = readPriceValue(existingData['price']);

        await doc.reference.update({
          'quantity': currentQty + quantity,
          if (currentPrice <= 0) 'price': price,
        });
      } else {
        await _cartsRef.add({
          'userId': userId,
          'name': name,
          'imageUrl': imageUrl,
          'price': price,
          'category': category,
          'quantity': quantity,
        });
      }
    }
  }
}