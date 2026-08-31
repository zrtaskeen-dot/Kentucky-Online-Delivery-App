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
  String _selectedBranchId = ''; // Active branch id state

  List<CartItem> get items => _items;

  // Getter: read the active branch id from any screen.
  String get selectedBranchId => _selectedBranchId;

  // Setter: call this when the branch is changed on HomeScreen.
  void setBranchId(String branchId) {
    _selectedBranchId = branchId;
    notifyListeners(); // Notifies the whole app of the branch change.
  }

  // Updated Cart badge count: returns total sum of item quantities.
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice {
    return _items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  void addItem(CartItem item) {
    final index = _items.indexWhere((element) => element.name == item.name);
    if (index >= 0) {
      _items[index].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void removeItem(String name) {
    _items.removeWhere((item) => item.name == name);
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}