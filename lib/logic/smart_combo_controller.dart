import 'package:cloud_firestore/cloud_firestore.dart';
import '../repository/smart_combo_dal.dart';
import '../models/food_item.dart';

class SmartComboController {
  final SmartComboDAL _dal = SmartComboDAL();

  // Raw documents ko process karke standard FoodItem list mein convert karna
  Future<List<FoodItem>> getComboSpecificItems({
    required String branchId,
    required String price,
    required String category,
  }) async {
    try {
      List<DocumentSnapshot> docs = await _dal.fetchSmartComboItems(
        branchId: branchId,
        selectedPrice: price,
        categoryName: category,
      );
      return docs.map((doc) => FoodItem.fromFirestore(doc)).toList();
    } catch (e) {
      print("Error in SmartCombo Controller: $e");
      return [];
    }
  }
}