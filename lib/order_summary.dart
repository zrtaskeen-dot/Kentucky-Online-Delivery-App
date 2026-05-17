import 'dart:ui';
import 'package:flutter/material.dart';
import 'cart_provider.dart';

class OrderSuccessScreen extends StatelessWidget {
  final String name;
  final String phone;
  final String address;
  final double totalAmount;
  final List<CartItem> cartItems;
  final String paymentMethod;

  const OrderSuccessScreen({
    super.key,
    required this.name,
    required this.phone,
    required this.address,
    required this.totalAmount,
    required this.cartItems,
    required this.paymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background mein aapka menu nazar aayega agar aap isse dialog ki tarah kholti hain
      // Lekin agar full screen hai toh hum stack use kar sakte hain
      body: Stack(
        children: [
          // 1. Background (Aap yahan apni menu screen ki image ya widget dal sakti hain)
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/menu_bg.png'), // Aapka menu background
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          // 2. Blur Effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),

          // 3. Details Content
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 60),
                    const SizedBox(height: 10),
                    const Text(
                      "Order Confirmed!",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const Divider(),

                    // Customer Info
                    _detailRow("Name:", name),
                    _detailRow("Phone:", phone),
                    _detailRow("Address:", address),
                    const Divider(),

                    // Items List
                    const Text("Your Items:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    ...cartItems.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${item.name} x${item.quantity}"),
                          Text("Rs. ${item.price * item.quantity}"),
                        ],
                      ),
                    )),

                    const Divider(thickness: 2),
                    _detailRow("Total Bill:", "Rs. $totalAmount", isBold: true),
                    _detailRow("Payment:", paymentMethod),
                    
                    const SizedBox(height: 20),
                    
                    // Done Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B0000),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          // Poora cart clear karke wapas home par jane ke liye
                          Navigator.popUntil(context, (route) => route.isFirst);
                        },
                        child: const Text("Back to Home", style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for rows
  Widget _detailRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? const Color(0xFF7B0000) : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}