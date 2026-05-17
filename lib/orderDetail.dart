import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // For LatLng
import 'cart_provider.dart'; // For CartItem
import 'main.dart'; // For FoodMenuApp (Menu/Home Screen)

class OrderDetailsScreen extends StatelessWidget {
  // 1. RECEIVES ALL THE FINAL DATA
  final List<CartItem> cartItems; // From Cart
  final double totalAmount; // From Cart
  final LatLng deliveryLocation; // From DeliveryScreen
  final String deliveryTime; // Now/Later
  final String paymentMethod; // Cash/JazzCash

  const OrderDetailsScreen({
    super.key,
    required this.cartItems,
    required this.totalAmount,
    required this.deliveryLocation,
    required this.deliveryTime,
    required this.paymentMethod,
  });

  // 2. NAVIGATE BACK TO MENU FUNCTION
  void goBackToMenu(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const FoodMenuApp()),
      (Route<dynamic> route) => false, // Clears all previous routes
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF7B0000),
        title: const Text("Order Confirmation"),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // --- SECTION 1: FOOD ITEMS LIST ---
          Expanded(
            child: ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final item = cartItems[index];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: Image.network(
                      item.imageUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.fastfood),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      "Rs. ${item.price.toStringAsFixed(0)} x ${item.quantity}",
                    ),
                    trailing: Text(
                      "Rs. ${(item.price * item.quantity).toStringAsFixed(0)}",
                    ),
                  ),
                );
              },
            ),
          ),

          // --- SECTION 2: SUMMARY PANEL ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Total: Rs ${totalAmount.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text("Delivery Time: $deliveryTime"),
                Text("Payment Method: $paymentMethod"),
                Text(
                  "Location: (${deliveryLocation.latitude.toStringAsFixed(3)}, ${deliveryLocation.longitude.toStringAsFixed(3)})",
                ),
              ],
            ),
          ),

          // --- SECTION 3: FINAL BUTTONS ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Cancel Order Button
                ElevatedButton(
                  onPressed: () => goBackToMenu(context),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                  child: const Text("Cancel Order"),
                ),
                // Confirm Order Button
                ElevatedButton(
                  onPressed: () {
                    // Here you can send order to backend if needed
                    goBackToMenu(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B0000),
                  ),
                  child: const Text(
                    "Confirm & Done",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
