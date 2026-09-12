// Shared "Upload Receipt" button used by both order_detail.dart (right
// after placing a scheduled Online order) and order_history_detail.dart
// (when revisiting that order later from order history). Handles the
// whole flow: pick image -> OCR-verify it's a real EasyPaisa/JazzCash
// receipt -> upload to Cloudinary -> save the URL on the order doc.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ReceiptUploadButton extends StatefulWidget {
  const ReceiptUploadButton({
    super.key,
    required this.orderId,
    required this.provider,
    this.onUploaded,
  });

  final String orderId;

  /// The online payment provider for this order — "EasyPaisa" or
  /// "JazzCash" — used both for OCR verification and as the Cloudinary tag.
  final String provider;

  /// Optional callback fired after the receipt is successfully saved,
  /// in case the parent screen wants to refresh itself.
  final VoidCallback? onUploaded;

  @override
  State<ReceiptUploadButton> createState() => _ReceiptUploadButtonState();
}

class _ReceiptUploadButtonState extends State<ReceiptUploadButton> {
  static const Color themeColor = Color(0xFFA62600);
  static const String _cloudinaryUrl =
      "https://api.cloudinary.com/v1_1/dqjqkwwwh/image/upload";
  static const String _receiptUploadPreset = "payment_receipts";

  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  bool _uploaded = false;

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Same OCR check used at checkout in delivery_screen.dart — confirms
  // the screenshot actually mentions the selected provider before we
  // accept it as a valid receipt.
  Future<bool> _verifyReceipt(File file) async {
    final inputImage = InputImage.fromFile(file);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final scannedText = recognizedText.text.toLowerCase();
      await textRecognizer.close();

      if (widget.provider == 'EasyPaisa') {
        return scannedText.contains('easypaisa') ||
            scannedText.contains('easy paisa') ||
            scannedText.contains('telenor microfinance');
      } else if (widget.provider == 'JazzCash') {
        return scannedText.contains('jazzcash') ||
            scannedText.contains('jazz cash') ||
            scannedText.contains('mobilink microfinance');
      }
      // Unrecognized provider label — skip strict text match rather than
      // block the upload outright.
      return true;
    } catch (e) {
      await textRecognizer.close();
      return false;
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_cloudinaryUrl))
        ..fields['upload_preset'] = _receiptUploadPreset
        ..fields['tags'] = widget.provider
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();
      if (streamedResponse.statusCode != 200) return null;

      final data = jsonDecode(responseBody);
      return data['secure_url'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleUpload() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isUploading = true);
    final file = File(picked.path);

    final isValid = await _verifyReceipt(file);
    if (!isValid) {
      if (mounted) setState(() => _isUploading = false);
      _showSnack(
        "Invalid screenshot! Please upload a correct ${widget.provider} receipt.",
        themeColor,
      );
      return;
    }

    final url = await _uploadToCloudinary(file);
    if (url == null) {
      if (mounted) setState(() => _isUploading = false);
      _showSnack("Upload failed. Please try again.", themeColor);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .update({
        'receiptImageUrl': url,
        'receiptUploadedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _uploaded = true;
      });
      _showSnack(
        "Receipt uploaded! Your order will be confirmed shortly.",
        Colors.green.shade700,
      );
      widget.onUploaded?.call();
    } catch (e) {
      if (mounted) setState(() => _isUploading = false);
      _showSnack("Could not save receipt. Please try again.", themeColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uploaded) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            SizedBox(width: 8),
            Text(
              "Receipt uploaded",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isUploading ? null : _handleUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: themeColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: _isUploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.upload_rounded, color: Colors.white),
        label: Text(
          _isUploading ? "Uploading..." : "Upload ${widget.provider} Receipt",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}