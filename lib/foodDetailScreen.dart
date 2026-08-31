import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/food_item.dart';

class FoodDetailScreen extends StatefulWidget {
  final FoodItem item;
  final String selectedBranchId;

  const FoodDetailScreen({
    super.key,
    required this.item,
    required this.selectedBranchId,
  });

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  static const primary = Color(0xFFB12C00);
  static const bgColor = Color(0xFFFFFDF3);

  int quantity = 1;
  bool isAddingToCart = false;
  String selectedSize = '';
  Set<String> selectedToppings = {};
  Map<String, Map<String, dynamic>> toppingsData = {};
  bool loadingToppings = true;

  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  bool get isPizza => widget.item.category.toLowerCase().contains('pizza');
  bool get isWings => widget.item.category.toLowerCase().contains('wing');

  bool get hasSizes {
    final dynamic prices = widget.item.prices;
    if (prices is! Map || prices.isEmpty) return false;
    final keys = prices.keys.toList();
    if (keys.length == 1 && keys.first.toString().toLowerCase() == 'simple') {
      return false;
    }
    return true;
  }

  String get sizeSelectorTitle => isWings ? 'Select Pieces' : 'Select Size';

  // 🟢 Size key ko readable label mein convert karo
  String _formatSizeLabel(String key) {
    switch (key.toLowerCase()) {
      case 'small':
        return 'Small';
      case 'medium':
        return 'Medium';
      case 'large':
        return 'Large';
      case 'xlarge':
        return 'X-Large';
      case '6pcs':
        return '6 Pcs';
      case '12pcs':
        return '12 Pcs';
      case '05l':
        return '0.5L';
      case '1l':
        return '1L';
      case '15l':
        return '1.5L';
      case '2l':
        return '2L';
      case 'simple':
        return 'Standard';
      default:
        return key.toUpperCase();
    }
  }

  Map<String, dynamic> get pricesMap =>
      (widget.item.prices is Map && (widget.item.prices as Map).isNotEmpty)
      ? Map<String, dynamic>.from(widget.item.prices as Map)
      : {};

  double _parseSizeValue(String key) {
    final match = RegExp(r'^(\d+(\.\d+)?)').firstMatch(key.trim());
    if (match == null) return double.infinity;
    final numStr = match.group(1)!;
    double value = double.tryParse(numStr) ?? double.infinity;
    if (!numStr.contains('.') && numStr.length == 2) {
      value = value / 10;
    }
    return value;
  }

  List<String> get sortedSizeKeys {
    final keys = pricesMap.keys.toList();
    keys.sort((a, b) => _parseSizeValue(a).compareTo(_parseSizeValue(b)));
    return keys;
  }

  int get basePrice {
    final dynamic prices = widget.item.prices;
    if (prices == null) return 0;
    if (prices is Map) {
      if (prices.isEmpty) return 0;
      if (selectedSize.isNotEmpty && prices.containsKey(selectedSize)) {
        return int.tryParse(prices[selectedSize].toString()) ?? 0;
      }
      if (sortedSizeKeys.isNotEmpty) {
        return int.tryParse(prices[sortedSizeKeys.first].toString()) ?? 0;
      }
      return int.tryParse(prices.values.first.toString()) ?? 0;
    }
    return double.tryParse(prices.toString())?.round() ?? 0;
  }

  int get toppingsPrice {
    int total = 0;
    for (final id in selectedToppings) {
      final t = toppingsData[id];
      if (t != null) {
        total += int.tryParse(t['price'].toString()) ?? 0;
      }
    }
    return total;
  }

  int get totalPrice => (basePrice + toppingsPrice) * quantity;

  @override
  void initState() {
    super.initState();
    if (hasSizes) {
      selectedSize = sortedSizeKeys.first;
    }
    _fetchToppings();
  }

  Future<void> _fetchToppings() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('toppings')
          .where('category', isEqualTo: widget.item.category)
          .get();
      setState(() {
        toppingsData = {for (var d in snap.docs) d.id: d.data()};
        loadingToppings = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to fetch toppings: $e');
      setState(() => loadingToppings = false);
    }
  }

  Future<void> _addToCart() async {
    setState(() => isAddingToCart = true);
    try {
      final int price = totalPrice;

      if (price <= 0) {
        debugPrint(
          '⚠️ totalPrice resolved to 0 for "${widget.item.name}". '
          'Raw prices field: ${widget.item.prices} '
          '(type: ${widget.item.prices.runtimeType}) '
          'basePrice=$basePrice toppingsPrice=$toppingsPrice quantity=$quantity',
        );
      }

      final toppingNames = selectedToppings
          .map((id) => toppingsData[id]?['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      await FirebaseFirestore.instance.collection('carts').add({
        'userId': userId,
        'branchId': widget.selectedBranchId,
        'name': hasSizes && selectedSize.isNotEmpty
            ? '${widget.item.name} (${_formatSizeLabel(selectedSize)})'
            : widget.item.name,
        'price': price,
        'quantity': quantity,
        'imageUrl': widget.item.imageUrl,
        'category': widget.item.category,
        'selectedSize': hasSizes ? selectedSize : 'regular',
        'toppings': toppingNames,
        'isSmartCombo': false,
        'addedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.item.name} added to cart!',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('❌ Add to cart failed: $e');
      debugPrint('$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isAddingToCart = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: primary,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildImage(widget.item.imageUrl),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.item.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              'Rs. $totalPrice',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (widget.item.description.isNotEmpty)
                          _infoCard(
                            title: 'Ingredients',
                            child: Text(
                              widget.item.description,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                                height: 1.5,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        if (hasSizes) ...[
                          _infoCard(
                            title: sizeSelectorTitle,
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: sortedSizeKeys.map((sizeKey) {
                                final isSelected = selectedSize == sizeKey;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => selectedSize = sizeKey),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? primary
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? primary
                                            : Colors.grey.shade300,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: primary.withAlpha(60),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          _formatSizeLabel(sizeKey), // 🟢 fix
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Rs. ${pricesMap[sizeKey]}',
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white70
                                                : Colors.grey[500],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (!loadingToppings && toppingsData.isNotEmpty)
                          _infoCard(
                            title: 'Extra Toppings',
                            child: Column(
                              children: toppingsData.entries.map((entry) {
                                final id = entry.key;
                                final topping = entry.value;
                                final name = topping['name']?.toString() ?? '';
                                final price =
                                    topping['price']?.toString() ?? '0';
                                final selected = selectedToppings.contains(id);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (selected) {
                                        selectedToppings.remove(id);
                                      } else {
                                        selectedToppings.add(id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFFFFF3F3)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? primary
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: selected
                                                ? primary
                                                : Colors.white,
                                            border: Border.all(
                                              color: selected
                                                  ? primary
                                                  : Colors.grey.shade400,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: selected
                                              ? const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 13,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '+$price',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? primary
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 16),

                        _infoCard(
                          title: 'Quantity',
                          child: _buildQuantityRectBox(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.1),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        'Rs. $totalPrice',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                        onPressed: isAddingToCart ? null : _addToCart,
                        child: isAddingToCart
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'ADD TO CART',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(String url) {
    return url.isNotEmpty
        ? Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(),
          )
        : _placeholder();
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFFFF3E0),
    child: const Center(
      child: Icon(Icons.fastfood_rounded, size: 80, color: primary),
    ),
  );

  Widget _infoCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildQuantityRectBox() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _qtyRectButton("-", () {
          if (quantity > 1) setState(() => quantity--);
        }),
        Container(
          width: 44,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: primary.withOpacity(0.4)),
            ),
          ),
          child: Text(
            "$quantity",
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        _qtyRectButton("+", () => setState(() => quantity++)),
      ],
    );
  }

  Widget _qtyRectButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: primary.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: primary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}
