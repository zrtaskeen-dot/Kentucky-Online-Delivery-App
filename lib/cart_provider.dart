import 'package:flutter/material.dart';

class CartItem {
  final String name;
  final String imageUrl;
  final double price;
  final String category;
  int quantity;

  CartItem({
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.category,
    this.quantity = 1,
  });
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice =>
      _items.fold(0, (sum, item) => sum + item.price * item.quantity);

  void addItem(CartItem newItem) {
    int index = _items.indexWhere((item) => item.name == newItem.name);

    if (index >= 0) {
      _items[index].quantity += newItem.quantity;
    } else {
      _items.add(newItem);
    }

    notifyListeners();
  }

  void increaseQuantity(CartItem item) {
    item.quantity++;
    notifyListeners();
  }

  void decreaseQuantity(CartItem item) {
    if (item.quantity > 1) {
      item.quantity--;
    } else {
      _items.remove(item);
    }
    notifyListeners();
  }
}
