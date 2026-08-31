// // File Path: lib/presentation/screens/paymnt.dart

// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// class PaymentReceiptScreen extends StatefulWidget {
//   // Hum Amount aur Method pichli screen se mangwa rahe hain
//   final double? totalAmount;
//   final String? initialMethod;

//   const PaymentReceiptScreen({
//     super.key, 
//     this.totalAmount, 
//     this.initialMethod
//   });

//   @override
//   State<PaymentReceiptScreen> createState() => _PaymentReceiptScreenState();
// }

// class _PaymentReceiptScreenState extends State<PaymentReceiptScreen> {
//   File? _imageFile;
//   String _extractedText = "";
//   bool _isLoading = false;
  
//   // State variables
//   late String _selectedMethod;
//   final ImagePicker _picker = ImagePicker();

//   // Controllers (Initial values from previous screen)
//   late TextEditingController _amountController;
//   final TextEditingController _transactionIdController = TextEditingController();

//   @override
//   void initState() {
//     super.initState();
//     // Default values set karna
//     _selectedMethod = widget.initialMethod ?? "EasyPaisa";
//     _amountController = TextEditingController(text: widget.totalAmount?.toString() ?? "0.0");
//   }

//   // 🔴 AI DETECTION LOGIC (OCR + KEYWORDS)
//   Future<void> _processReceipt(File image) async {
//     final inputImage = InputImage.fromFile(image);
//     final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    
//     try {
//       final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
//       String resultText = recognizedText.text;
//       textRecognizer.close();

//       String textLow = resultText.toLowerCase();
//       String detected = _selectedMethod;

//       // Smart Detection Keywords
//       if (textLow.contains("easypaisa") || textLow.contains("telenor")) {
//         detected = "EasyPaisa";
//       } else if (textLow.contains("jazzcash") || textLow.contains("mobilink")) {
//         detected = "JazzCash";
//       }

//       setState(() {
//         _extractedText = resultText;
//         _selectedMethod = detected; // Automatic Update Dropdown
//         _isLoading = false;
//       });

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text("Detected: $detected"), backgroundColor: Colors.green),
//       );
//     } catch (e) {
//       textRecognizer.close();
//       setState(() => _isLoading = false);
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("OCR Error: $e")));
//     }
//   }

//   Future<void> _pickImage() async {
//     final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
//     if (pickedFile == null) return;

//     setState(() {
//       _imageFile = File(pickedFile.path);
//       _isLoading = true;
//     });

//     _processReceipt(_imageFile!);
//   }

//   // 🔴 DATA SAVE TO FIRESTORE
//   Future<void> _submitPayment() async {
//     if (_imageFile == null) {
//       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Plz upload receipt image!")));
//       return;
//     }

//     setState(() => _isLoading = true);

//     try {
//       await FirebaseFirestore.instance.collection('payments').add({
//         'method': _selectedMethod,
//         'amount': double.tryParse(_amountController.text) ?? 0.0,
//         'transactionId': _transactionIdController.text,
//         'status': 'Pending Verification',
//         'timestamp': FieldValue.serverTimestamp(),
//         'ocr_data': _extractedText,
//       });

//       setState(() => _isLoading = false);
      
//       // Success Message and Go Back
//       _showSuccessDialog();
//     } catch (e) {
//       setState(() => _isLoading = false);
//       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save Error: $e")));
//     }
//   }

//   void _showSuccessDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         title: const Icon(Icons.verified, color: Colors.green, size: 50),
//         content: const Text("Payment Receipt Submitted Successfully! Admin will verify it soon."),
//         actions: [
//           TextButton(onPressed: () {
//             Navigator.pop(context); // Close dialog
//             Navigator.pop(context); // Go back to Delivery Screen
//           }, child: const Text("OK"))
//         ],
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     const Color themeBg = Color(0xFFFFFDF0); // Cream
//     const Color themeOrange = Color(0xFFDC8B27); // Orange
//     const Color themeRed = Color(0xFFA62600); // Dark Red

//     return Scaffold(
//       backgroundColor: themeBg,
//       appBar: AppBar(
//         title: const Text("Upload Receipt", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
//         backgroundColor: themeBg,
//         elevation: 0,
//         iconTheme: const IconThemeData(color: Colors.black),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           children: [
//             // 1. Amount Info Card
//             Container(
//               padding: const EdgeInsets.all(15),
//               decoration: BoxDecoration(color: themeOrange, borderRadius: BorderRadius.circular(15)),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   const Text("Payable Amount:", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
//                   Text("RS. ${_amountController.text}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 20),

//             // 2. Upload Area
//             GestureDetector(
//               onTap: _pickImage,
//               child: Container(
//                 height: 200,
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(15),
//                   border: Border.all(color: themeOrange, width: 2, style: BorderStyle.solid),
//                 ),
//                 child: _imageFile != null
//                     ? ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.file(_imageFile!, fit: BoxFit.cover))
//                     : Column(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: const [
//                           Icon(Icons.cloud_upload, size: 50, color: Colors.grey),
//                           Text("Click to Upload Receipt Screenshot", style: TextStyle(color: Colors.grey)),
//                         ],
//                       ),
//               ),
//             ),
//             const SizedBox(height: 20),

//             // 3. Form Fields
//             DropdownButtonFormField<String>(
//               initialValue: _selectedMethod,
//               decoration: const InputDecoration(labelText: "Detected Method", border: OutlineInputBorder()),
//               items: ["EasyPaisa", "JazzCash", "Bank Transfer"].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
//               onChanged: (val) => setState(() => _selectedMethod = val!),
//             ),
//             const SizedBox(height: 12),
//             TextField(
//               controller: _transactionIdController,
//               decoration: const InputDecoration(labelText: "Transaction ID (Optional)", border: OutlineInputBorder(), hintText: "Enter Ref Number"),
//             ),

//             const SizedBox(height: 30),

//             // 4. Submit Button
//             SizedBox(
//               width: double.infinity,
//               height: 55,
//               child: ElevatedButton(
//                 onPressed: _isLoading ? null : _submitPayment,
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: themeRed,
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                 ),
//                 child: _isLoading 
//                   ? const CircularProgressIndicator(color: Colors.white)
//                   : const Text("Submit & Verify Payment", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
//               ),
//             ),

//             const SizedBox(height: 20),
//             // OCR Summary (Optional)
//             if (_extractedText.isNotEmpty)
//               ExpansionTile(
//                 title: const Text("Scanned Text (Raw Data)", style: TextStyle(fontSize: 12)),
//                 children: [Text(_extractedText, style: const TextStyle(fontSize: 10, color: Colors.grey))],
//               ),
//           ],
//         ),
//       ),
//     );
//   }
// }