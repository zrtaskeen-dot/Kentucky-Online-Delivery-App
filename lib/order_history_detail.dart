import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'live_tracking.dart';

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
      orderData['totalAmount'] ??
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

class OrderHistoryDetailScreen extends StatelessWidget {
  const OrderHistoryDetailScreen({
    super.key,
    required this.orderId,
    required this.data,
  });

  final String orderId;
  final Map<String, dynamic> data;

  static const Color themeColor = Color(0xFFA62600);
  static const Color bgColor = Color(0xFFFEF9E7);
  static const Color cardColor = Color(0xFFFFFFF0);
  static const Color lightMaroon = Color(0xFFFFF3F1);

  static const List<String> _pastStatuses = ['delivered', 'cancelled'];

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> data,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return OrderHistoryDetailScreen(
              orderId: orderId,
              data: data,
            )._buildSheet(context, scrollController);
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> get _items => _readOrderItems(data);

  double get _total => _computeOrderTotal(data, _items);

  String get _status =>
      (data['order_status'] ?? 'pending').toString().toLowerCase();

  bool get _isActive => !_pastStatuses.contains(_status);

  bool get _hasRiderAssigned {
    final riderId =
        data['riderId'] ??
        data['rider_id'] ??
        data['assignedRiderId'] ??
        data['assigned_rider_id'] ??
        data['driverId'] ??
        data['driver_id'];
    if (riderId == null) return false;
    final s = riderId.toString().trim();
    return s.isNotEmpty && s.toLowerCase() != 'null';
  }

  String get _name => (data['customer_name'] ?? data['name'] ?? '—').toString();

  String get _phone =>
      (data['phone_number'] ?? data['phone'] ?? '—').toString();

  String get _address =>
      (data['delivery_address'] ?? data['address'] ?? '—').toString();

  String get _deliveryTime =>
      (data['delivery_time'] ?? data['deliveryTime'] ?? '—').toString();

  String get _paymentMethod =>
      (data['payment_method'] ?? data['paymentMethod'] ?? '—').toString();

  String get _dateLabel {
    final ts = data['createdAt'] ?? data['order_date'];
    if (ts is Timestamp) {
      final d = ts.toDate();
      return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    }
    return "—";
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

  @override
  Widget build(BuildContext context) {
    return _buildSheet(context, ScrollController());
  }

  Widget _buildSheet(BuildContext context, ScrollController scrollController) {
    final items = _items;

    return Container(
      decoration: const BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length).toUpperCase()}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBanner(),
                  const SizedBox(height: 16),

                  if (items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text(
                        "Items (${items.length})",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (context, index) =>
                        _buildItemCard(items[index], index),
                  ),
                  const SizedBox(height: 16),

                  _buildDetailsCard(),
                ],
              ),
            ),
          ),

          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withOpacity(0.15)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _status == 'cancelled'
                  ? Icons.cancel_rounded
                  : _status == 'delivered'
                  ? Icons.check_circle_rounded
                  : Icons.local_shipping_rounded,
              color: _statusColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status[0].toUpperCase() + _status.substring(1),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateLabel,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: themeColor.withOpacity(0.15)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(Icons.person_rounded, "Name", _name),
          const SizedBox(height: 12),
          _detailRow(Icons.phone_rounded, "Phone", _phone),
          const SizedBox(height: 12),
          _detailRow(Icons.location_on_rounded, "Address", _address),
          const SizedBox(height: 12),
          _detailRow(Icons.schedule_rounded, "Delivery Time", _deliveryTime),
          const SizedBox(height: 12),
          _detailRow(Icons.payment_rounded, "Payment Method", _paymentMethod),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: lightMaroon,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: themeColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, int index) {
    final name = (item['name'] ?? '').toString();
    final imageUrl = (item['imageUrl'] ?? '').toString();
    final category = (item['category'] ?? '').toString();
    final price = _readItemPrice(item);
    final quantity = _readItemQuantity(item).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 84,
                          height: 84,
                          color: lightMaroon,
                          child: const Icon(
                            Icons.fastfood_rounded,
                            color: themeColor,
                            size: 28,
                          ),
                        ),
                      )
                    : Container(
                        width: 84,
                        height: 84,
                        color: lightMaroon,
                        child: const Icon(
                          Icons.fastfood_rounded,
                          color: themeColor,
                          size: 28,
                        ),
                      ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: themeColor,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  child: Text(
                    "x$quantity",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? "Item ${index + 1}" : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: lightMaroon,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: themeColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  "Rs. ${price.toStringAsFixed(0)} each",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),

          Text(
            "Rs. ${(price * quantity).toStringAsFixed(0)}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: themeColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "Rs. ${_total.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),

            if (_isActive) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _hasRiderAssigned
                      ? () {
                          Navigator.of(context).pop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LiveTrackingScreen(orderId: orderId),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasRiderAssigned
                        ? themeColor
                        : Colors.grey.shade400,
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: Icon(
                    Icons.location_on_rounded,
                    color: _hasRiderAssigned ? Colors.white : Colors.white70,
                  ),
                  label: Text(
                    "Track Order",
                    style: TextStyle(
                      color: _hasRiderAssigned ? Colors.white : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              if (!_hasRiderAssigned) ...[
                const SizedBox(height: 8),
                const Text(
                  "Rider not assigned yet. You'll be able to track once a rider picks up your order.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
