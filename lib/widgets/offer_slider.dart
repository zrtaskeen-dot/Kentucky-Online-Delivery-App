import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
  static const accent = Color(0xFFFCF800);
  static const creamBg = Color(0xFFFEF9E7); // matches app's cream theme

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

  // Resolves prices (either a Map like {"simple": 1500} or a plain number) to an int
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

  // Counts numbered points like "1. ... 2. ... 3. ..." inside the description
  int _countItems(String description) {
    if (description.isEmpty) return 0;
    final matches = RegExp(r'\d+\.').allMatches(description);
    return matches.isEmpty ? 0 : matches.length;
  }

  // Splits "1. Item one 2. Item two 3. Item three" into ["Item one", "Item two", "Item three"]
  List<String> _splitItems(String description) {
    if (description.isEmpty) return [];
    final parts = description.split(RegExp(r'\d+\.\s*'));
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  // ── Bottom sheet: offer details + order ─────────────────────────
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ Failed to add offer to cart: $e');
                if (sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    SnackBar(
                      content: Text('Something went wrong: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } finally {
                setSheetState(() => isAdding = false);
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: creamBg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
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
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  imageUrl,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                            const SizedBox(height: 16),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
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
                                  color: primary,
                                ),
                              ),
                            ],
                            if (items.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              const Text(
                                'What\'s included',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...items.map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: primary,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          line,
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
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _qtyBtn('-', () {
                                  if (quantity > 1) {
                                    setSheetState(() => quantity--);
                                  }
                                }),
                                Container(
                                  width: 48,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    border: Border.symmetric(
                                      horizontal: BorderSide(
                                        color: primary.withOpacity(0.4),
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '$quantity',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                _qtyBtn(
                                  '+',
                                  () => setSheetState(() => quantity++),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        decoration: const BoxDecoration(
                          color: creamBg,
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.08),
                              blurRadius: 10,
                              offset: Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 3,
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
                                : Text(
                                    'ADD TO CART • Rs. ${price * quantity}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _qtyBtn(String label, VoidCallback onTap) {
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
              height: 150,
              child: PageView.builder(
                controller: _controller,
                itemCount: offers.length,
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  final name = (offer['name'] ?? offer['eventName'] ?? 'Offer')
                      .toString();
                  final description = (offer['description'] ?? '').toString();
                  final priceText = _formatPrice(offer['prices']);
                  final imageUrl = offer['imageUrl']?.toString();
                  final itemCount = _countItems(description);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: GestureDetector(
                      onTap: () => _openOfferSheet(offer),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(3, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // LEFT SIDE: Title -> Item count -> Price
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        color: Color(0xFFFCF8dd),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (itemCount > 0)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.checklist_rounded,
                                            color: Colors.white70,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$itemCount Items Included',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (priceText.isNotEmpty)
                                      Text(
                                        priceText,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: accent,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // RIGHT SIDE: Image (placeholder for now)
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child:
                                      (imageUrl != null && imageUrl.isNotEmpty)
                                      ? Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _placeholderImage(),
                                        )
                                      : _placeholderImage(),
                                ),
                              ),
                            ),
                          ],
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
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_rounded,
        color: Colors.white70,
        size: 36,
      ),
    );
  }
}
