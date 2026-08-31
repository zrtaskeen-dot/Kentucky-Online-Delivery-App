import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SmartComboItemsScreen extends StatefulWidget {
  final String branchId;
  final String chosenPrice;
  final String chosenCategory;
  final List<Map<String, dynamic>> sharedComboBucket;

  const SmartComboItemsScreen({
    super.key,
    required this.branchId,
    required this.chosenPrice,
    required this.chosenCategory,
    required this.sharedComboBucket,
  });

  @override
  State<SmartComboItemsScreen> createState() => _SmartComboItemsScreenState();
}

class _SmartComboItemsScreenState extends State<SmartComboItemsScreen> {
  // ── Theme Colors (Maroon — matches app) ─────────────────────────
  static const Color primary = Color(0xFFB12C00);
  static const Color bgColor = Color(0xFFFFFDF3);
  static const Color lightMaroon = Color(0xFFFFF3F1);

  double dealDiscountPercentage = 0.0;
  bool isLoadingDiscount = true;
  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  @override
  void initState() {
    super.initState();
    _calculateDealDiscount();
  }

  // 👈 CHANGED: theme-based SnackBar helper — replaces green/orange default
  // Material colors with app's primary maroon, keeps messages emoji-free.
  void _showThemedSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Database ke 'prices' map se correct price nikalne ka helper function
  int _getPriceFromMap(
    Map<String, dynamic>? pricesMap,
    dynamic fallbackRawPrice,
  ) {
    if (pricesMap != null && pricesMap.isNotEmpty) {
      var targetPrice =
          pricesMap['simple'] ??
          pricesMap['small'] ??
          pricesMap['medium'] ??
          pricesMap['large'] ??
          pricesMap.values.first;
      return int.tryParse(targetPrice.toString()) ?? 0;
    }
    return int.tryParse(fallbackRawPrice.toString()) ?? 0;
  }

  // Description se item aur uski original price match karne ka logic
  int calculateDynamicItemPrice(
    Map<String, dynamic> menuItemData,
    String cleanMatchedText,
  ) {
    String itemName = (menuItemData['name'] ?? '').toString().toLowerCase();
    Map<String, dynamic>? pricesMap = menuItemData['prices'] != null
        ? Map<String, dynamic>.from(menuItemData['prices'])
        : null;

    int fallbackPrice = _getPriceFromMap(pricesMap, menuItemData['price']);

    if (itemName.contains('wing') ||
        itemName.contains('piece') ||
        itemName.contains('pc')) {
      try {
        RegExp dealPcsRegex = RegExp(
          r'(\d+)\s*(?:pcs|pc|pieces|piece)',
          caseSensitive: false,
        );
        var dealMatch = dealPcsRegex.firstMatch(cleanMatchedText);

        RegExp menuPcsRegex = RegExp(
          r'(\d+)\s*(?:pcs|pc|pieces|piece)',
          caseSensitive: false,
        );
        var menuMatch = menuPcsRegex.firstMatch(menuItemData['name'] ?? '');

        if (dealMatch != null) {
          int requiredPiecesInDeal = int.parse(dealMatch.group(1)!);
          int totalPiecesInMenuPackage = 6;

          if (menuMatch != null) {
            totalPiecesInMenuPackage = int.parse(menuMatch.group(1)!);
          }

          double pricePerSinglePiece = fallbackPrice / totalPiecesInMenuPackage;
          return (pricePerSinglePiece * requiredPiecesInDeal).round();
        }
      } catch (e) {
        print("Parsing error: $e");
      }
    }

    if (itemName.contains('string') ||
        itemName.contains('drink') ||
        itemName.contains('cola') ||
        itemName.contains('sprite')) {
      if (pricesMap != null) {
        if (cleanMatchedText.toLowerCase().contains('1.5l') &&
            pricesMap['1.5l'] != null) {
          return int.tryParse(pricesMap['1.5l'].toString()) ?? fallbackPrice;
        } else if (cleanMatchedText.toLowerCase().contains('1l') &&
            pricesMap['1l'] != null) {
          return int.tryParse(pricesMap['1l'].toString()) ?? fallbackPrice;
        }
      }
    }

    return fallbackPrice;
  }

  Future<void> _calculateDealDiscount() async {
    try {
      String cleanPriceStr = widget.chosenPrice
          .replaceAll(RegExp(r'[^0-9]'), '')
          .trim();
      int dealTargetPrice = int.tryParse(cleanPriceStr) ?? 0;

      var menuSnapshot = await FirebaseFirestore.instance
          .collection('menu')
          .where('branchId', isEqualTo: widget.branchId)
          .get();

      DocumentSnapshot? matchedDealDoc;

      for (var doc in menuSnapshot.docs) {
        var data = doc.data();
        Map<String, dynamic>? pricesMap = data['prices'] != null
            ? Map<String, dynamic>.from(data['prices'])
            : null;
        int itemActualPrice = _getPriceFromMap(pricesMap, data['price']);

        if (itemActualPrice == dealTargetPrice) {
          matchedDealDoc = doc;
          break;
        }
      }

      if (matchedDealDoc != null) {
        var dealData = matchedDealDoc.data() as Map<String, dynamic>;
        String fullDescription = dealData['description'] ?? '';

        RegExp itemSplitterRegex = RegExp(
          r'(?:\d+\.\s*)(.*?)(?=\s*\d+\.\s*|$)',
        );
        Iterable<Match> matches = itemSplitterRegex.allMatches(fullDescription);

        List<String> extractedDealItems = [];
        for (var match in matches) {
          String itemText = match.group(1)!.trim();
          if (itemText.isNotEmpty) {
            extractedDealItems.add(itemText);
          }
        }

        int totalCalculatedOriginalOfDeal = 0;

        for (String textLine in extractedDealItems) {
          String cleanTextLine = textLine.toLowerCase();

          var matchDoc = menuSnapshot.docs.where((doc) {
            String mName = (doc.data()['name'] ?? '').toString().toLowerCase();
            return cleanTextLine.contains(mName) ||
                mName.contains(cleanTextLine.split('(')[0].trim());
          });

          if (matchDoc.isNotEmpty) {
            var menuItemData = matchDoc.first.data();
            int singleItemCost = calculateDynamicItemPrice(
              menuItemData,
              textLine,
            );
            totalCalculatedOriginalOfDeal += singleItemCost;
          }
        }

        if (totalCalculatedOriginalOfDeal > dealTargetPrice) {
          double calcDiscount =
              ((totalCalculatedOriginalOfDeal - dealTargetPrice) /
                  totalCalculatedOriginalOfDeal) *
              100;
          setState(() {
            dealDiscountPercentage = calcDiscount;
          });
        }
      }
    } catch (e) {
      print("Error in parsing description text block from menu: $e");
    } finally {
      if (mounted) setState(() => isLoadingDiscount = false);
    }
  }

  int get customComboOriginalTotal => widget.sharedComboBucket.fold(
    0,
    (sum, item) => sum + (item['selectedPrice'] as int),
  );

  int get customComboFinalPrice {
    double discountAmount =
        customComboOriginalTotal * (dealDiscountPercentage / 100);
    return (customComboOriginalTotal - discountAmount).round();
  }

  int calculateHypotheticalFinalPrice(int newItemPrice) {
    int projectedOriginalTotal = customComboOriginalTotal + newItemPrice;
    double discountAmount =
        projectedOriginalTotal * (dealDiscountPercentage / 100);
    return (projectedOriginalTotal - discountAmount).round();
  }

  @override
  Widget build(BuildContext context) {
    final int maxBudget =
        int.tryParse(widget.chosenPrice.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (isLoadingDiscount) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: primary)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 0,
        title: Text(
          "${widget.chosenCategory} Under $maxBudget PKR",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      bottomNavigationBar: widget.sharedComboBucket.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
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
              child: SafeArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 👈 CHANGED: FittedBox use kiya taake price kabhi
                          // ellipsis se cut na ho — pura number hamesha
                          // dikhega, sirf zaroorat par thoda shrink hoga.
                          // OFF badge bhi wapis green kar diya.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Text(
                                  "Original: Rs. $customComboOriginalTotal",
                                  style: const TextStyle(
                                    decoration: TextDecoration.lineThrough,
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                if (dealDiscountPercentage > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "${dealDiscountPercentage.round()}% OFF",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 👈 CHANGED: Final price bhi FittedBox mein —
                          // full price hamesha visible rahega, ellipsis se
                          // cut nahi hoga.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                Text(
                                  "Rs. $customComboFinalPrice",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: primary,
                                  ),
                                ),
                                if (customComboOriginalTotal >
                                    customComboFinalPrice) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    "(-Rs. ${customComboOriginalTotal - customComboFinalPrice})",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Limit: Rs. $maxBudget",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                        onPressed: () async {
                          if (widget.sharedComboBucket.isEmpty) return;
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(
                              child: CircularProgressIndicator(color: primary),
                            ),
                          );
                          try {
                            String dynamicTitle = widget.sharedComboBucket
                                .map((item) => item['name'])
                                .join(' + ');
                            dynamicTitle = dynamicTitle.length > 35
                                ? "Custom Smart Combo Bundle"
                                : "$dynamicTitle Combo";
                            String dynamicImage =
                                widget.sharedComboBucket.first['imageUrl'] ??
                                '';

                            await FirebaseFirestore.instance
                                .collection('carts')
                                .add({
                                  'userId': userId,
                                  'branchId': widget.branchId,
                                  'name': dynamicTitle,
                                  'price': customComboFinalPrice,
                                  'quantity': 1,
                                  'imageUrl': dynamicImage,
                                  'comboItems': widget.sharedComboBucket,
                                  'isSmartCombo': true,
                                  'addedAt': DateTime.now().toIso8601String(),
                                });

                            if (mounted) Navigator.pop(context);
                            setState(() => widget.sharedComboBucket.clear());
                            if (mounted) Navigator.pop(context);
                            // 👈 CHANGED: message ab English mein hai
                            _showThemedSnack("Added to cart successfully.");
                          } catch (e) {
                            if (mounted) Navigator.pop(context);
                            print("Error saving item: $e");
                          }
                        },
                        child: const Text(
                          "CONFIRM COMBO",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('menu')
            .where('branchId', isEqualTo: widget.branchId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primary),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                "No items available in this branch.",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          final String targetCategory = widget.chosenCategory
              .toUpperCase()
              .trim();
          var allItems = snapshot.data!.docs;

          var filteredItems = allItems.where((doc) {
            var data = doc.data() as Map<String, dynamic>;
            String itemCategory = (data['category'] ?? '')
                .toString()
                .toUpperCase()
                .trim();
            if (itemCategory != targetCategory) return false;

            Map<String, dynamic>? pricesMap = data['prices'] != null
                ? Map<String, dynamic>.from(data['prices'])
                : null;
            int minimumPriceOfItem = _getPriceFromMap(pricesMap, data['price']);

            if (pricesMap != null && pricesMap.isNotEmpty) {
              minimumPriceOfItem = pricesMap.values
                  .map((v) => int.tryParse(v.toString()) ?? 99999)
                  .reduce((min, val) => val < min ? val : min);
            }

            return minimumPriceOfItem <= maxBudget;
          }).toList();

          if (filteredItems.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.money_off_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    // 👈 CHANGED: emoji hataya
                    "No items available under Rs. $maxBudget",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Please try a higher budget bracket.",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              var doc = filteredItems[index];
              var data = doc.data() as Map<String, dynamic>;
              String itemName = data['name'] ?? 'Item';
              String imgUrl = data['imageUrl'] ?? data['image'] ?? '';

              Map<String, dynamic>? pricesMap = data['prices'] != null
                  ? Map<String, dynamic>.from(data['prices'])
                  : null;
              int displayedPrice = _getPriceFromMap(pricesMap, data['price']);

              // ── Modern card layout (image-left, matches FoodDetailScreen style) ──
              return GestureDetector(
                onTap: () => _openItemSheet(
                  context: context,
                  itemName: itemName,
                  imgUrl: imgUrl,
                  description:
                      data['description'] ?? 'No description available.',
                  category: (data['category'] ?? '')
                      .toString()
                      .toUpperCase()
                      .trim(),
                  pricesMap: pricesMap ?? {},
                  displayedPrice: displayedPrice,
                  maxBudget: maxBudget,
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primary.withOpacity(0.12)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imgUrl.isNotEmpty
                            ? Image.network(
                                imgUrl,
                                width: 70,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 70,
                                  height: 70,
                                  color: lightMaroon,
                                  child: const Icon(
                                    Icons.fastfood,
                                    color: primary,
                                  ),
                                ),
                              )
                            : Container(
                                width: 70,
                                height: 70,
                                color: lightMaroon,
                                child: const Icon(
                                  Icons.fastfood,
                                  color: primary,
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
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              pricesMap != null
                                  ? "Starting from Rs. $displayedPrice"
                                  : "Rs. $displayedPrice",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          int projectedFinalPrice =
                              calculateHypotheticalFinalPrice(displayedPrice);
                          if (projectedFinalPrice > maxBudget) {
                            // 👈 CHANGED: emoji hataya, theme color use kiya
                            _showThemedSnack(
                              "This exceeds your selected budget.",
                            );
                          } else {
                            setState(() {
                              widget.sharedComboBucket.add({
                                'name': itemName,
                                'imageUrl': imgUrl,
                                'selectedPrice': displayedPrice,
                              });
                            });
                          }
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Bottom sheet, restyled to match FoodDetailScreen / PizzaDetailScreen ──
  void _openItemSheet({
    required BuildContext context,
    required String itemName,
    required String imgUrl,
    required String description,
    required String category,
    required Map<String, dynamic> pricesMap,
    required int displayedPrice,
    required int maxBudget,
  }) {
    String selectedSize = pricesMap.isNotEmpty ? pricesMap.keys.first : '';
    int currentPrice = displayedPrice;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setPopupState) {
            if (category == 'PIZZA' &&
                selectedSize.isNotEmpty &&
                pricesMap.containsKey(selectedSize)) {
              currentPrice =
                  int.tryParse(pricesMap[selectedSize].toString()) ??
                  displayedPrice;
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Image + Name (matches detail screen header style) ──
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: imgUrl.isNotEmpty
                                ? Image.network(
                                    imgUrl,
                                    width: 85,
                                    height: 85,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => Container(
                                      width: 85,
                                      height: 85,
                                      color: lightMaroon,
                                      child: const Icon(
                                        Icons.fastfood,
                                        size: 36,
                                        color: primary,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 85,
                                    height: 85,
                                    color: lightMaroon,
                                    child: const Icon(
                                      Icons.fastfood,
                                      size: 36,
                                      color: primary,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Rs. $currentPrice",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ── Description card ──
                      _sheetCard(
                        title: 'Ingredients',
                        child: Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Size selector (pizza only) ──
                      if (category == 'PIZZA' && pricesMap.isNotEmpty) ...[
                        _sheetCard(
                          title: 'Select Size',
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: pricesMap.keys.map((size) {
                              bool isSelected = selectedSize == size;
                              return GestureDetector(
                                onTap: () {
                                  setPopupState(() => selectedSize = size);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected ? primary : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? primary
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        size.toUpperCase(),
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
                                        'Rs. ${pricesMap[size]}',
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white70
                                              : Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // ── Add to Combo button (bottom sticky style) ──
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 3,
                          ),
                          icon: const Icon(Icons.add, color: Colors.white),
                          label: const Text(
                            "ADD TO COMBO",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                          onPressed: () {
                            int projectedFinalPrice =
                                calculateHypotheticalFinalPrice(currentPrice);
                            if (projectedFinalPrice > maxBudget) {
                              Navigator.pop(context);
                              // 👈 CHANGED: emoji hataya, theme color use kiya
                              _showThemedSnack(
                                "This exceeds your selected budget.",
                              );
                            } else {
                              setState(() {
                                widget.sharedComboBucket.add({
                                  'name': category == 'PIZZA'
                                      ? "$itemName ($selectedSize)"
                                      : itemName,
                                  'imageUrl': imgUrl,
                                  'selectedPrice': currentPrice,
                                  'size': selectedSize,
                                });
                              });
                              Navigator.pop(context);
                              // 👈 CHANGED: emoji hataya, theme color use kiya
                              _showThemedSnack(
                                category == 'PIZZA'
                                    ? "$itemName ($selectedSize) added to your combo."
                                    : "$itemName added to your combo.",
                              );
                            }
                          },
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

  // ── Small helper: consistent card style inside bottom sheet ──
  Widget _sheetCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}