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
  // Har branch ka apna cart: branchId -> us branch ke items.
  // Cart system aik hi hai, bas items us branch ke hisaab se yaad rehte hain
  // jahan se add kiye gaye.
  final Map<String, List<CartItem>> _branchItems = {};
  String _selectedBranchId = ''; // Active branch id state
  double _deliveryCharge = 50; // Fallback until the branch's own value loads

  // Sirf ACTIVE branch ke items (baqi sab getters isi par chalte hain).
  List<CartItem> get items =>
      _branchItems.putIfAbsent(_selectedBranchId, () => <CartItem>[]);

  // Getter: read the active branch id from any screen.
  String get selectedBranchId => _selectedBranchId;

  // Setter: call this when the branch is changed on HomeScreen.
  void setBranchId(String branchId) {
    // Branch select hone se pehle jo items add hue (key ''), wo pehli
    // asli branch ke cart mein shamil kar do, warna gum ho jate.
    if (_selectedBranchId.isEmpty && branchId.isNotEmpty) {
      final orphans = _branchItems.remove('');
      if (orphans != null && orphans.isNotEmpty) {
        final target = _branchItems.putIfAbsent(branchId, () => <CartItem>[]);
        for (final item in orphans) {
          final i = target.indexWhere((e) => e.name == item.name);
          if (i >= 0) {
            target[i].quantity += item.quantity;
          } else {
            target.add(item);
          }
        }
      }
    }
    _selectedBranchId = branchId;
    notifyListeners(); // Notifies the whole app of the branch change.
  }

  // The selected branch's delivery charge, from restaurant_info.
  double get deliveryCharge => _deliveryCharge;

  void setDeliveryCharge(double charge) {
    _deliveryCharge = charge;
    notifyListeners();
  }

  // Cart badge count: ACTIVE branch ke items ki quantity ka total.
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get totalPrice {
    return items.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  void addItem(CartItem item) {
    final list = items;
    final index = list.indexWhere((element) => element.name == item.name);
    if (index >= 0) {
      list[index].quantity += item.quantity;
    } else {
      list.add(item);
    }
    notifyListeners();
  }

  void removeItem(String name) {
    items.removeWhere((item) => item.name == name);
    notifyListeners();
  }

  
  void clearCart() {
    items.clear();
    notifyListeners();
  }
}