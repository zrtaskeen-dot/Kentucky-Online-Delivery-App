import 'package:cloud_firestore/cloud_firestore.dart';

class SmartComboDAL {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<DocumentSnapshot>> fetchSmartComboItems({
    required String branchId,
    required String selectedPrice,
    required String categoryName,
  }) async {
    try {
      String cleanPrice = selectedPrice.replaceAll(" PKR", "").trim();

      final snapshot = await _firestore
          .collection('menu')
          .where('branchId', isEqualTo: branchId)
          .where('category', isEqualTo: categoryName.toUpperCase()) 
          .get();

     
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        if (data['prices'] != null) {
          final pricesMap = data['prices'] as Map<String, dynamic>;
          return pricesMap.values.any((value) => value.toString() == cleanPrice || value.toString() == selectedPrice);
        }
        return false;
      }).toList();
          
      return filteredDocs;
    } catch (e) {
      print("Error in SmartCombo DAL: $e");
      rethrow;
    }
  }
}