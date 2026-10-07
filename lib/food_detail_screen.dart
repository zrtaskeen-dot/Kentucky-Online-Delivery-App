import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // App Theme Colors (matches the rest of the app's maroon brand palette)
  static const Color themeColor = Color(0xFFA70000); // Main Maroon Accent
  static const Color bgColor = Colors.white; // Matches cardColor/bottom bar
  static const Color lightMaroon = Color(0x33A70000);
  static const Color cardColor = Color(0xFFFFFDFA);

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

  // Combo / Deals items describe what is included, so their text is
  // shown under "Description" instead of "Ingredients".
  bool get isComboOrDeal {
    final c = widget.item.category.toLowerCase();
    return c.contains('combo') || c.contains('deal');
  }

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

  Map<String, dynamic> get pricesMap => ((widget.item.prices as Map).isNotEmpty)
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

  int get unitPrice => basePrice + toppingsPrice;
  int get totalPrice => unitPrice * quantity;

  @override
  void initState() {
    super.initState();
    _qtyFocus.addListener(_onQtyFocusChange);
    if (hasSizes) {
      selectedSize = sortedSizeKeys.first;
    }
    _fetchToppings();
  }

  // ── Quantity limits ──────────────────────────────────────────────
  // "+" button yahan tak jata hai. Isse zyada ke liye customer number par
  // tap karke khud type kar sakta hai (maxLength 5 => 99,999 tak).
  static const int _stepperMaxQty = 500;
  static const int _manualMaxQty = 99999;

  final TextEditingController _qtyController = TextEditingController(text: '1');
  final FocusNode _qtyFocus = FocusNode();

  @override
  void dispose() {
    _qtyFocus.removeListener(_onQtyFocusChange);
    _qtyFocus.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _onQtyFocusChange() {
    // Field se bahar jate hi typed value ko theek (normalize) kar do.
    if (!_qtyFocus.hasFocus) _commitQtyText();
  }

  // Quantity ko 1.._manualMaxQty mein rakhta hai aur text field ko sync karta hai.
  void _setQuantity(int value) {
    if (!mounted) return;
    final int q = value.clamp(1, _manualMaxQty).toInt();
    setState(() => quantity = q);
    final String text = q.toString();
    if (_qtyController.text != text) {
      _qtyController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  // Typing ke dauran: valid number ho to total foran update hota hai.
  // Khali ya 0 ho to last valid quantity rehti hai (field abhi edit ho raha hai).
  void _onQtyTyped(String raw) {
    final int? parsed = int.tryParse(raw);
    if (parsed != null && parsed >= 1) {
      setState(() => quantity = parsed);
    }
  }

  // Edit khatam: khali/0 ho to last valid quantity wapas, warna "007" -> "7".
  void _commitQtyText() {
    final int? parsed = int.tryParse(_qtyController.text);
    _setQuantity((parsed == null || parsed < 1) ? quantity : parsed);
  }

  void _incrementQty() {
    if (quantity >= _stepperMaxQty) return; // zyada ke liye number par tap karo
    FocusScope.of(context).unfocus();
    _setQuantity(quantity + 1);
  }

  void _decrementQty() {
    if (quantity <= 1) return;
    FocusScope.of(context).unfocus();
    _setQuantity(quantity - 1);
  }

  Future<void> _fetchToppings() async {
    try {
      // NOTE: assumes topping documents carry a `branchId` field, the
      // same way cart entries do (see 'branchId': widget.selectedBranchId
      // below) — adjust the field name here if your toppings collection
      // uses a different one.
      final snap = await FirebaseFirestore.instance
          .collection('toppings')
          .where('category', isEqualTo: widget.item.category)
          .where('branchId', isEqualTo: widget.selectedBranchId)
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
    // Keyboard band karo aur typed quantity final kar do.
    FocusScope.of(context).unfocus();
    _commitQtyText();
    setState(() => isAddingToCart = true);
    try {
      final int price = unitPrice;

      final toppingNames = selectedToppings
          .map((id) => toppingsData[id]?['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      await FirebaseFirestore.instance
          .collection('carts')
          .add({
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
          })
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Add to cart timed out'),
          );

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
            backgroundColor: themeColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please check your internet connection and try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                backgroundColor: themeColor,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 6),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ),
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
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        if (widget.item.description.isNotEmpty)
                          _infoCard(
                            title: isComboOrDeal ? 'Description' : 'Ingredients',
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
                                          ? themeColor
                                          : cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? themeColor
                                            : Colors.grey.shade300,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: themeColor.withAlpha(60),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ]
                                          : [],
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          _formatSizeLabel(sizeKey),
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
                                                : Colors.grey[600],
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
                                      color: selected ? lightMaroon : cardColor,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? themeColor
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
                                                ? themeColor
                                                : cardColor,
                                            border: Border.all(
                                              color: selected
                                                  ? themeColor
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
                                                ? themeColor
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
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -2),
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
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
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
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
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
    color: lightMaroon,
    child: const Center(
      child: Icon(Icons.fastfood_rounded, size: 80, color: themeColor),
    ),
  );

  Widget _infoCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
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
    final bool atStepperMax = quantity >= _stepperMaxQty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _qtyRectButton("-", _decrementQty, enabled: quantity > 1),
            Container(
              width: 72,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              // Tap karke seedha type kar sakte hain.
              child: TextField(
                controller: _qtyController,
                focusNode: _qtyFocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                maxLength: 5,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                cursorColor: themeColor,
                onTap: () => _qtyController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _qtyController.text.length,
                ),
                onChanged: _onQtyTyped,
                onSubmitted: (_) => _commitQtyText(),
                onTapOutside: (_) => _qtyFocus.unfocus(),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            _qtyRectButton("+", _incrementQty, enabled: !atStepperMax),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          atStepperMax
              ? 'Maximum $_stepperMaxQty Items Quantity.'
              : 'Tap the number to type a custom quantity.',
          style: TextStyle(
            fontSize: 11.5,
            color: atStepperMax ? themeColor : Colors.grey[600],
            fontWeight: atStepperMax ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _qtyRectButton(
    String label,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? themeColor : Colors.grey.shade400,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}