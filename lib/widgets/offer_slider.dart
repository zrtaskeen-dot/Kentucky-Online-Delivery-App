// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OfferSlider extends StatefulWidget {
  final String branchId;

  const OfferSlider({super.key, required this.branchId});

  @override
  State<OfferSlider> createState() => _OfferSliderState();
}

class _OfferSliderState extends State<OfferSlider> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  Timer? _timer;

  static const primary = Color(0xFFA70000);
  static const priceColor = Color(0xFFFFC857);
  static const orange = Color(0xFFFF8A00);
  static const sheetBg = Colors.white;
  static const itemCardColor = Color(0xFFFFFDFA);
  static const lightMaroonBorder = Color(0x33A70000);
  static const int maxQty = 500;

  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoSlide(int itemCount) {
    _timer?.cancel();
    if (itemCount <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_controller.hasClients) return;
      if (_currentPage < itemCount - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }
      _controller.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  bool _isOfferCurrentlyActive(Map<String, dynamic> data) {
    final isActive = data['isActive'] == true;
    if (!isActive) return false;

    final startStr = data['startDate']?.toString();
    final endStr = data['endDate']?.toString();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (startStr != null && startStr.isNotEmpty) {
      final start = DateTime.tryParse(startStr);
      if (start != null && today.isBefore(start)) return false;
    }
    if (endStr != null && endStr.isNotEmpty) {
      final end = DateTime.tryParse(endStr);
      if (end != null && today.isAfter(end)) return false;
    }
    return true;
  }

  String _formatPrice(dynamic prices) {
    final value = _priceValue(prices);
    return value > 0 ? 'Rs. $value' : '';
  }

  int _priceValue(dynamic prices) {
    if (prices is Map && prices.isNotEmpty) {
      final map = Map<String, dynamic>.from(prices);
      final raw = map['simple'] ?? map['Simple'] ?? map.values.first;
      return int.tryParse(raw.toString()) ?? 0;
    }
    if (prices != null) {
      return double.tryParse(prices.toString())?.round() ?? 0;
    }
    return 0;
  }

  List<String> _splitItems(String description) {
    if (description.isEmpty) return [];
    final parts = description.split(RegExp(r'\d+\.\s*'));
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  // Bottom sheet: offer details,order
  void _openOfferSheet(Map<String, dynamic> offer) {
    final name = (offer['name'] ?? offer['eventName'] ?? 'Offer').toString();
    final description = (offer['description'] ?? '').toString();
    final imageUrl = offer['imageUrl']?.toString();
    final price = _priceValue(offer['prices']);
    final items = _splitItems(description);

    int quantity = 1;
    bool isAdding = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> addOfferToCart() async {
              setSheetState(() => isAdding = true);
              try {
                await FirebaseFirestore.instance.collection('carts').add({
                  'userId': userId,
                  'branchId': widget.branchId,
                  'name': name,
                  'price': price,
                  'quantity': quantity,
                  'imageUrl': imageUrl,
                  'category': 'Special Offer',
                  'selectedSize': 'regular',
                  'toppings': <String>[],
                  'isSmartCombo': true,
                  'addedAt': FieldValue.serverTimestamp(),
                });

                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$name added to cart!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: primary,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint(' Failed to add offer to cart: $e');
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Something went wrong: $e',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: primary,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  );
                }
              } finally {
                setSheetState(() => isAdding = false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: sheetBg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFEEEEEE)),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              if (price > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Rs. $price',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: orange,
                                  ),
                                ),
                              ],
                              if (items.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                const Text(
                                  'What\'s included',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: itemCardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: lightMaroonBorder,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < items.length; i++)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: i == items.length - 1
                                                ? 0
                                                : 10,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: primary.withValues(
                                                    alpha: 0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Icon(
                                                  Icons.check_rounded,
                                                  color: primary,
                                                  size: 14,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  items[i],
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.black87,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: itemCardColor,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: lightMaroonBorder,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _qtyBtn(Icons.remove_rounded, () {
                                        FocusScope.of(context).unfocus();
                                        if (quantity > 1) {
                                          setSheetState(() => quantity--);
                                        }
                                      }, enabled: quantity > 1),
                                      SizedBox(
                                        width: 64,
                                        child: _OfferQtyField(
                                          quantity: quantity,
                                          max: maxQty,
                                          onChanged: (value) => setSheetState(
                                            () => quantity = value,
                                          ),
                                        ),
                                      ),
                                      _qtyBtn(
                                        Icons.add_rounded,
                                        () {
                                          FocusScope.of(context).unfocus();
                                          if (quantity < maxQty) {
                                            setSheetState(() => quantity++);
                                          }
                                        },
                                        filled: true,
                                        enabled: quantity < maxQty,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  quantity >= maxQty
                                      ? 'Maximum $maxQty Items Quantity.'
                                      : 'Tap the number to type a custom quantity.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: quantity >= maxQty
                                        ? primary
                                        : Colors.grey[600],
                                    fontWeight: quantity >= maxQty
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                          decoration: const BoxDecoration(
                            color: sheetBg,
                            border: Border(
                              top: BorderSide(color: Color(0xFFEEEEEE)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Total',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    'Rs. ${price * quantity}',
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
                                  height: 48,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: isAdding ? null : addOfferToCart,
                                    child: isAdding
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
                      ],
                    ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _qtyBtn(
    IconData icon,
    VoidCallback onTap, {
    bool filled = false,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: filled
                ? const LinearGradient(
                    colors: [orange, primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: filled ? null : Colors.white,
            shape: BoxShape.circle,
            border: filled
                ? null
                : Border.all(color: primary.withValues(alpha: 0.4)),
          ),
          child: Icon(icon, size: 18, color: filled ? Colors.white : primary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.branchId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('special_offers')
          .where('branchId', isEqualTo: widget.branchId)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 150,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFA70000)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final offers = snapshot.data!.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .where(_isOfferCurrentlyActive)
            .toList();

        if (offers.isEmpty) {
          return const SizedBox.shrink();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startAutoSlide(offers.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Special Offers',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
            SizedBox(
              height: 190,
              child: PageView.builder(
                controller: _controller,
                itemCount: offers.length,
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  final name = (offer['name'] ?? offer['eventName'] ?? 'Offer')
                      .toString();
                  final priceText = _formatPrice(offer['prices']);
                  final imageUrl = offer['imageUrl']?.toString();
                  final words = name.trim().toUpperCase().split(RegExp(r'\s+'));
                  final nameLines = words.length <= 3
                      ? words
                      : [words.first, words.skip(1).join(' ')];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: GestureDetector(
                      onTap: () => _openOfferSheet(offer),
                      child: Container(
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.12),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final imageWidth = constraints.maxWidth * 0.46;
                              return Stack(
                                children: [
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    width: imageWidth,
                                    child:
                                        (imageUrl != null &&
                                            imageUrl.isNotEmpty)
                                        ? Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _placeholderImage(),
                                          )
                                        : _placeholderImage(),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    width: imageWidth,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [primary, Color(0x00A70000)],
                                          stops: [0.0, 0.55],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      18,
                                      14,
                                      imageWidth * 0.75,
                                      14,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              nameLines.join('\n'),
                                              style: const TextStyle(
                                                fontSize: 25,
                                                height: 1.1,
                                                letterSpacing: 0.3,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                              maxLines: nameLines.length,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (priceText.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              Text(
                                                priceText,
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  color: priceColor,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        GestureDetector(
                                          onTap: () => _openOfferSheet(offer),
                                          child: Container(
                                            height: 36,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'View Details',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: primary,
                                                  ),
                                                ),
                                                SizedBox(width: 6),
                                                Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 16,
                                                  color: primary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _placeholderImage() {
    return Container(
      color: Colors.white.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_rounded,
        color: Colors.white70,
        size: 40,
      ),
    );
  }
}

class _OfferQtyField extends StatefulWidget {
  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  const _OfferQtyField({
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_OfferQtyField> createState() => _OfferQtyFieldState();
}

class _OfferQtyFieldState extends State<_OfferQtyField> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.quantity.toString());
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _OfferQtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) {
      _setText(widget.quantity);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _setText(int value) {
    final text = value.toString();
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null || parsed < 1) {
      _setText(widget.quantity);
      return;
    }
    final value = parsed.clamp(1, widget.max).toInt();
    _setText(value);
    if (value != widget.quantity) widget.onChanged(value);
  }

  void _onTyped(String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return;
    if (parsed > widget.max) {
      _setText(widget.max);
      widget.onChanged(widget.max);
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      textAlign: TextAlign.center,
      maxLength: 3,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      cursorColor: _OfferSliderState.primary,
      onTap: () => _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      ),
      onChanged: _onTyped,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _focus.unfocus(),
      style: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
      decoration: const InputDecoration(
        counterText: '',
        border: InputBorder.none,
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}