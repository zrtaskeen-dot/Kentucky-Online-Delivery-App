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
    this.deadline,
  });

  final String orderId;
  final String provider;
  final VoidCallback? onUploaded;
  final DateTime? deadline;

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
  String? _bannerMessage;
  bool _bannerIsError = true;

  
  static const Color _successBorder = Color(0xFF4A7C59);
  static const Color _successBg = Color(0xFFEAF3ED);
  static const Color _successText = Color(0xFF2F5B3E);
  static const Color _errorBorder = Color(0xFFC62828);
  static const Color _errorBg = Color(0xFFFDECEA);
  static const Color _errorText = Color(0xFFB71C1C);

  // OCR check
  
  Future<bool> _verifyReceipt(File file) async {
    final inputImage = InputImage.fromFile(file);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final scannedText = recognizedText.text.toLowerCase();
      await textRecognizer.close();

      final bool looksLikeEasyPaisa =
          scannedText.contains('easypaisa') ||
          scannedText.contains('easy paisa') ||
          scannedText.contains('telenor microfinance');
      final bool looksLikeJazzCash =
          scannedText.contains('jazzcash') ||
          scannedText.contains('jazz cash') ||
          scannedText.contains('mobilink microfinance');

      if (widget.provider == 'EasyPaisa') return looksLikeEasyPaisa;
      if (widget.provider == 'JazzCash') return looksLikeJazzCash;

      
      return looksLikeEasyPaisa || looksLikeJazzCash;
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

   
    if (widget.deadline != null && !DateTime.now().isBefore(widget.deadline!)) {
      if (!mounted) return;
      setState(() {
        _bannerIsError = true;
        _bannerMessage = "Time's up — this order can no longer be confirmed.";
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _bannerMessage = null; 
    });
    final file = File(picked.path);

    final isValid = await _verifyReceipt(file);
    if (!isValid) {
      if (!mounted) return;
      final String providerLabel =
          (widget.provider == 'EasyPaisa' || widget.provider == 'JazzCash')
          ? widget.provider
          : 'EasyPaisa or JazzCash';
      setState(() {
        _isUploading = false;
        _bannerIsError = true;
        _bannerMessage =
            "Invalid screenshot! Please upload a correct $providerLabel receipt.";
      });
      return;
    }

    final url = await _uploadToCloudinary(file);
    if (url == null) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _bannerIsError = true;
        _bannerMessage = "Upload failed. Please try again.";
      });
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
        _bannerIsError = false;
        _bannerMessage =
            "Receipt uploaded! Your order will be confirmed shortly.";
      });
      widget.onUploaded?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _bannerIsError = true;
        _bannerMessage = "Could not save receipt. Please try again.";
      });
    }
  }

  Widget _buildBanner() {
    final borderColor = _bannerIsError ? _errorBorder : _successBorder;
    final fillColor = _bannerIsError ? _errorBg : _successBg;
    final textColor = _bannerIsError ? _errorText : _successText;
    final icon = _bannerIsError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _bannerMessage!,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_uploaded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_bannerMessage != null) _buildBanner(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
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
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_bannerMessage != null) _buildBanner(),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _handleUpload,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.upload_rounded, color: Colors.white, size: 18),
            label: Text(
             
              _isUploading ? "Uploading..." : "Upload Receipt",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}