import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_combo_categories_screen.dart'; // Agli screen ka import
import '../cart_screen.dart';
import '../cart_provider.dart';

class SmartComboPriceScreen extends StatefulWidget {
  final String branchId;
  const SmartComboPriceScreen({super.key, required this.branchId});

  @override
  State<SmartComboPriceScreen> createState() => _SmartComboPriceScreenState();
}

class _SmartComboPriceScreenState extends State<SmartComboPriceScreen> {
  String? selectedPrice;

  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  // ── Theme (matches app's maroon/cream palette) ──
  static const Color primaryRed = Color(0xFFA70000);
  static const Color creamColor = Color(0xFFFFFDFA);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // 👈 CHANGED: gradient/deep red hata kar sirf 0xFFA70000 (categories
        // screen jaisa), texture opacity bhi wohi 0.2.
        decoration: const BoxDecoration(
          color: primaryRed,
          image: DecorationImage(
            image: AssetImage("assets/red_texture.png"),
            fit: BoxFit.cover,
            opacity: 0.2,
          ),
        ),
        child: SafeArea(
          // Poori body SingleChildScrollView mein wrap hai taake neeche wala
          // card apni content ke hisaab se size le sake aur page scroll ho.
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── Header Bar ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 16, 20, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        // 👈 CHANGED: line wala back arrow
                        icon: const Icon(
                          Icons.arrow_back,
                          color: creamColor,
                          size: 24,
                        ),
                        style: IconButton.styleFrom(
                          padding: const EdgeInsets.all(10),
                        ),
                      ),
                      const Text(
                        "Smart Combo",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: creamColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                      _buildCartIconWithBadge(context),
                    ],
                  ),
                ),

                // ── Subtitle / tagline for a more professional feel ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Build your own combo",
                        style: TextStyle(
                          fontSize: 15,
                          color: creamColor.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Pick a budget to see what fits",
                        style: TextStyle(
                          fontSize: 12,
                          color: creamColor.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),

                // ── Selection Card Box ──
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(
                    color: creamColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: primaryRed,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            "Select Your Price",
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // DYNAMIC PRICES FETCHING FROM ALL DEALS/COMBOS
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('menu')
                            .where('branchId', isEqualTo: widget.branchId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: primaryRed,
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData ||
                              snapshot.data!.docs.isEmpty) {
                            return _buildEmptyState("No items available!");
                          }

                          var dealDocs = snapshot.data!.docs.where((doc) {
                            var data = doc.data() as Map<String, dynamic>;
                            String cat = (data['category'] ?? '')
                                .toString()
                                .toUpperCase();
                            return cat == 'COMBO' ||
                                cat == 'SMART COMBO' ||
                                cat == 'DEALS';
                          }).toList();

                          if (dealDocs.isEmpty) {
                            return _buildEmptyState("No Deals active!");
                          }

                          Set<String> uniquePrices = {};
                          for (var doc in dealDocs) {
                            var data = doc.data() as Map<String, dynamic>;
                            if (data['prices'] != null &&
                                data['prices'] is Map) {
                              var priceMap = data['prices'] as Map;
                              for (var value in priceMap.values) {
                                uniquePrices.add("$value PKR");
                              }
                            } else if (data['price'] != null) {
                              uniquePrices.add("${data['price']} PKR");
                            }
                          }

                          List<String> sortedPricesList = uniquePrices.toList();
                          sortedPricesList.sort((a, b) {
                            int numA =
                                int.tryParse(
                                  a.replaceAll(RegExp(r'[^0-9]'), ''),
                                ) ??
                                0;
                            int numB =
                                int.tryParse(
                                  b.replaceAll(RegExp(r'[^0-9]'), ''),
                                ) ??
                                0;
                            return numA.compareTo(numB);
                          });

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sortedPricesList.length,
                            itemBuilder: (context, index) {
                              final priceLabel = sortedPricesList[index];
                              final isSelected = selectedPrice == priceLabel;
                              final isLast =
                                  index == sortedPricesList.length - 1;

                              return IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // ── Timeline icon + connecting line ──
                                    Column(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? primaryRed
                                                : Colors.white,
                                            border: Border.all(
                                              color: isSelected
                                                  ? primaryRed
                                                  : Colors.grey.shade300,
                                              width: 1.4,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.local_offer_rounded,
                                            size: 16,
                                            color: isSelected
                                                ? Colors.white
                                                : primaryRed.withValues(
                                                    alpha: 0.55,
                                                  ),
                                          ),
                                        ),
                                        if (!isLast)
                                          Expanded(
                                            child: Container(
                                              width: 2,
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 14),

                                    // ── Price Card ──
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          bottom: isLast ? 0 : 14,
                                        ),
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              selectedPrice = priceLabel;
                                            });

                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SmartComboCategoriesScreen(
                                                      branchId: widget.branchId,
                                                      chosenPrice: priceLabel,
                                                    ),
                                              ),
                                            );
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                              horizontal: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? primaryRed
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: isSelected
                                                    ? primaryRed
                                                    : Colors.grey.shade200,
                                                width: 1.1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isSelected
                                                      ? primaryRed.withValues(
                                                          alpha: 0.28,
                                                        )
                                                      : Colors.black.withValues(
                                                          alpha: 0.04,
                                                        ),
                                                  blurRadius: isSelected
                                                      ? 10
                                                      : 5,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        priceLabel,
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: isSelected
                                                              ? Colors.white
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        "Tap to build your combo",
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isSelected
                                                              ? Colors.white70
                                                              : Colors
                                                                    .grey
                                                                    .shade500,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  isSelected
                                                      ? Icons
                                                            .check_circle_rounded
                                                      : Icons
                                                            .arrow_forward_ios_rounded,
                                                  size: isSelected ? 20 : 14,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.grey.shade300,
                                                ),
                                              ],
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
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartIconWithBadge(BuildContext context) {
    // 👈 CHANGED: CartScreen wala hi filter — sirf ACTIVE branch ke items.
    final String activeBranchId = context
        .watch<CartProvider>()
        .selectedBranchId;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('carts')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        // Pehle sab docs gine jate the (dusri branch ke bhi), is liye
        // cart khali hone par bhi "1" dikhta tha. Ab CartScreen jaisa
        // filter: branchId khali ho ya active branch ke barabar ho.
        int itemCount = 0;
        if (snapshot.hasData) {
          itemCount = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final docBranchId = (data['branchId'] ?? '').toString();
            return docBranchId.isEmpty || docBranchId == activeBranchId;
          }).length;
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: creamColor,
                size: 26,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                );
              },
            ),
            if (itemCount > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: creamColor,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$itemCount',
                    style: const TextStyle(
                      color: primaryRed,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
