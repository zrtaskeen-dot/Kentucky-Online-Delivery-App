import 'package:cloud_firestore/cloud_firestore.dart';

class SmartComboDAL {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🔹 Selected Branch, Selected Price aur Category ke mutabiq precise items filter karna
  Future<List<DocumentSnapshot>> fetchSmartComboItems({
    required String branchId,
    required String selectedPrice,
    required String categoryName,
  }) async {
    try {
      // String se ' PKR' remove kar rahe hain agar aap database mein sirf number (jaise 700 ya 1250) save kar rahi hain
      String cleanPrice = selectedPrice.replaceAll(" PKR", "").trim();

      final snapshot = await _firestore
          .collection('menu')
          .where('branchId', isEqualTo: branchId)
          .where('category', isEqualTo: categoryName.toUpperCase()) // Jaise 'PIZZA', 'BURGER'
          .get();

      // 🔥 Memory level filter: Sirf un items ko filter karna jinki deal/combo price selected price se match kare
      // Yeh tab best hai agar aapke prices map ka structure dynamic ho
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        if (data['prices'] != null) {
          final pricesMap = data['prices'] as Map<String, dynamic>;
          // Agar aapne direct combo price map key banayi hui hai ya price check karni hai:
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