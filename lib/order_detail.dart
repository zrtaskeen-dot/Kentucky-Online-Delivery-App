import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_provider.dart'; // For CartItem
import 'main_navigation.dart'; // 👈 CHANGED: HomeScreen ki jagah MainScreen import kiya (bottom nav bar ke liye)
import 'package:latlong2/latlong.dart';

class OrderDetailsScreen extends StatelessWidget {
  final String orderId;
  final String userName;
  final String userPhone;
  final String addressDetails;
  final List<CartItem> cartItems;
  final double totalAmount;
  final LatLng deliveryLocation;
  final String deliveryTime;
  final String paymentMethod;
  final bool receiptUploaded;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    required this.userName,
    required this.userPhone,
    required this.addressDetails,
    required this.cartItems,
    required this.totalAmount,
    required this.deliveryLocation,
    required this.deliveryTime,
    required this.paymentMethod,
    this.receiptUploaded = false,
  });

  // 👈 Matches HomeScreen's actual brand palette exactly (not a guess anymore)
  static const Color themeColor = Color(0xFFA70000); // Brand Maroon
  static const Color accentOrange = Color(0xFFFF8A00); // Brand Orange
  static const Color bgColor = Colors.white; // Pure white, same as HomeScreen
  static const Color cardColor = Color(0xFFFFFDFA); // Near-white cards
  static const Color lightMaroon = Color(0x33A70000); // ~20% maroon border

  // Delivery screen sets deliveryTime to "Standard Delivery" for
  // immediate orders, and a formatted date/time string for scheduled
  // ("Deliver Later") orders — so this is not "Standard Delivery" only
  // when the order is scheduled.
  bool get _isScheduled => deliveryTime != "Standard Delivery";

  // Delivery screen sets paymentMethod to "Cash On Delivery" for COD,
  // and the provider name (EasyPaisa/JazzCash) for online payments.
  bool get _isOnlinePayment => paymentMethod != "Cash On Delivery";

  // Only "Deliver Later" + Online, with no receipt uploaded yet, is
  // pending. If the receipt WAS already uploaded at checkout (e.g. the
  // scheduled time was within the immediate-upload window), the order
  // shows as placed successfully right away, same as any other order.
  bool get _isPendingReceiptUpload =>
      _isScheduled && _isOnlinePayment && !receiptUploaded;

  double get _itemsSubtotal =>
      cartItems.fold(0.0, (sum, item) => sum + (item.price * item.quantity));

  double get _deliveryFee {
    final diff = totalAmount - _itemsSubtotal;
    return diff > 0 ? diff : 0;
  }

  void goBackToMenu(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const MainScreen(),
      ), // 👈 CHANGED: HomeScreen -> MainScreen, taake bottom nav bar wapas aaye
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        // 👈 CHANGED: maroon app bar with white title, no back arrow (kept automaticallyImplyLeading: false)
        backgroundColor: themeColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Order Detail",
          style: TextStyle(fontWeight: FontWeight.bold, color: bgColor),
        ),
        centerTitle: true,
        // 👈 Cancel Order now lives inside this menu — off the main
        // card/view, only shown for scheduled orders.
        actions: [
          if (_isScheduled)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: bgColor),
              onSelected: (value) {
                if (value == 'cancel') _cancelOrder(context);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Cancel Order', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Status section (kept inside the details screen — for
                  // scheduled orders this is where "Confirmed" shows, not on
                  // the My Orders card) ──
                  _buildStatusBanner(),
                  const SizedBox(height: 8),

                  // ── Items ──
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cartItems.length,
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return _buildItemCard(item);
                    },
                  ),
                  const SizedBox(height: 8),

                  // ── Customer / Delivery Details Card ──
                  _buildDeliveryDetailsCard(),
                ],
              ),
            ),
          ),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  // Scheduled orders show "Confirmed" here once the receipt is uploaded
  // (or immediately for COD, since only online payment needs a receipt).
  // Non-scheduled ("Deliver Now") orders just show the placed confirmation —
  // their ongoing Pending/Accepted/Delivered status lives on the My Orders
  // card, not here.
  Widget _buildStatusBanner() {
    final String label = _isPendingReceiptUpload
        ? "Not Confirmed"
        : (_isScheduled && _isOnlinePayment)
        ? "Confirmed"
        : "Order Placed Successfully!";

    return Container(
      padding: const EdgeInsets.all(14),
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
              color: (_isPendingReceiptUpload ? Colors.orange : themeColor)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPendingReceiptUpload
                  ? Icons.hourglass_top_rounded
                  : Icons.check_circle_rounded,
              color: _isPendingReceiptUpload
                  ? Colors.orange.shade800
                  : themeColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                if (_isPendingReceiptUpload) ...[
                  const SizedBox(height: 2),
                  const Text(
                    "Order will be confirmed once you upload the receipt "
                    "two hours before delivery.",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailRow(Icons.person_rounded, "Name", userName),
          const SizedBox(height: 10),
          _detailRow(Icons.phone_rounded, "Phone", userPhone),
          const SizedBox(height: 10),
          _detailRow(Icons.location_on_rounded, "Address", addressDetails),
          const SizedBox(height: 10),
          _detailRow(Icons.schedule_rounded, "Delivery Time", deliveryTime),
          const SizedBox(height: 10),
          _detailRow(Icons.payment_rounded, "Payment Method", paymentMethod),
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

  // ── Item card uses the SAME cardColor as the details card above ──
  Widget _buildItemCard(CartItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 70,
                      height: 70,
                      color: lightMaroon,
                      child: const Icon(
                        Icons.fastfood_rounded,
                        color: themeColor,
                      ),
                    ),
                  )
                : Container(
                    width: 70,
                    height: 70,
                    color: lightMaroon,
                    child: const Icon(
                      Icons.fastfood_rounded,
                      color: themeColor,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "Rs. ${item.price.toStringAsFixed(0)} x ${item.quantity}",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Text(
            "Rs. ${(item.price * item.quantity).toStringAsFixed(0)}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: themeColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Cancels a scheduled order. Uses 'orderStatus' — same field HomeScreen
  // already reads/writes for order state (e.g. 'Delivered').
  Future<void> _cancelOrder(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Order?"),
        content: const Text(
          "Are you sure you want to cancel this scheduled order?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Yes, Cancel",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update(
        {'orderStatus': 'Cancelled'},
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Order cancelled.")));
        goBackToMenu(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to cancel order: $e")));
      }
    }
  }

  // ── Bottom Total + Button Bar (Cancel Order moved to the AppBar menu;
  // Track Order lives on the My Orders detail screen, not here) ──
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
                  "Subtotal",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  "Rs. ${_itemsSubtotal.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Delivery Fee",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  _deliveryFee == 0
                      ? "FREE"
                      : "Rs. ${_deliveryFee.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _deliveryFee == 0 ? Colors.green : Colors.black87,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "Rs. ${totalAmount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => goBackToMenu(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Back to Menu",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}