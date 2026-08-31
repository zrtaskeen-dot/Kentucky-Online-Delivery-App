import 'package:flutter/material.dart';
import 'cart_provider.dart'; // Aapki cart provider file
import 'delivery_screen.dart'; // Doosri screen ko link karne k liye
// import 'package:google_maps_flutter/google_maps_flutter.dart'; // 👈 Yeh import add karein
import 'package:latlong2/latlong.dart';

class UserDetailsScreen extends StatefulWidget {
  final double totalAmount;
  final List<CartItem> cartItems;

  const UserDetailsScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
  });

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFFFFFDF0); // Cream background
    const Color buttonColor = Color(0xFFA62600); // Red/Orange button

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20.0),
          child: Column(
            children: [
              // Back Button Row
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.black,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(height: 20),

              // 🍕 Pizza Animation / Image Placeholder
              Container(
                height: 220,
                width: 220,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(
                      'assets/pizza_image.png',
                    ), // Apni asset image ka path dein
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 50),

              // Name Input Field
              TextField(
                controller: nameController,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "Name",
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Phone Number Input Field
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "Phone Number (3XXXXXXXXX)",
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: Colors.black),
                  ),
                ),
              ),
              const SizedBox(height: 60),

              // 🚀 Next Button
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isEmpty ||
                      phoneController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please fill all details! ⚠️"),
                      ),
                    );
                    return;
                  }

                  // Data lekar DeliveryScreen par shift hona
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DeliveryScreen(
                        totalAmount: widget.totalAmount,
                        cartItems: widget.cartItems,
                        userName: nameController.text,
                        userPhone: phoneController.text,
                        selectedLocation: const LatLng(
                          0.0,
                          0.0,
                        ), // ✅ Required field satisfies (No error in other files)
                        addressDetails: "Address not provided via map",
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  minimumSize: const Size(180, 45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  "Next",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
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
}
