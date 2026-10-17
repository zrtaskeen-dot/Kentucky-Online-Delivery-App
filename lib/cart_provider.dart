// ignore_for_file: avoid_types_as_parameter_names

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CartItem {
  final String name;
  final String imageUrl;
  final double price;
  final String category;
  final List<String> toppings;
  int quantity;

  CartItem({
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.category,
    this.toppings = const <String>[],
    this.quantity = 1,
  });
}

List<String> toppingsFromData(dynamic raw) {
  if (raw is String) {
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  if (raw is! List) return <String>[];
  return raw
      .map((e) => e is Map ? (e['name'] ?? '').toString() : e.toString())
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class CartProvider with ChangeNotifier {
  final Map<String, List<CartItem>> _branchItems = {};
  String _selectedBranchId = '';
  double _deliveryCharge = 50;
  List<CartItem> get items =>
      _branchItems.putIfAbsent(_selectedBranchId, () => <CartItem>[]);

  String get selectedBranchId => _selectedBranchId;

  void setBranchId(String branchId) {
    if (_selectedBranchId.isEmpty && branchId.isNotEmpty) {
      final orphans = _branchItems.remove('');
      if (orphans != null && orphans.isNotEmpty) {
        final target = _branchItems.putIfAbsent(branchId, () => <CartItem>[]);
        for (final item in orphans) {
          final i = target.indexWhere((e) => e.name == item.name);
          if (i >= 0) {
            target[i].quantity += item.quantity;
          } else {
            target.add(item);
          }
        }
      }
    }
    _selectedBranchId = branchId;
    notifyListeners();
  }

  double get deliveryCharge => _deliveryCharge;

  void setDeliveryCharge(double charge) {
    _deliveryCharge = charge;
    notifyListeners();
  }

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice {
    return items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  void addItem(CartItem item) {
    final list = items;
    final index = list.indexWhere((element) => element.name == item.name);
    if (index >= 0) {
      list[index].quantity += item.quantity;
    } else {
      list.add(item);
    }
    notifyListeners();
  }

  void removeItem(String name) {
    items.removeWhere((item) => item.name == name);
    notifyListeners();
  }

  void clearCart() {
    items.clear();
    notifyListeners();
  }

  Future<void> clearCartInFirestore(String userId) async {
    try {
      await CartService.clearBranch(userId, _selectedBranchId);
    } catch (e) {
      debugPrint('Could not clear cart in Firestore: $e');
    }
    clearCart();
  }
}

class CartLine {
  final String docId;
  final String? lineId;
  final Map<String, dynamic> data;

  const CartLine({
    required this.docId,
    required this.lineId,
    required this.data,
  });
}

class CartService {
  CartService._();

  static CollectionReference<Map<String, dynamic>> get _carts =>
      FirebaseFirestore.instance.collection('carts');

  static Future<void> addItem(String userId, Map<String, dynamic> item) async {
    final branchId = (item['branchId'] ?? '').toString();

    final line = <String, dynamic>{
      ...item,
      'lineId': DateTime.now().microsecondsSinceEpoch.toString(),
      'addedAt': Timestamp.now(),
    }..remove('branchId');

    final mine = await _carts.where('userId', isEqualTo: userId).get();
    DocumentReference<Map<String, dynamic>>? existing;
    for (final doc in mine.docs) {
      final d = doc.data();
      if (d['items'] is List && (d['branchId'] ?? '').toString() == branchId) {
        existing = doc.reference;
        break;
      }
    }

    if (existing != null) {
      await existing.update({
        'items': FieldValue.arrayUnion([line]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _carts.add({
        'userId': userId,
        if (branchId.isNotEmpty) 'branchId': branchId,
        'items': [line],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static List<CartLine> linesFromDocs(Iterable<QueryDocumentSnapshot> docs) {
    final lines = <CartLine>[];
    for (final doc in docs) {
      final data = (doc.data() as Map<String, dynamic>?) ?? {};
      final items = data['items'];
      if (items is List) {
        final docBranch = (data['branchId'] ?? '').toString();
        for (final e in items) {
          if (e is Map) {
            final m = Map<String, dynamic>.from(e);
            if (docBranch.isNotEmpty) m['branchId'] = docBranch;
            lines.add(
              CartLine(docId: doc.id, lineId: m['lineId']?.toString(), data: m),
            );
          }
        }
      } else {
        lines.add(CartLine(docId: doc.id, lineId: null, data: data));
      }
    }
    int stamp(CartLine l) {
      final t = l.data['addedAt'];
      return t is Timestamp ? t.millisecondsSinceEpoch : 0;
    }

    lines.sort((a, b) => stamp(a).compareTo(stamp(b)));
    return lines;
  }

  //  QUANTITY / REMOVE

  static Future<void> setQuantity(CartLine line, int newQty) async {
    final ref = _carts.doc(line.docId);

    if (line.lineId == null) {
      if (newQty <= 0) {
        await ref.delete();
      } else {
        await ref.update({'quantity': newQty});
      }
      return;
    }

    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      snap = await ref.get();
    }
    if (!snap.exists) return;

    final items = _itemsOf(snap.data());
    final i = items.indexWhere((e) => e['lineId']?.toString() == line.lineId);
    if (i < 0) return;

    if (newQty <= 0) {
      items.removeAt(i);
    } else {
      items[i]['quantity'] = newQty;
    }

    if (items.isEmpty) {
      await ref.delete();
    } else {
      await ref.update({
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<void> removeLine(CartLine line) => setQuantity(line, 0);

  static Future<void> recordSales(String userId, String activeBranchId) async {
    try {
      final snap = await _carts.where('userId', isEqualTo: userId).get();
      final perItem = <String, int>{};
      for (final line in linesFromDocs(snap.docs)) {
        final b = (line.data['branchId'] ?? '').toString();
        if (b.isNotEmpty && b != activeBranchId) continue;
        final menuItemId = (line.data['menuItemId'] ?? '').toString();
        if (menuItemId.isEmpty) continue;
        final qty = int.tryParse('${line.data['quantity']}') ?? 1;
        perItem[menuItemId] = (perItem[menuItemId] ?? 0) + qty;
      }
      for (final e in perItem.entries) {
        try {
          await FirebaseFirestore.instance.collection('menu').doc(e.key).update(
            {'soldCount': FieldValue.increment(e.value)},
          );
        } catch (err) {
          debugPrint('Could not update soldCount for ${e.key}: $err');
        }
      }
    } catch (err) {
      debugPrint('recordSales failed: $err');
    }
  }

  static Future<void> clearBranch(String userId, String activeBranchId) async {
    final snap = await _carts.where('userId', isEqualTo: userId).get();
    if (snap.docs.isEmpty) return;

    bool belongs(Map<String, dynamic> m) {
      final b = (m['branchId'] ?? '').toString();
      return b.isEmpty || b == activeBranchId;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final data = doc.data();
      final items = data['items'];
      if (items is List) {
        final docBranch = (data['branchId'] ?? '').toString();
        if (docBranch.isNotEmpty) {
          if (docBranch == activeBranchId) batch.delete(doc.reference);
          continue;
        }
        final keep = _itemsOf(data).where((m) => !belongs(m)).toList();
        if (keep.isEmpty) {
          batch.delete(doc.reference);
        } else {
          batch.update(doc.reference, {
            'items': keep,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else if (belongs(data)) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }

  static List<Map<String, dynamic>> _itemsOf(Map<String, dynamic>? data) {
    final raw = data?['items'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}