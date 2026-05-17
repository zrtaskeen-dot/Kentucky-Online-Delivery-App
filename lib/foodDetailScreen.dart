import 'package:flutter/material.dart';
import 'pizza_detail.dart';
import 'items.dart';
import 'models/food_item.dart';
// where FoodItem is

class FoodDetailScreen extends StatelessWidget {
  final FoodItem item;

  const FoodDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: use item.category instead of item['category']
    if (item.category == 'PIZZA') {
      return PizzaDetailScreen(item: item);
    } else {
      return ItemDetailScreen(item: item);
    }
  }
}