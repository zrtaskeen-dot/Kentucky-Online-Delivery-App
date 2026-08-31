import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/food_item.dart';

class PizzaDetailScreen extends StatefulWidget {
  final FoodItem item;
  final String selectedBranchId;

  const PizzaDetailScreen({
    super.key,
    required this.item,
    required this.selectedBranchId,
  });

  @override
  State<PizzaDetailScreen> createState() => _PizzaDetailScreenState();
}

class _PizzaDetailScreenState extends State<PizzaDetailScreen> {
  static const primary = Color(0xFFB12C00); // Maroon theme (matches app)
  static const bgColor = Color(0xFFFFFDF3);

  // ── State ─────────────────────────────────────────────────────
  String selectedSize = '';
  int quantity = 1;
  bool isAddingToCart = false;
  Set<String> selectedToppings = {};
  Map<String, Map<String, dynamic>> toppingsData = {};
  bool loadingToppings = true;

  // Matches CartScreen's fallback guest id.
  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  // ── Pizza size visual scale (circle sizing) ────────────────────
  static const Map<String, double> sizeVisualScale = {
    'small': 0.55,
    'Small': 0.55,
    'medium': 0.68,
    'Medium': 0.68,
    'large': 0.82,
    'Large': 0.82,
    'xlarge': 1.0,
    'XLarge': 1.0,
    'xl': 1.0,
    'XL': 1.0,
    '6pcs': 0.6,
    '12pcs': 1.0,
  };

  Map<String, dynamic> get pricesMap =>
      Map<String, dynamic>.from(widget.item.prices as Map);

  // Forces a proper Small → Medium → Large → XLarge display order
  // regardless of how Firestore returns the map keys.
  static const List<String> _sizeSortOrder = [
    'small',
    'medium',
    'large',
    'xlarge',
    'xl',
    '6pcs',
    '12pcs',
  ];

  List<String> get sortedSizeKeys {
    final keys = pricesMap.keys.toList();
    keys.sort((a, b) {
      final ai = _sizeSortOrder.indexOf(a.toLowerCase());
      final bi = _sizeSortOrder.indexOf(b.toLowerCase());
      final aIndex = ai == -1 ? _sizeSortOrder.length : ai;
      final bIndex = bi == -1 ? _sizeSortOrder.length : bi;
      return aIndex.compareTo(bIndex);
    });
    return keys;
  }

  int get basePrice {
    if (selectedSize.isNotEmpty && pricesMap.containsKey(selectedSize)) {
      return int.tryParse(pricesMap[selectedSize].toString()) ??
          double.tryParse(pricesMap[selectedSize].toString())?.round() ??
          0;
    }
    return 0;
  }

  int get toppingsPrice {
    int total = 0;
    for (final id in selectedToppings) {
      final t = toppingsData[id];
      if (t != null) total += int.tryParse(t['price'].toString()) ?? 0;
    }
    return total;
  }

  int get totalPrice => (basePrice + toppingsPrice) * quantity;

  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    debugPrint(
      'PizzaDetailScreen opened for "${widget.item.name}" | '
      'prices=${widget.item.prices} (type: ${widget.item.prices.runtimeType}) | '
      'userId=$userId',
    );

    if (pricesMap.isNotEmpty) {
      selectedSize = sortedSizeKeys.first; // smallest size by proper order
    } else {
      debugPrint(
        'pricesMap is EMPTY for "${widget.item.name}". '
        'This item has no size options, so basePrice will always be 0 '
        'unless you fix its Firestore "prices" field to be a Map like '
        '{"small": 500, "large": 800}.',
      );
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
        toppingsData = {
          for (var d in snap.docs) d.id: d.data(),
        };
        loadingToppings = false;
      });
    } catch (e) {
      debugPrint('Failed to fetch toppings: $e');
      setState(() => loadingToppings = false);
    }
  }

  Future<void> _addToCart() async {
    setState(() => isAddingToCart = true);
    try {
      final int price = totalPrice;

      debugPrint(
        'Adding to cart -> name: ${widget.item.name}, '
        'size: $selectedSize, basePrice: $basePrice, '
        'toppingsPrice: $toppingsPrice, totalPrice: $price, '
        'userId: $userId, branchId: ${widget.selectedBranchId}',
      );

      if (price <= 0) {
        debugPrint(
          'Warning: totalPrice is 0. Check that "${widget.item.name}" '
          'has a valid "prices" Map field in Firestore with a matching '
          'key for size "$selectedSize".',
        );
      }

      final toppingNames = selectedToppings
          .map((id) => toppingsData[id]?['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      final docRef = await FirebaseFirestore.instance.collection('carts').add({
        'userId': userId,
        'branchId': widget.selectedBranchId,
        'name': '${widget.item.name} ($selectedSize)',
        'price': price,
        'quantity': quantity,
        'imageUrl': widget.item.imageUrl,
        'category': widget.item.category,
        'selectedSize': selectedSize,
        'toppings': toppingNames,
        'isSmartCombo': false,
        'addedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Successfully written to Firestore. Doc ID: ${docRef.id}');

      if (mounted) {
        // Success snackbar now uses the app's maroon theme color
        // instead of green, so it matches the rest of the app.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.item.name} added to cart!'),
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
      debugPrint('Add to cart FAILED: $e');
      debugPrint('$stack');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong: $e'),
            backgroundColor: primary,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isAddingToCart = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Pizza Image ──────────────────────────────────
                _buildTopImage(),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title ──────────────────────────────────
                      Text(
                        widget.item.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // ── Description card ───────────────────────
                      if (widget.item.description.isNotEmpty)
                        _card(
                          title: 'Ingredients',
                          child: Text(
                            widget.item.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              height: 1.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),

                      // ── SIZE SELECTOR (fixed to single line) ────
                      if (pricesMap.isNotEmpty)
                        _card(
                          title: 'Select Size',
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: sortedSizeKeys.map((sizeKey) {
                                final isSelected = selectedSize == sizeKey;
                                final scale =
                                    sizeVisualScale[sizeKey] ??
                                    sizeVisualScale[sizeKey.toLowerCase()] ??
                                    0.7;
                                final circleSize = 44.0 + (scale * 28);

                                return Padding(
                                  padding: const EdgeInsets.only(right: 22),
                                  child: GestureDetector(
                                    onTap: () => setState(
                                      () => selectedSize = sizeKey,
                                    ),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          width: circleSize,
                                          height: circleSize,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? primary.withAlpha(15)
                                                : Colors.grey.shade100,
                                            border: Border.all(
                                              color: isSelected
                                                  ? primary
                                                  : Colors.grey.shade300,
                                              width: isSelected ? 2.5 : 1.5,
                                            ),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: primary
                                                          .withAlpha(50),
                                                      blurRadius: 8,
                                                      offset: const Offset(
                                                        0,
                                                        3,
                                                      ),
                                                    ),
                                                  ]
                                                : [],
                                          ),
                                          child: ClipOval(
                                            child:
                                                widget.item.imageUrl.isNotEmpty
                                                ? Image.network(
                                                    widget.item.imageUrl,
                                                    width: circleSize,
                                                    height: circleSize,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, __, ___) => Icon(
                                                          Icons
                                                              .local_pizza_rounded,
                                                          size:
                                                              circleSize *
                                                              0.52,
                                                          color: isSelected
                                                              ? primary
                                                              : Colors
                                                                    .grey
                                                                    .shade400,
                                                        ),
                                                  )
                                                : Icon(
                                                    Icons.local_pizza_rounded,
                                                    size: circleSize * 0.52,
                                                    color: isSelected
                                                        ? primary
                                                        : Colors.grey.shade400,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _formatSizeLabel(sizeKey),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? primary
                                                : Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          'Rs.${pricesMap[sizeKey]}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isSelected
                                                ? primary
                                                : Colors.grey[500],
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        )
                      else
                        // ── No size map -> show plain price instead ──
                        _card(
                          title: 'Price',
                          child: Text(
                            'Rs. ${widget.item.prices}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),

                      // ── Extra Toppings ────────────────────────
                      if (!loadingToppings && toppingsData.isNotEmpty)
                        _card(
                          title: 'Extra Topping',
                          child: Column(
                            children: toppingsData.entries.map((entry) {
                              final id = entry.key;
                              final topping = entry.value;
                              final name = topping['name']?.toString() ?? '';
                              final price = topping['price']?.toString() ?? '0';
                              final sel = selectedToppings.contains(id);

                              return GestureDetector(
                                onTap: () => setState(() {
                                  sel
                                      ? selectedToppings.remove(id)
                                      : selectedToppings.add(id);
                                }),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? const Color(0xFFFFF3F3)
                                        : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel
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
                                          color: sel ? primary : Colors.white,
                                          border: Border.all(
                                            color: sel
                                                ? primary
                                                : Colors.grey.shade400,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: sel
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
                                            fontWeight: sel
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
                                          color: sel
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
                      const SizedBox(height: 14),

                      // ── Quantity (rectangle box style, matches cart) ──
                      _card(title: 'Quantity', child: _buildQuantityRectBox()),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky Add to Cart ─────────────────────────────────
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

  // ── Top image with back button ────────────────────────────────
  Widget _buildTopImage() {
    return Stack(
      children: [
        Container(
          height: 280,
          width: double.infinity,
          color: Colors.grey.shade100,
          child: widget.item.imageUrl.isNotEmpty
              ? Image.network(
                  widget.item.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.local_pizza_rounded,
                      size: 80,
                      color: primary,
                    ),
                  ),
                )
              : const Center(
                  child: Icon(
                    Icons.local_pizza_rounded,
                    size: 80,
                    color: primary,
                  ),
                ),
        ),
        // Back button
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.15),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.black87,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────
  String _formatSizeLabel(String key) {
    switch (key.toLowerCase()) {
      case 'small':
        return 'Small';
      case 'medium':
        return 'Medium';
      case 'large':
        return 'Large';
      case 'xlarge':
        return 'XLarge';
      case 'xl':
        return 'XLarge';
      case '6pcs':
        return '6 Pcs';
      case '12pcs':
        return '12 Pcs';
      default:
        return key;
    }
  }

  Widget _card({required String title, required Widget child}) {
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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Quantity control: rectangle box "- qty +" ──────────────────
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