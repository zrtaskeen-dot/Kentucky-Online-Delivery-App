import 'package:flutter/material.dart';
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
  });

  static const Color themeColor = Color(0xFFA62600);
  static const Color bgColor = Color(0xFFFEF9E7);
  static const Color cardColor = Color(0xFFFFFFF0);
  static const Color lightMaroon = Color(0xFFFFF3F1);

  void goBackToMenu(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()), // 👈 CHANGED: HomeScreen -> MainScreen, taake bottom nav bar wapas aaye
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        // 👈 CHANGED: maroon app bar with cream title, no back arrow (kept automaticallyImplyLeading: false)
        backgroundColor: themeColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          "Order Detail",
          style: TextStyle(fontWeight: FontWeight.bold, color: bgColor),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Items now shown first, no separate section header ──
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cartItems.length,
                    itemBuilder: (context, index) {
                      final item = cartItems[index];
                      return _buildItemCard(item);
                    },
                  ),
                  const SizedBox(height: 16),

                  // ── Customer / Delivery Details Card ──
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: themeColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Order Placed Successfully!",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFEEEEEE)),
          const SizedBox(height: 12),
          _detailRow(Icons.person_rounded, "Name", userName),
          const SizedBox(height: 12),
          _detailRow(Icons.phone_rounded, "Phone", userPhone),
          const SizedBox(height: 12),
          _detailRow(Icons.location_on_rounded, "Address", addressDetails),
          const SizedBox(height: 12),
          _detailRow(Icons.schedule_rounded, "Delivery Time", deliveryTime),
          const SizedBox(height: 12),
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
        border: Border.all(color: Colors.black.withOpacity(0.15)),
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

  // ── Bottom Total + Button Bar (Track Order button removed) ──
  Widget _buildBottomBar(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        // 👈 CHANGED: same field/card color as the rest of the flow instead of plain white
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
                  "Rs. ${totalAmount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => goBackToMenu(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  "Back to Menu",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
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