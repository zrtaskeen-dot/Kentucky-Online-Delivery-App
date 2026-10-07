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

  // Success/error message card colors — same palette used on the
  // Login/Signup screens, kept consistent app-wide.
  static const Color successBorder = Color(0xFF4A7C59);
  static const Color successBg = Color(0xFFEAF3ED);
  static const Color successText = Color(0xFF2F5B3E);
  static const Color errorBorder = Color(0xFFC62828);
  static const Color errorBg = Color(0xFFFDECEA);
  static const Color errorText = Color(0xFFB71C1C);

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

  // Same compact, single-line, colored-card snackbar style used on the
  // Login/Signup screens — green for success, red for error.
  void _showThemedSnack(
    BuildContext context,
    String msg, {
    bool isError = true,
  }) {
    final borderColor = isError ? errorBorder : successBorder;
    final fillColor = isError ? errorBg : successBg;
    final textColor = isError ? errorText : successText;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
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

                  // ── Customer / Delivery Details Card (now also holds
                  // the ordered items below the detail rows, in the same
                  // card) ──
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
                    "1.5 hours before delivery.",
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

          // ── Items — shown inside this same card, right below the
          // delivery details, with no image and tight spacing so the
          // card doesn't balloon in height. ──
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          const Text(
            "Items",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          ...List.generate(cartItems.length, (index) {
            final item = cartItems[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index > 0) const Divider(height: 12, thickness: 0.5),
                _buildItemRow(item),
              ],
            );
          }),
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

  // ── Compact item row: no image, just name/price/qty — used inside
  // the details card above instead of its own bordered card. ──
  Widget _buildItemRow(CartItem item) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                "Rs. ${item.price.toStringAsFixed(0)} x ${item.quantity}",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        Text(
          "Rs. ${(item.price * item.quantity).toStringAsFixed(0)}",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: themeColor,
            fontSize: 13,
          ),
        ),
      ],
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
        _showThemedSnack(context, "Order cancelled.", isError: false);
        goBackToMenu(context);
      }
    } catch (e) {
      if (context.mounted) {
        _showThemedSnack(context, "Failed to cancel order: $e");
      }
    }
  }

  
  Widget _buildBottomBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
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
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                Text(
                  "Rs. ${_itemsSubtotal.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Delivery Fee",
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                Text(
                  _deliveryFee == 0
                      ? "FREE"
                      : "Rs. ${_deliveryFee.toStringAsFixed(0)}",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _deliveryFee == 0 ? Colors.green : Colors.black87,
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Total",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  "Rs. ${totalAmount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: () => goBackToMenu(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Back to Menu",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
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