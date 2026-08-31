// File Path: lib/data/repositories/payment_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveReceiptToDatabase({
    required String orderId,
    required String paymentId,
    required String paymentMethod,
    required String paymentStatus,
    required double amount,
    required String receiptText,
    required String branchId, // Branch linking field
  }) async {
    try {
      // 'payments' collection mein naya document save ho raha hai
      await _firestore.collection('payments').add({
        'orderId': orderId,
        'branchId': branchId, // Foreign Key link
        'paymentId': paymentId, // Transaction Ref Number
        'paymentMethod': paymentMethod,
        'amount': amount,
        'paymentStatus': paymentStatus, 
        'receiptText': receiptText, // OCR parsed text
        'adminRemarks': "", 
        'uploadedAt': FieldValue.serverTimestamp(), 
        'verifiedAt': null, 
      });
      
      print("Data Layer: Payment doc saved for branch: $branchId (Without User ID)");
    } catch (e) {
      throw Exception("Data Layer Error: $e");
    }
  }
}