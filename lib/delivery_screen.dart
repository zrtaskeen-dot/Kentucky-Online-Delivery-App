import 'dart:ui';
import 'package:flutter/material.dart';
import 'cart_provider.dart';
import 'jazzcash_screen.dart';
import 'order_summary.dart'; // Create this file for summary
import 'firebase.dart';

class DeliveryScreen extends StatefulWidget {
  final double totalAmount;
  final List<CartItem> cartItems;

  const DeliveryScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
  });

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  String deliveryTime = "Now";
  String paymentMethod = "Cash on Delivery";
  
  final FirestoreService _firestoreService = FirestoreService();
  
  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();

  // ✅ Step 1: Save Order & Show Confirmation
  Future<void> handleOrderConfirmation() async {
    if (nameController.text.isEmpty || phoneController.text.isEmpty || addressController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all details and pick address! 📍")),
      );
      return;
    }

    try {
      // Save to Firestore
      await _firestoreService.saveOrder(
        name: nameController.text,
        phone: phoneController.text,
        address: addressController.text,
        totalAmount: widget.totalAmount,
        deliveryTime: deliveryTime,
        paymentMethod: paymentMethod,
        cartItems: widget.cartItems,
      );

      // Show Success Dialog with Blur
      showOrderPopup();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  // ✅ Step 2: Background Blur Dialog
  void showOrderPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Icon(Icons.check_circle, color: Colors.green, size: 60),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Order Placed!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 10),
              Text("Thank you ${nameController.text}, your order is being prepared."),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B0000)),
                onPressed: () {
                  Navigator.pop(context); // Close Popup
                  // Navigate to Final Success Screen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OrderSuccessScreen(
                        name: nameController.text,
                        phone: phoneController.text,
                        address: addressController.text,
                        totalAmount: widget.totalAmount,
                        cartItems: widget.cartItems,
                        paymentMethod: paymentMethod,
                      ),
                    ),
                  );
                },
                child: const Text("View Details", style: TextStyle(color: Colors.white)),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ✅ Step 3: JazzCash Logic
  Future<void> openJazzCash() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => JazzCashScreen(amount: widget.totalAmount)),
    );
    if (result == true) {
      setState(() => paymentMethod = "JazzCash Paid");
      handleOrderConfirmation();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Delivery Details"), backgroundColor: Colors.white, foregroundColor: Colors.black),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Contact Info", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            TextField(controller: nameController, decoration: const InputDecoration(hintText: "Name", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: "Phone", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            
            // Address with Map Icon
            TextField(
              controller: addressController,
              readOnly: true, // Takay sirf Map se aaye
              decoration: InputDecoration(
                hintText: "Select Address from Map",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.red),
                  onPressed: () {
                    // Yahan aap apna Google Map Picker call karein
                    // Example: addressController.text = selectedAddressFromMap;
                  },
                ),
              ),
            ),

            const SizedBox(height: 20),
            const Text("Delivery Time", style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile(title: const Text("Now"), value: "Now", groupValue: deliveryTime, onChanged: (v) => setState(() => deliveryTime = v!)),
            RadioListTile(title: const Text("Later"), value: "Later", groupValue: deliveryTime, onChanged: (v) => setState(() => deliveryTime = v!)),

            const SizedBox(height: 20),
            const Text("Payment Method", style: TextStyle(fontWeight: FontWeight.bold)),
            RadioListTile(title: const Text("Cash on Delivery"), value: "Cash on Delivery", groupValue: paymentMethod, onChanged: (v) => setState(() => paymentMethod = v!)),
            RadioListTile(title: const Text("JazzCash"), value: "JazzCash", groupValue: paymentMethod, onChanged: (v) {
              setState(() => paymentMethod = v!);
              openJazzCash();
            }),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: handleOrderConfirmation,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B0000)),
                child: const Text("Confirm Order", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}