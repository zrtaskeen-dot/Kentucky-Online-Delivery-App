import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/price_u.dart';
import 'checkout_location.dart';
import 'cart_provider.dart';
import 'login_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  static const Color themeColor = Color(0xFFB12C00);
  static const Color bgColor = Color(0xFFFEF9E7);
  static const Color lightMaroon = Color(0xFFFFF3F1);
  static const Color cardColor = Color(0xFFFFFFF0);

  static const double _freeDeliveryThreshold = 500;
  static const double _deliveryFee = 50;

  double _calculateDeliveryFee(double subtotal) {
    return subtotal < _freeDeliveryThreshold ? _deliveryFee : 0;
  }

  Future<void> _updateQuantity(String docId, int currentQty, int change) async {
    int newQty = currentQty + change;
    if (newQty <= 0) {
      await FirebaseFirestore.instance.collection('carts').doc(docId).delete();
    } else {
      await FirebaseFirestore.instance.collection('carts').doc(docId).update({
        'quantity': newQty,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String userId =
        FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.black,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          "My Cart",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('carts')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: themeColor),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "Your cart is empty 🛒",
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          var cartDocs = snapshot.data!.docs;
          double calculatedTotalPrice = 0;
          List<CartItem> structuredCartItems = [];

          for (var doc in cartDocs) {
            var data = doc.data() as Map<String, dynamic>;
            double price = readPriceValue(data['price']);
            int qty = readItemQuantity(data).round();
            calculatedTotalPrice += (price * qty);

            structuredCartItems.add(
              CartItem(
                name: data['name'] ?? 'Item',
                imageUrl: data['imageUrl'] ?? '',
                price: price,
                category: data['category'] ?? 'FastFood',
                quantity: qty,
              ),
            );
          }

          final double deliveryFee = _calculateDeliveryFee(
            calculatedTotalPrice,
          );
          final double grandTotal = calculatedTotalPrice + deliveryFee;

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  itemCount: cartDocs.length,
                  itemBuilder: (context, index) {
                    var docId = cartDocs[index].id;
                    var item = cartDocs[index].data() as Map<String, dynamic>;

                    bool isSmartCombo = item['isSmartCombo'] ?? false;
                    String itemName = item['name'] ?? 'Item';
                    int itemPrice = readPriceValue(item['price']).round();
                    int itemQty = readItemQuantity(item).round();
                    String imgUrl = item['imageUrl'] ?? '';
                    String category = item['category'] ?? 'FastFood';
                    List<dynamic> nestedItems = item['comboItems'] ?? [];

                    if (isSmartCombo && nestedItems.isNotEmpty) {
                      return _buildComboCard(
                        docId: docId,
                        itemName: itemName,
                        itemPrice: itemPrice,
                        itemQty: itemQty,
                        nestedItems: nestedItems,
                      );
                    }

                    return _buildRegularItemCard(
                      docId: docId,
                      itemName: itemName,
                      itemPrice: itemPrice,
                      itemQty: itemQty,
                      imgUrl: imgUrl,
                      category: category,
                    );
                  },
                ),
              ),

              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Subtotal",
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            "Rs. ${calculatedTotalPrice.toStringAsFixed(0)}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Delivery Fee",
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            deliveryFee == 0
                                ? "FREE"
                                : "Rs. ${deliveryFee.toStringAsFixed(0)}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: deliveryFee == 0
                                  ? Colors.green
                                  : Colors.black87,
                            ),
                          ),
                        ],
                      ),

                      if (deliveryFee > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              "Add Rs. ${(_freeDeliveryThreshold - calculatedTotalPrice).toStringAsFixed(0)} more for free delivery",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ),
                        ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            "Rs. ${grandTotal.toStringAsFixed(0)}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: themeColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: Consumer<CartProvider>(
                          builder: (context, cartProvider, child) {
                            return ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () {
                                final user = FirebaseAuth.instance.currentUser;
                                String globalBranchId =
                                    cartProvider.selectedBranchId;

                                if (user == null || user.isAnonymous) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Please log in or sign up to proceed with your order.",
                                      ),
                                      backgroundColor: themeColor,
                                      duration: Duration(seconds: 3),
                                    ),
                                  );

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginScreen(
                                        role: 'customer',
                                        allowSignup: true,
                                      ),
                                    ),
                                  ).then((_) {
                                    final currentUser =
                                        FirebaseAuth.instance.currentUser;
                                    if (currentUser != null &&
                                        !currentUser.isAnonymous) {
                                      if (context.mounted) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CheckoutLocationScreen(
                                                  totalAmount: grandTotal,
                                                  cartItems:
                                                      structuredCartItems,
                                                  branchId: globalBranchId,
                                                ),
                                          ),
                                        );
                                      }
                                    }
                                  });
                                  return;
                                }

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CheckoutLocationScreen(
                                      totalAmount: grandTotal,
                                      cartItems: structuredCartItems,
                                      branchId: globalBranchId,
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                "Checkout",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRegularItemCard({
    required String docId,
    required String itemName,
    required int itemPrice,
    required int itemQty,
    required String imgUrl,
    required String category,
  }) {
    int totalLinePrice = itemPrice * itemQty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withOpacity(0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imgUrl.isNotEmpty
                ? Image.network(
                    imgUrl,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: 90,
                      height: 90,
                      color: lightMaroon,
                      child: const Icon(
                        Icons.fastfood,
                        color: themeColor,
                        size: 30,
                      ),
                    ),
                  )
                : Container(
                    width: 90,
                    height: 90,
                    color: lightMaroon,
                    child: const Icon(
                      Icons.fastfood,
                      color: themeColor,
                      size: 30,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemName,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  category,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      "Rs. $totalLinePrice",
                      style: const TextStyle(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (itemQty > 1) ...[
                      const SizedBox(width: 6),
                      Text(
                        "(Rs. $itemPrice each)",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildQuantityBox(docId, itemQty),
                    InkWell(
                      onTap: () => FirebaseFirestore.instance
                          .collection('carts')
                          .doc(docId)
                          .delete(),
                      child: const Text(
                        "REMOVE",
                        style: TextStyle(
                          color: themeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComboCard({
    required String docId,
    required String itemName,
    required int itemPrice,
    required int itemQty,
    required List<dynamic> nestedItems,
  }) {
    String comboImgUrl = nestedItems.isNotEmpty
        ? (nestedItems.first['imageUrl']?.toString() ?? '')
        : '';

    String comboContents = nestedItems
        .map((e) => e['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .join(' + ');

    int totalLinePrice = itemPrice * itemQty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeColor.withOpacity(0.15)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: comboImgUrl.isNotEmpty
                ? Image.network(
                    comboImgUrl,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: 90,
                      height: 90,
                      color: lightMaroon,
                      child: const Icon(
                        Icons.auto_awesome,
                        color: themeColor,
                        size: 30,
                      ),
                    ),
                  )
                : Container(
                    width: 90,
                    height: 90,
                    color: lightMaroon,
                    child: const Icon(
                      Icons.auto_awesome,
                      color: themeColor,
                      size: 30,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: themeColor, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        itemName,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comboContents.isNotEmpty ? comboContents : 'Smart Combo',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      "Rs. $totalLinePrice",
                      style: const TextStyle(
                        color: themeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (itemQty > 1) ...[
                      const SizedBox(width: 6),
                      Text(
                        "(Rs. $itemPrice each)",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildQuantityBox(docId, itemQty),
                    InkWell(
                      onTap: () => FirebaseFirestore.instance
                          .collection('carts')
                          .doc(docId)
                          .delete(),
                      child: const Text(
                        "REMOVE",
                        style: TextStyle(
                          color: themeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityBox(String docId, int currentQty) {
    return Row(
      children: [
        _qtyButton("-", () => _updateQuantity(docId, currentQty, -1)),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: themeColor.withOpacity(0.4)),
            ),
          ),
          child: Text(
            "$currentQty",
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        _qtyButton("+", () => _updateQuantity(docId, currentQty, 1)),
      ],
    );
  }

  Widget _qtyButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: themeColor.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: themeColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}