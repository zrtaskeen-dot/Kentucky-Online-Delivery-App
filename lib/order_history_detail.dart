import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'live_tracking.dart';
import 'receipt_upload_button.dart';

// Rebuilds [builder] every [interval] so time-based UI — like the
// scheduled-order cancel window — keeps itself up to date while this
// bottom sheet stays open, instead of only updating when it's first
// shown. Without this, a customer reading the order details as the
// clock crosses the 1h30m cutoff wouldn't see the Cancel button
// disappear until they closed and reopened the sheet.
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

  // 👈 Matches HomeScreen's actual brand palette: white bg + orange/maroon
  static const Color themeColor = Color(0xFFA70000); // Brand Maroon
  static const Color accentOrange = Color(0xFFFF8A00); // Brand Orange
  static const Color bgColor = Colors.white;
  static const Color cardColor = Color(0xFFFFFDFA);
  static const Color lightMaroon = Color(0x33A70000);

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

  // The rider/rider's name who accepted the order — shown inside the
  // details once assigned, alongside the customer's own delivery details.
  String? get _riderName {
    final name =
        data['riderName'] ??
        data['rider_name'] ??
        data['assignedRiderName'] ??
        data['assigned_rider_name'] ??
        data['driverName'] ??
        data['driver_name'];
    final s = (name ?? '').toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'null') return null;
    return s;
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

  // Delivery screen sets this to "Standard Delivery" for immediate
  // orders, and a formatted date/time string for scheduled orders.
  bool get _isScheduled => _deliveryTime != "Standard Delivery";

  // Delivery screen sets this to "Cash On Delivery" for COD, and the
  // provider name (EasyPaisa/JazzCash) for online payments.
  bool get _isOnlinePayment => _paymentMethod != "Cash On Delivery";

  String get _receiptUrl =>
      (data['receiptImageUrl'] ?? data['receipt_url'] ?? '').toString();

  // Only Deliver Later + Online orders that haven't had a receipt
  // uploaded yet need this button — and only while the order is still
  // active (not delivered/cancelled).
  bool get _needsReceiptUpload =>
      _isActive && _isScheduled && _isOnlinePayment && _receiptUrl.isEmpty;

  // Parses delivery_screen.dart's "6 Sep 2026 at 05:30 PM" label back
  // into a DateTime, so we can gate the upload button to the last hour
  // before delivery. Returns null if it can't be parsed.
  DateTime? get _scheduledDateTime {
    if (!_isScheduled) return null;
    try {
      final parts = _deliveryTime.split(' at ');
      if (parts.length != 2) return null;

      final dateSegs = parts[0].trim().split(' ');
      if (dateSegs.length != 3) return null;
      final day = int.tryParse(dateSegs[0]);
      final year = int.tryParse(dateSegs[2]);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months.indexOf(dateSegs[1]) + 1;
      if (day == null || year == null || month == 0) return null;

      final timeMatch = RegExp(
        r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
        caseSensitive: false,
      ).firstMatch(parts[1].trim());
      if (timeMatch == null) return null;

      int hour = int.parse(timeMatch.group(1)!);
      final minute = int.parse(timeMatch.group(2)!);
      final period = timeMatch.group(3)!.toUpperCase();
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  // True once we're within 2 hours of the scheduled delivery time (or if
  // the label couldn't be parsed at all — fails open rather than
  // permanently blocking the upload).
  bool get _isWithinUploadWindow {
    final dt = _scheduledDateTime;
    if (dt == null) return true;
    return !DateTime.now().isBefore(dt.subtract(const Duration(hours: 2)));
  }

  bool get _canUploadReceiptNow => _needsReceiptUpload && _isWithinUploadWindow;

  // How long before the scheduled delivery time a customer is still
  // allowed to cancel this order.
  static const Duration _cancelCutoff = Duration(hours: 1, minutes: 30);

  // True while the order can still be cancelled: it must be a scheduled
  // order, still active (not delivered/cancelled), the scheduled time
  // must have parsed successfully, and we must be more than 1h30m away
  // from it. Unlike the upload window above, this fails *closed* if the
  // time can't be parsed — better to block a cancellation than to let
  // one through this close to (or past) delivery due to a parsing bug.
  bool get _canCancelOrder {
    if (!_isActive || !_isScheduled) return false;
    final dt = _scheduledDateTime;
    if (dt == null) return false;
    return DateTime.now().isBefore(dt.subtract(_cancelCutoff));
  }

  String get _dateLabel {
    final ts = data['createdAt'] ?? data['order_date'];
    if (ts is Timestamp) {
      // ✅ Pakistan Standard Time hai (UTC+5, no DST) — device ki apni
      // timezone se independent, taake result hamesha PKT mein sahi ho.
      final d = ts.toDate().toUtc().add(const Duration(hours: 5));
      final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final period = d.hour >= 12 ? 'PM' : 'AM';
      return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  "
          "${hour12.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $period";
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

  // ── DELETE (HIDE-ONLY) ──
  // Same approach as OrderHistoryScreen: never deletes the Firestore order
  // document — just adds this customer's uid to its `hiddenFor` array, so
  // it disappears from their history list while the order record stays
  // saved (for the restaurant's own records).
  Future<void> _confirmDeleteOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
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

    if (confirmed != true) return;

    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'hiddenFor': FieldValue.arrayUnion([userId]),
    });

    // Order is now hidden from the list — close this detail sheet too,
    // since it no longer has anywhere to return to.
    if (context.mounted) Navigator.of(context).pop();
  }

  // ── CANCEL (customer-initiated) ──
  // Only reachable while _canCancelOrder is true, but we re-check the
  // cutoff right before writing in case a few minutes passed between
  // opening this confirmation dialog and tapping "Cancel Order".
  Future<void> _confirmCancelOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel this order?',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        content: Text(
          'This will cancel your scheduled order for $_deliveryTime. '
          'This action cannot be undone.',
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(
              'Cancel Order',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!_canCancelOrder) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Too close to the delivery time to cancel now."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'order_status': 'cancelled',
      'cancelledBy': 'customer',
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Your order has been cancelled."),
          backgroundColor: Colors.black87,
        ),
      );
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
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          "Order #${orderId.substring(0, orderId.length > 6 ? 6 : orderId.length).toUpperCase()}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (_isScheduled) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: themeColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Text(
                            "Scheduled",
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                        ),
                      ],
                      if (_isScheduled &&
                          _isOnlinePayment &&
                          !_needsReceiptUpload) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            "Confirmed",
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                      if (_needsReceiptUpload) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            "Not Confirmed",
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
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

          // Delete only makes sense for past orders (delivered/cancelled)
          // — active orders can't be deleted from here.
          if (!_isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _confirmDeleteOrder(context),
                  style: TextButton.styleFrom(
                    foregroundColor: themeColor,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: const Text(
                    "Delete from History",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
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
                  const SizedBox(height: 8),

                  if (items.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
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
                  const SizedBox(height: 8),

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
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
    final riderName = _riderName;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(Icons.person_rounded, "Name", _name),
          const SizedBox(height: 10),
          _detailRow(Icons.phone_rounded, "Phone", _phone),
          const SizedBox(height: 10),
          _detailRow(Icons.location_on_rounded, "Address", _address),
          const SizedBox(height: 10),
          _detailRow(Icons.schedule_rounded, "Delivery Time", _deliveryTime),
          const SizedBox(height: 10),
          _detailRow(Icons.payment_rounded, "Payment Method", _paymentMethod),
          if (riderName != null) ...[
            const SizedBox(height: 10),
            _detailRow(Icons.delivery_dining_rounded, "Rider", riderName),
          ],
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
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
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
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: lightMaroon),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
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

            if (_isScheduled && _isActive) ...[
              const SizedBox(height: 16),
              _LiveTicker(
                builder: (context) => _canCancelOrder
                    ? SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () => _confirmCancelOrder(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text(
                            "Cancel Order",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_clock_rounded,
                              size: 18,
                              color: Colors.black45,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "This order can no longer be cancelled — "
                                "it's within 1 hour 30 minutes of the "
                                "scheduled delivery time.",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black54,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],

            if (_needsReceiptUpload) ...[
              const SizedBox(height: 16),
              if (_canUploadReceiptNow)
                ReceiptUploadButton(orderId: orderId, provider: _paymentMethod)
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_clock_rounded,
                        size: 18,
                        color: Colors.black45,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "Receipt upload opens 2 hours before your "
                          "scheduled delivery time.",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

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
