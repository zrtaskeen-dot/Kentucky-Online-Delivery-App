import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'smart_combo_items_screen.dart';
import '../cart_screen.dart';

class SmartComboCategoriesScreen extends StatefulWidget {
  final String branchId;
  final String chosenPrice;

  const SmartComboCategoriesScreen({
    super.key,
    required this.branchId,
    required this.chosenPrice,
  });

  @override
  State<SmartComboCategoriesScreen> createState() =>
      _SmartComboCategoriesScreenState();
}

class _SmartComboCategoriesScreenState
    extends State<SmartComboCategoriesScreen> {
  // 🌟 FIXED: Combo Bucket ko parent screen par le aaye taake back aane par data clear na ho
  List<Map<String, dynamic>> globalComboBucket = [];

  // 👈 CHANGED: current user ki id nikali taake cart count sirf unke apne
  // items count kare (guest fallback bhi rakha hai taake app crash na ho).
  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFD32F2F),
          image: DecorationImage(
            image: AssetImage("assets/red_texture.png"),
            fit: BoxFit.cover,
            opacity: 0.2,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Categories (${widget.chosenPrice})",
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // 👈 CHANGED: Cart icon ab live item-count badge dikhata
                    // hai aur tap karne par CartScreen khulti hai.
                    _buildCartIconWithBadge(context),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Fetching standard categories
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('menu')
                      .where('branchId', isEqualTo: widget.branchId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "No categories found!",
                          style: TextStyle(color: Colors.white),
                        ),
                      );
                    }

                    Set<String> uniqueCategories = {};
                    Map<String, String> categoryImages = {};

                    for (var doc in snapshot.data!.docs) {
                      var data = doc.data() as Map<String, dynamic>;
                      String cat = (data['category'] ?? '')
                          .toString()
                          .toUpperCase();

                      if (cat != 'COMBO' &&
                          cat != 'SMART COMBO' &&
                          cat != 'DEALS' &&
                          cat.isNotEmpty) {
                        uniqueCategories.add(cat);
                        if (data['imageUrl'] != null &&
                            data['imageUrl'].toString().isNotEmpty) {
                          categoryImages[cat] = data['imageUrl'];
                        }
                      }
                    }

                    List<String> finalCategoriesList = uniqueCategories
                        .toList();

                    if (finalCategoriesList.isEmpty) {
                      return const Center(
                        child: Text(
                          "No standard categories available.",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                      itemCount: finalCategoriesList.length,
                      itemBuilder: (context, index) {
                        final catName = finalCategoriesList[index];
                        final imgUrl = categoryImages[catName] ?? '';
                        bool alignRight = index % 2 == 0;

                        String displayTitle =
                            catName[0] + catName.substring(1).toLowerCase();
                        if (!displayTitle.endsWith('s') &&
                            displayTitle.length < 7) {
                          displayTitle += 's';
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 20),
                          width: double.infinity,
                          child: Row(
                            mainAxisAlignment: alignRight
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      // 🌟 FIXED: Ab hum `globalComboBucket` ko paas kar rahe hain aur wapsi par state refresh kar rahe hain
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SmartComboItemsScreen(
                                            branchId: widget.branchId,
                                            chosenPrice: widget.chosenPrice,
                                            chosenCategory: catName,
                                            sharedComboBucket:
                                                globalComboBucket, // Pass bucket reference
                                          ),
                                        ),
                                      ).then((_) {
                                        // Jab user items screen se back aayega toh categories screen ka state refresh ho jaye
                                        setState(() {});
                                      });
                                    },
                                    child: Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.15),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            spreadRadius: 1,
                                            blurRadius: 10,
                                            offset: const Offset(0, 5),
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: imgUrl.isNotEmpty
                                            ? Image.network(
                                                imgUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    const Icon(
                                                      Icons.fastfood,
                                                      size: 65,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.fastfood,
                                                size: 65,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    displayTitle,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          blurRadius: 4.0,
                                          color: Colors.black45,
                                          offset: Offset(2.0, 2.0),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 👈 NEW: Live Firestore stream se cart items ka count nikal kar
  // shopping cart icon ke upar chhota badge dikhata hai. Tap karne
  // par seedha CartScreen khulti hai.
  Widget _buildCartIconWithBadge(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('carts')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        int itemCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.white,
                size: 28,
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
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$itemCount',
                    style: const TextStyle(
                      color: Color(0xFFD32F2F),
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
