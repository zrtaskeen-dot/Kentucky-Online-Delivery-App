// File Path: lib/logic/controllers/payment_controller.dart

import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../../repository/payment_repository.dart';

class PaymentController {
  final PaymentRepository _repository = PaymentRepository();

  Future<String> processAndSaveReceipt({
    required File image,
    required String orderId,
    required String paymentId,
    required String paymentMethod,
    required String paymentStatus,
    required double amount,
    required String branchId,
  }) async {
    final inputImage = InputImage.fromFile(image);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    
    try {
      // 1. Image se text extract karna (OCR)
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      String extractedText = recognizedText.text;
      textRecognizer.close();

      if (extractedText.trim().isEmpty) {
        return "Receipt par koi text nahi mila. Koshish karein ke image saaf ho.";
      }

      // 2. Data Layer ko call karna bagair User ID ke
      await _repository.saveReceiptToDatabase(
        orderId: orderId,
        paymentId: paymentId,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        amount: amount,
        receiptText: extractedText,
        branchId: branchId,
      );

      return extractedText;
      
    } catch (e) {
      textRecognizer.close();
      throw Exception("Business Logic Error: $e");
    }
  }
}