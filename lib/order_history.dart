// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'dart:async';
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
  final raw =
      item['price'] ??
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
  final raw =
      orderData['totalAmount'] ;
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

String _formatPakistaniDateTime(DateTime dateTime) {
  final pkt = dateTime.toUtc().add(const Duration(hours: 5));
  final day = pkt.day.toString().padLeft(2, '0');
  final month = pkt.month.toString().padLeft(2, '0');
  final hour24 = pkt.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = pkt.minute.toString().padLeft(2, '0');
  final period = hour24 >= 12 ? 'PM' : 'AM';
  return "$day/$month/${pkt.year} $hour12:$minute $period";
}

Stream<QuerySnapshot<Map<String, dynamic>>> _streamMyOrders() {
  final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
  return FirebaseFirestore.instance
      .collection('orders')
      .where('customerId', isEqualTo: userId)
      .snapshots();
}

Future<void> _hideOrderForUser({
  required String orderId,
  required String userId,
}) async {
  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
    'hiddenFor': FieldValue.arrayUnion([userId]),
  });
}

bool _sameToppings(List<String> a, List<String> b) {
  final x = List<String>.from(a)..sort();
  final y = List<String>.from(b)..sort();
  return x.join('|') == y.join('|');
}

Future<void> _reorderItems(
  BuildContext context,
  List<Map<String, dynamic>> items, {
  required String? branchId,
}) async {
  final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';
  final cartProvider = Provider.of<CartProvider>(context, listen: false);

 
  final cartSnap = await FirebaseFirestore.instance
      .collection('carts')
      .where('userId', isEqualTo: userId)
      .get();
  final cartLines = CartService.linesFromDocs(cartSnap.docs);

  for (final item in items) {
    final name = (item['name'] ?? '').toString();
    if (name.isEmpty) continue;

    final imageUrl = (item['imageUrl'] ?? '').toString();
    final category = (item['category'] ?? '').toString();
    final price = _readItemPrice(item);
    final quantity = _readItemQuantity(item).round();
    final toppings = toppingsFromData(item['toppings']);

    CartLine? existing;
    for (final line in cartLines) {
      final lineBranch = (line.data['branchId'] ?? '').toString();
      final sameBranch =
          lineBranch.isEmpty ||
          branchId == null ||
          branchId.isEmpty ||
          lineBranch == branchId;
      if ((line.data['name'] ?? '').toString() == name &&
          sameBranch &&
          _sameToppings(toppingsFromData(line.data['toppings']), toppings)) {
        existing = line;
        break;
      }
    }

    if (existing != null) {
      final currentQty =
          int.tryParse(existing.data['quantity'].toString()) ?? 1;
      await CartService.setQuantity(existing, currentQty + quantity);
    } else {
      await CartService.addItem(userId, {
        'name': name,
        'imageUrl': imageUrl,
        'price': price,
        'category': category,
        'quantity': quantity,
        'toppings': toppings,

        if (branchId != null && branchId.isNotEmpty) 'branchId': branchId,
      });
    }

    cartProvider.addItem(
      CartItem(
        name: name,
        imageUrl: imageUrl,
        price: price,
        category: category,
        toppings: toppings,
        quantity: quantity,
      ),
    );
  }
}

class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key});

  static const Color themeColor = Color(0xFFA70000);
  static const Color accentOrange = Color(0xFFFF8A00);
  static const Color bgColor = Colors.white;
  static const Color creamColor = Colors.white;
  static const Color cardColor = Color(0xFFFFFDFA);
  static const Color outlineColor = Color(0x33A70000);

  
  static const List<String> _pastStatuses = [
    'delivered',
    'cancelled',
    'incomplete',
    'undelivered',
  ];

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final selectedBranchId = context.watch<CartProvider>().selectedBranchId;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: themeColor,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
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

          final allDocs = snapshot.data!.docs.where((doc) {
            final data = doc.data();
            final hiddenFor = List<String>.from(data['hiddenFor'] ?? const []);
            if (hiddenFor.contains(currentUserId)) return false;

            if (selectedBranchId.isNotEmpty &&
                (data['branchId'] ?? '').toString() != selectedBranchId) {
              return false;
            }
            return true;
          }).toList();

          final activeDocs = allDocs.where((doc) {
            final status = (doc.data()['orderStatus'] ?? '')
                .toString()
                .toLowerCase();
            return !_pastStatuses.contains(status);
          }).toList();

          final pastDocs = allDocs.where((doc) {
            final status = (doc.data()['orderStatus'] ?? '')
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (activeDocs.isNotEmpty) ...[
                _sectionHeader("Active Orders", Icons.local_shipping_rounded),
                const SizedBox(height: 8),
                // Active orders  can never deletable

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
                  (doc) => Dismissible(
                    key: ValueKey(doc.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) => _confirmDeleteOrder(context),
                    onDismissed: (_) {
                      _hideOrderForUser(orderId: doc.id, userId: currentUserId);
                    },
                    child: _OrderCard(
                      orderId: doc.id,
                      data: doc.data(),
                      isPast: true,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDeleteOrder(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete order?',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        content: Text(
          'Do you want to delete this order?',
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: themeColor),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
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
            color: themeColor.withValues(alpha: 0.4),
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

class _LiveTicker extends StatefulWidget {
  const _LiveTicker({required this.builder})
    : interval = const Duration(seconds: 30);

  final WidgetBuilder builder;
  final Duration interval;

  @override
  State<_LiveTicker> createState() => _LiveTickerState();
}

class _LiveTickerState extends State<_LiveTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
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
      (data['orderStatus'] ??  'pending')
          .toString()
          .toLowerCase();

  String get _dateLabel {
    final ts = data['createdAt'] ;
    if (ts is Timestamp) {
      return _formatPakistaniDateTime(ts.toDate());
    }
    return "";
  }

  String get _deliveryTime =>
      (data['deliveryTime']  ?? '—').toString();

  String get _paymentMethod =>
      (data['paymentMethod']  ?? '—').toString();

  bool get _isScheduled => _deliveryTime != "Standard Delivery";

  bool get _isOnlinePayment => _paymentMethod != "Cash On Delivery";

  String get _receiptUrl =>
      (data['receiptImageUrl'] ?? data['receipt_url'] ?? '').toString();

  // Scheduled/Online orders
  bool get _needsReceiptUpload =>
      !isPast && _isScheduled && _isOnlinePayment && _receiptUrl.isEmpty;

  Color get _statusColor {
    switch (_status) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'incomplete':
      case 'undelivered':
        return Colors.deepOrange;
      case 'on the way':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  void _showCancellationDialog(BuildContext context) {
    final bool cancelledByCustomer =
        (data['cancelledBy'] ?? '').toString() == 'customer';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: outlineColor, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cancel_rounded,
                    color: Colors.red,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "Order Cancelled",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: themeColor,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: outlineColor),
                ),
                child: Text(
                  cancelledByCustomer
                      ? "You cancelled this order."
                      : "Your order has been cancelled by the restaurant manager due to an invalid payment receipt.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "OK",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIncompleteDialog(BuildContext context) {
    _showStatusReasonDialog(
      context,
      title: "Order Incomplete",
      reason: (data['incompleteReason'] ?? '').toString().trim(),
      emptyText: "This order could not be completed.",
    );
  }

  
  void _showUndeliveredDialog(BuildContext context) {
    final String base = (data['undeliveredReason'] ?? '').toString().trim();
    final String note = (data['undeliveredNote'] ?? '').toString().trim();
    final String reason = note.isEmpty
        ? base
        : (base.isEmpty ? note : '$base\n$note');
    _showStatusReasonDialog(
      context,
      title: "Order Undelivered",
      reason: reason,
      emptyText: "Your order could not be delivered.",
    );
  }

  void _showStatusReasonDialog(
    BuildContext context, {
    required String title,
    required String reason,
    required String emptyText,
  }) {
    const Color accent = OrderHistoryScreen.accentOrange;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: outlineColor, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.report_problem_rounded,
                    color: accent,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: themeColor,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: outlineColor),
                ),
                child: Text(
                  reason.isNotEmpty ? reason : emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "OK",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        OrderHistoryDetailScreen.show(context, orderId: orderId, data: data);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: outlineColor),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.04),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          "Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length).toUpperCase()}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (_isScheduled) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: themeColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            "Scheduled",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                        ),
                      ],
                      // Confirmation status (Not Confirmed / Confirmed)
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
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

            if (_dateLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                _dateLabel,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],

            const SizedBox(height: 6),
            Row(
              children: [
                ...displayThumbs.map((item) => _thumb(item)),
                if (extraCount > 0) _extraBadge(extraCount),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black38,
                  size: 18,
                ),
              ],
            ),

            const SizedBox(height: 6),

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
                    fontSize: 13,
                    color: themeColor,
                  ),
                ),
              ],
            ),

            if (items.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 26,
                  child: ElevatedButton.icon(
                    onPressed: () async => await _reorder(
                      context,
                      items,
                      (data['branchId'] ?? '').toString(),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.replay_rounded, size: 12),
                    label: const Text(
                      "Reorder",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            if (_status == 'cancelled') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 28,
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
                  icon: const Icon(Icons.info_outline_rounded, size: 13),
                  label: const Text(
                    "View Cancellation Reason",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
            ],

            if (_status == 'incomplete' || _status == 'undelivered') ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 28,
                child: OutlinedButton.icon(
                  onPressed: () => _status == 'incomplete'
                      ? _showIncompleteDialog(context)
                      : _showUndeliveredDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: const BorderSide(color: Colors.deepOrange),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 13),
                  label: const Text(
                    "View Reason",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
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
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackThumb(),
              )
            : _fallbackThumb(),
      ),
    );
  }

  Widget _fallbackThumb() {
    return Container(
      width: 30,
      height: 30,
      color: themeColor.withValues(alpha: 0.1),
      child: const Icon(Icons.fastfood_rounded, color: themeColor, size: 16),
    );
  }

  Widget _extraBadge(int count) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        "+$count",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 10,
          color: themeColor,
        ),
      ),
    );
  }

  Future<void> _reorder(
    BuildContext context,
    List<Map<String, dynamic>> items,
    String? branchId,
  ) async {
    await _reorderItems(context, items, branchId: branchId);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Items added to your cart!"),
        backgroundColor: themeColor,
      ),
    );
  }
}