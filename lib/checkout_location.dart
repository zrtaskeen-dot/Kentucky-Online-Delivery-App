// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:provider/provider.dart';
// import 'cart_provider.dart';
// import 'delivery_screen.dart'; // ✅ you forgot this import

// class CheckoutLocationScreen extends StatefulWidget {
//   final double totalAmount;

//   const CheckoutLocationScreen({super.key, required this.totalAmount});

//   @override
//   State<CheckoutLocationScreen> createState() => _CheckoutLocationScreenState();
// }

// class _CheckoutLocationScreenState extends State<CheckoutLocationScreen> {
//   GoogleMapController? mapController;
//   LatLng? userLocation;
//   LatLng? selectedLocation;

//   bool isLoading = true; // ✅ loading control

//   @override
//   void initState() {
//     super.initState();

//     // ✅ avoid context issue
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       getCurrentLocation();
//     });
//   }

//   Future<void> getCurrentLocation() async {
//     bool serviceEnabled;
//     LocationPermission permission;

//     // ✅ check location service
//     serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) {
//       showMessage("Please enable location services");
//       setState(() => isLoading = false);
//       return;
//     }

//     // ✅ check permission
//     permission = await Geolocator.checkPermission();

//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//     }

//     if (permission == LocationPermission.denied) {
//       showMessage("Location permission denied");
//       setState(() => isLoading = false);
//       return;
//     }

//     if (permission == LocationPermission.deniedForever) {
//       showMessage("Enable permission from settings");
//       setState(() => isLoading = false);
//       return;
//     }

//     // ✅ get location
//     try {
//       Position position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );

//       setState(() {
//         userLocation = LatLng(position.latitude, position.longitude);
//         selectedLocation = userLocation;
//         isLoading = false;
//       });
//     } catch (e) {
//       showMessage("Error getting location");
//       setState(() => isLoading = false);
//     }
//   }

//   void showMessage(String msg) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//   }

//   @override
//   Widget build(BuildContext context) {
//     final cartProvider = Provider.of<CartProvider>(context, listen: false);

//     return Scaffold(
//       backgroundColor: const Color(0xffFFF7DD),
//       appBar: AppBar(
//         backgroundColor: Colors.white,
//         title: const Text("Checkout", style: TextStyle(color: Colors.black)),
//         centerTitle: true,
//         iconTheme: const IconThemeData(color: Colors.black),
//       ),

//       body: isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : userLocation == null
//           ? const Center(child: Text("Location not available"))
//           : SingleChildScrollView(
//               child: Column(
//                 children: [
//                   SizedBox(
//                     height: 350,
//                     child: GoogleMap(
//                       initialCameraPosition: CameraPosition(
//                         target: userLocation!,
//                         zoom: 16,
//                       ),
//                       myLocationEnabled: true,
//                       myLocationButtonEnabled: true,
//                       onMapCreated: (controller) => mapController = controller,
//                       onTap: (pos) {
//                         setState(() => selectedLocation = pos);
//                       },
//                       markers: {
//                         Marker(
//                           markerId: const MarkerId("selected"),
//                           position: selectedLocation!,
//                           draggable: true,
//                           onDragEnd: (pos) =>
//                               setState(() => selectedLocation = pos),
//                         ),
//                       },
//                     ),
//                   ),

//                   const SizedBox(height: 20),

//                   Padding(
//                     padding: const EdgeInsets.symmetric(horizontal: 25),
//                     child: TextField(
//                       decoration: InputDecoration(
//                         hintText: "Street No",
//                         filled: true,
//                         fillColor: Colors.white,
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: BorderSide.none,
//                         ),
//                       ),
//                     ),
//                   ),

//                   const SizedBox(height: 12),

//                   Padding(
//                     padding: const EdgeInsets.symmetric(horizontal: 25),
//                     child: TextField(
//                       decoration: InputDecoration(
//                         hintText: "House No",
//                         filled: true,
//                         fillColor: Colors.white,
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: BorderSide.none,
//                         ),
//                       ),
//                     ),
//                   ),

//                   const SizedBox(height: 25),

//                   ElevatedButton(
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: const Color(0xffA53F0C),
//                       padding: const EdgeInsets.symmetric(
//                         horizontal: 40,
//                         vertical: 12,
//                       ),
//                     ),
//                     onPressed: () {
//                       if (selectedLocation == null) {
//                         showMessage("Please pick a location");
//                         return;
//                       }

//                       Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => DeliveryScreen(
//                             totalAmount: widget.totalAmount,
//                             cartItems: cartProvider.items,
//                             selectedLocation: selectedLocation!,
//                           ),
//                         ),
//                       );
//                     },
//                     child: const Text(
//                       "Next",
//                       style: TextStyle(color: Colors.white),
//                     ),
//                   ),

//                   const SizedBox(height: 20),
//                 ],
//               ),
//             ),
//     );
//   }
// }
