import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_combo_items_screen.dart';
import '../cart_screen.dart';
import '../cart_provider.dart';

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
  List<Map<String, dynamic>> globalComboBucket = [];

  
  final String userId =
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFA70000),
          image: DecorationImage(
            image: AssetImage("assets/red_texture.png"),
            fit: BoxFit.cover,
            opacity: 0.2,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 24,
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
                    
                    _buildCartIconWithBadge(context),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Fetching  categories
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
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SmartComboItemsScreen(
                                            branchId: widget.branchId,
                                            chosenPrice: widget.chosenPrice,
                                            chosenCategory: catName,
                                            sharedComboBucket:
                                                globalComboBucket, 
                                          ),
                                        ),
                                      ).then((_) {
                                        setState(() {});
                                      });
                                    },
                                    child: Container(
                                      width: 160,
                                      height: 160,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.2,
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

  
  Widget _buildCartIconWithBadge(BuildContext context) {
   
    final String activeBranchId = context
        .watch<CartProvider>()
        .selectedBranchId;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('carts')
          .where('userId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
      
        int itemCount = 0;
        if (snapshot.hasData) {
          final counted = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final docBranchId = (data['branchId'] ?? '').toString();
            if (!(docBranchId.isEmpty || docBranchId == activeBranchId)) {
              return false;
            }
            
            final qty = data['quantity'];
            if (qty is num && qty <= 0) return false;
            return true;
          }).toList();
          itemCount = counted.length;

          
        
        }

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
                      color: Color(0xFFA70000),
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
