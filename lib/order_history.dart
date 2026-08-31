import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'cart_provider.dart';
import 'order_history_detail.dart';

double _readPriceValue(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  if (raw is Map && raw.isNotEmpty) {
    return _readPriceValue(raw.values.first);
  }
  return double.tryParse(raw.toString()) ?? 0;
}

double _readItemPrice(Map<String, dynamic> item) {
  final raw = item['price'] ??
      item['itemPrice'] ??
      item['unitPrice'] ??
      item['amount'] ??
      item['cost'];
  return _readPriceValue(raw);
}

double _readItemQuantity(Map<String, dynamic> item) {
  final raw = item['quantity'] ?? item['qty'] ?? 1;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 1;
}

double _computeOrderTotal(
  Map<String, dynamic> orderData,
  List<Map<String, dynamic>> items,
) {
  final raw = orderData['totalAmount'] ??
      orderData['total_bill'] ??
      orderData['totalPrice'] ??
      orderData['total'] ??
      orderData['grandTotal'] ??
      orderData['finalAmount'] ??
      orderData['orderTotal'] ??
      orderData['amount'];
  final t = _readPriceValue(raw);
  if (t > 0) return t;

  double sum = 0;
  for (final item in items) {
    sum += _readItemPrice(item) * _readItemQuantity(item);
  }
  return sum;
}

List<Map<String, dynamic>> _readOrderItems(Map<String, dynamic> orderData) {
  final raw = orderData['items'] ?? orderData['cartItems'] ?? [];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

Stream<QuerySnapshot<Map<String, dynamic>>> _streamMyOrders() {
  final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  return FirebaseFirestore.instance
      .collection('orders')
      .where('customerId', isEqualTo: userId)
      .snapshots();
}

Future<void> _reorderItems(BuildContext context, List<Map<String, dynamic>> items) async {
  final cartsRef = FirebaseFirestore.instance.collection('carts');
  final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';
  final cartProvider = Provider.of<CartProvider>(context, listen: false);

  for (final item in items) {
    final name = (item['name'] ?? '').toString();
    if (name.isEmpty) continue;

    final imageUrl = (item['imageUrl'] ?? '').toString();
    final category = (item['category'] ?? '').toString();
    final price = _readItemPrice(item);
    final quantity = _readItemQuantity(item).round();

    final existing = await cartsRef
        .where('userId', isEqualTo: userId)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      final existingData = doc.data();
      final currentQty = int.tryParse(existingData['quantity'].toString()) ?? 1;
      final currentPrice = _readPriceValue(existingData['price']);

      await doc.reference.update({
        'quantity': currentQty + quantity,
        if (currentPrice <= 0) 'price': price,
      });
    } else {
      await cartsRef.add({
        'userId': userId,
        'name': name,
        'imageUrl': imageUrl,
        'price': price,
        'category': category,
        'quantity': quantity,
      });
    }

    cartProvider.addItem(
      CartItem(
        name: name,
        imageUrl: imageUrl,
        price: price,
        category: category,
        quantity: quantity,
      ),
    );
  }
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  static const Color themeColor = Color(0xFFA62600);
  static const Color bgColor = Color(0xFFF9F0E0);
  static const Color creamColor = Color(0xFFFEF9E7);
  static const Color cardColor = Color(0xFFFFFFF0);
  static const Color outlineColor = Colors.black26;

  static const List<String> _pastStatuses = ['delivered', 'cancelled'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "My Orders",
          style: TextStyle(fontWeight: FontWeight.bold, color: creamColor),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _streamMyOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: themeColor),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final allDocs = snapshot.data!.docs;

          final activeDocs = allDocs.where((doc) {
            final status = (doc.data()['order_status'] ?? '')
                .toString()
                .toLowerCase();
            return !_pastStatuses.contains(status);
          }).toList();

          final pastDocs = allDocs.where((doc) {
            final status = (doc.data()['order_status'] ?? '')
                .toString()
                .toLowerCase();
            return _pastStatuses.contains(status);
          }).toList();

          int byRecency(
            QueryDocumentSnapshot<Map<String, dynamic>> a,
            QueryDocumentSnapshot<Map<String, dynamic>> b,
          ) {
            final ta = a.data()['createdAt'];
            final tb = b.data()['createdAt'];
            if (ta is Timestamp && tb is Timestamp) {
              return tb.compareTo(ta);
            }
            return 0;
          }

          activeDocs.sort(byRecency);
          pastDocs.sort(byRecency);

          if (activeDocs.isEmpty && pastDocs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            children: [
              if (activeDocs.isNotEmpty) ...[
                _sectionHeader("Active Orders", Icons.local_shipping_rounded),
                const SizedBox(height: 8),
                ...activeDocs.map(
                  (doc) => _OrderCard(
                    orderId: doc.id,
                    data: doc.data(),
                    isPast: false,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (pastDocs.isNotEmpty) ...[
                _sectionHeader("Order History", Icons.history_rounded),
                const SizedBox(height: 8),
                ...pastDocs.map(
                  (doc) => _OrderCard(
                    orderId: doc.id,
                    data: doc.data(),
                    isPast: true,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: themeColor, size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 50,
            color: themeColor.withOpacity(0.4),
          ),
          const SizedBox(height: 10),
          const Text(
            "No orders found.",
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.orderId,
    required this.data,
    required this.isPast,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final bool isPast;

  static const Color themeColor = OrderHistoryScreen.themeColor;
  static const Color cardColor = OrderHistoryScreen.cardColor;
  static const Color outlineColor = OrderHistoryScreen.outlineColor;

  List<Map<String, dynamic>> get _items => _readOrderItems(data);

  double get _total => _computeOrderTotal(data, _items);

  String get _status =>
      (data['order_status'] ?? 'pending').toString().toLowerCase();

  String get _dateLabel {
    final ts = data['createdAt'] ?? data['order_date'];
    if (ts is Timestamp) {
      final d = ts.toDate();
      return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    }
    return "";
  }

  Color get _statusColor {
    switch (_status) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'on the way':
      case 'out for delivery':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  void _showCancellationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text(
              "Order Cancelled",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          "Your order has been cancelled by the restaurant manager due to an invalid payment receipt.",
          style: TextStyle(fontSize: 14, color: Colors.black87),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final displayThumbs = items.take(4).toList();
    final extraCount = items.length - displayThumbs.length;

    return InkWell(
      onTap: () {
        OrderHistoryDetailScreen.show(
          context,
          orderId: orderId,
          data: data,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: outlineColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length).toUpperCase()}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _status[0].toUpperCase() + _status.substring(1),
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),

            if (_dateLabel.isNotEmpty || !isPast) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (_dateLabel.isNotEmpty)
                    Expanded(
                      child: Text(
                        _dateLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  if (!isPast) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.location_on_rounded,
                            size: 10,
                            color: themeColor,
                          ),
                          SizedBox(width: 2),
                          Text(
                            "Live Tracking",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: themeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 8),
            Row(
              children: [
                ...displayThumbs.map((item) => _thumb(item)),
                if (extraCount > 0) _extraBadge(extraCount),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black38,
                  size: 20,
                ),
              ],
            ),

            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${items.length} item${items.length == 1 ? '' : 's'}",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  "Rs. ${_total.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: themeColor,
                  ),
                ),
              ],
            ),

            if (_status == 'cancelled') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: OutlinedButton.icon(
                  onPressed: () => _showCancellationDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 14),
                  label: const Text(
                    "View Cancellation Reason",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ),
            ],

            if (items.isNotEmpty && _status != 'cancelled') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 30,
                  child: ElevatedButton.icon(
                    onPressed: () async => await _reorder(context, items),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 13),
                    label: const Text(
                      "Reorder",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _thumb(Map<String, dynamic> item) {
    final imageUrl = (item['imageUrl'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackThumb(),
              )
            : _fallbackThumb(),
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 36,
      height: 36,
      color: themeColor.withOpacity(0.1),
      child: const Icon(Icons.fastfood_rounded, color: themeColor, size: 18),
    );
  }

  Widget _extraBadge(int count) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        "+$count",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: themeColor,
        ),
      ),
    );
  }

  Future<void> _reorder(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) async {
    await _reorderItems(context, items);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Items added to your cart!"),
        backgroundColor: themeColor,
      ),
    );
  }
}