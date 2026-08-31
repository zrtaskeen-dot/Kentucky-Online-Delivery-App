import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // 👈 FCM Token import
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart_provider.dart';
import 'cart_screen.dart';
import 'foodDetailScreen.dart';
import 'pizza_detail.dart';
import 'models/food_item.dart';
import 'package:animation/widgets/offer_slider.dart';
import 'package:animation/smartcombo/smart_combo_price_screen.dart';
import 'feedback.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Orange theme to match the app dashboard
  static const primary = Color(0xFFE65100);
  static const primaryLight = Color(0xFFFFF3E0);
  static const bgColor = Color(0xFFFEF9E7); // warm cream
  static const cardWhite = Color(0xFFFFFFF0);

  int selectedCategoryIndex = 0;
  List<FoodItem> allItems = [];
  List<FoodItem> searchResults = [];
  bool isLoadingItems = false;
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  List<DocumentSnapshot> branchesList = [];
  String? selectedBranchId;
  String selectedBranchAddress = 'Loading...';
  bool isLoadingBranches = true;

  String userName = 'there';

  // ---- state for pending feedback popup ----
  bool _isFeedbackDialogShown = false;
  StreamSubscription<QuerySnapshot>? _pendingFeedbackSub;
  StreamSubscription<DocumentSnapshot>? _userDocSub;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  final List<String> categories = [
    "ALL",
    "PIZZA",
    "BURGER",
    "WINGS",
    "FRIES",
    "SOFT DRINKS",
    "Sandwiches & PASTA",
    "PARATHA ROLL",
    "DEALS",
    "COMBO",
    "SMART COMBO",
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
    _listenForUserName();
    _listenForPendingFeedback();
    _searchController.addListener(_onSearchChanged);
    _generateAndSaveFcmToken(); // 👈 App kholte hi FCM Token save karne ke liye
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _pendingFeedbackSub?.cancel();
    _userDocSub?.cancel();
    super.dispose();
  }

  // ---- FCM Token Generation & Save Function ----
  Future<void> _generateAndSaveFcmToken() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        String? userId = FirebaseAuth.instance.currentUser?.uid;

        if (token != null && userId != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .set({'fcmToken': token}, SetOptions(merge: true));

          debugPrint("✅ Customer FCM Token Saved Successfully: $token");
        }
      }
    } catch (e) {
      debugPrint("❌ FCM Token Error: $e");
    }
  }

  // ---- Checks for any delivered order with feedback pending ----
  void _listenForPendingFeedback() {
    _pendingFeedbackSub = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: _currentUserId)
        .where('order_status', isEqualTo: 'Delivered')
        .where('isFeedbackSubmitted', isEqualTo: false)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;
          if (snapshot.docs.isNotEmpty && !_isFeedbackDialogShown) {
            _isFeedbackDialogShown = true;
            final orderId = snapshot.docs.first.id;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => OrderFeedbackDialog(orderId: orderId),
            ).then((_) {
              if (mounted) {
                setState(() => _isFeedbackDialogShown = false);
              }
            });
          }
        });
  }

  // ---- Search now matches ONLY the item name ----
  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      isSearching = query.isNotEmpty;
      if (isSearching) {
        searchResults = allItems
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
      } else {
        searchResults = [];
      }
    });
  }

  Future<void> _initializeData() async {
    await _fetchBranches();
  }

  String _normalizeCategory(String raw) {
    return raw.toUpperCase().trim().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  bool _categoryMatches(String itemCategory, String tabCategory) {
    final a = _normalizeCategory(itemCategory);
    final b = _normalizeCategory(tabCategory);
    if (a == b) return true;

    if (a.endsWith('S') && a.substring(0, a.length - 1) == b) return true;
    if (b.endsWith('S') && b.substring(0, b.length - 1) == a) return true;

    if (a.contains(b) || b.contains(a)) return true;

    return false;
  }

  void _listenForUserName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
          if (!mounted) return;
          if (doc.exists && doc.data() != null) {
            final data = doc.data() as Map<String, dynamic>;
            final name =
                (data['name'] ?? data['fullName'] ?? data['full_name'] ?? '')
                    .toString()
                    .trim();

            if (name.isNotEmpty) {
              setState(() => userName = name.split(' ').first.toUpperCase());
            }
          }
        }, onError: (e) {
          debugPrint('userName stream error: $e');
        });
  }

  Future<void> _fetchBranches() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('restaurant_info')
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          selectedBranchAddress = 'No branches available';
          isLoadingBranches = false;
        });
        return;
      }

      branchesList = snapshot.docs;
      String finalBranchId = snapshot.docs.first.id;

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          final savedId = data['branchId']?.toString() ?? '';

          if (savedId.isNotEmpty &&
              branchesList.any((doc) => doc.id == savedId)) {
            finalBranchId = savedId;
          }
        }
      }

      final activeBranch = branchesList.firstWhere(
        (d) => d.id == finalBranchId,
      );
      final branchData = activeBranch.data() as Map<String, dynamic>;

      setState(() {
        selectedBranchId = finalBranchId;
        selectedBranchAddress =
            branchData['phone'] ?? branchData['address'] ?? 'No address';
        isLoadingBranches = false;
      });

      if (mounted) {
        Provider.of<CartProvider>(
          context,
          listen: false,
        ).setBranchId(finalBranchId);
      }

      await _fetchMenuItems(finalBranchId);
    } catch (e) {
      debugPrint('fetchBranches error: $e');
      setState(() {
        selectedBranchAddress = 'Error loading branches';
        isLoadingBranches = false;
      });
    }
  }

  Future<void> _fetchMenuItems(String branchId) async {
    setState(() => isLoadingItems = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('menu')
          .where('branchId', isEqualTo: branchId)
          .get();

      setState(() {
        allItems = snapshot.docs.map((d) => FoodItem.fromFirestore(d)).toList();
        isLoadingItems = false;
      });
    } catch (e) {
      debugPrint('fetchMenuItems error: $e');
      setState(() => isLoadingItems = false);
    }
  }

  Future<void> _handleBranchChange(String newId) async {
    if (newId == selectedBranchId) return;

    final doc = branchesList.firstWhere((d) => d.id == newId);
    final data = doc.data() as Map<String, dynamic>;

    setState(() {
      selectedBranchId = newId;
      selectedBranchAddress = data['phone'] ?? data['address'] ?? 'No address';
      _searchController.clear();
    });

    if (mounted) {
      Provider.of<CartProvider>(context, listen: false).setBranchId(newId);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'branchId': newId,
      }, SetOptions(merge: true));
    }

    await _fetchMenuItems(newId);
  }

  void _showThemedMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<FoodItem> displayItems;

    if (isSearching) {
      displayItems = searchResults;
    } else if (selectedCategoryIndex == 0) {
      displayItems = allItems;
    } else {
      final catName = categories[selectedCategoryIndex];
      displayItems = allItems
          .where((i) => _categoryMatches(i.category, catName))
          .toList();
    }

    final safeDropdownValue = branchesList.any((d) => d.id == selectedBranchId)
        ? selectedBranchId
        : null;

    return Scaffold(
      backgroundColor: bgColor,
      body: isLoadingBranches
          ? const Center(child: CircularProgressIndicator(color: primary))
          : SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(safeDropdownValue)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: _buildSearchBar(),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildCategories()),
                  if (!isSearching)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: OfferSlider(branchId: selectedBranchId ?? ''),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: _sectionTitle(
                        isSearching
                            ? 'Results for "${_searchController.text}"'
                            : selectedCategoryIndex == 0
                            ? 'Our Menu'
                            : categories[selectedCategoryIndex],
                      ),
                    ),
                  ),
                  if (isLoadingItems)
                    const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: primary),
                        ),
                      ),
                    )
                  else if (displayItems.isEmpty)
                    SliverToBoxAdapter(child: _buildEmptyState())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildFoodCard(displayItems[index]),
                          childCount: displayItems.length,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.78,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(String? safeDropdownValue) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(color: bgColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildBranchDropdown(safeDropdownValue)),
              const SizedBox(width: 10),
              _buildCartIcon(),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 16),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Hello, ',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[700],
                  ),
                ),
                TextSpan(
                  text: userName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "What are you craving today?",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildBranchDropdown(String? safeDropdownValue) {
    if (branchesList.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.06),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: safeDropdownValue,
                isExpanded: true,
                itemHeight: 64,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: primary,
                ),
                onChanged: (id) {
                  if (id != null) _handleBranchChange(id);
                },
                selectedItemBuilder: (context) {
                  return branchesList.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (data['branchName'] ?? 'Branch')
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selectedBranchAddress,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  }).toList();
                },
                items: branchesList.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          color: primary,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (data['branchName'] ?? 'Branch')
                                .toString()
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartIcon() {
    Query<Map<String, dynamic>> cartQuery = FirebaseFirestore.instance
        .collection('carts')
        .where('userId', isEqualTo: _currentUserId);
    if (selectedBranchId != null && selectedBranchId!.isNotEmpty) {
      cartQuery = cartQuery.where('branchId', isEqualTo: selectedBranchId);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: cartQuery.snapshots(),
      builder: (context, snapshot) {
        int liveCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.06),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.shopping_cart_rounded,
                  color: primary,
                  size: 26,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CartScreen()),
                ),
              ),
              if (liveCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '$liveCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.07),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: primary,
            size: 24,
          ),
          suffixIcon: isSearching
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    FocusScope.of(context).unfocus();
                  },
                )
              : null,
          hintText: 'Search burgers, pizza, deals...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final isSelected = selectedCategoryIndex == index && !isSearching;
          final name = categories[index];

          return GestureDetector(
            onTap: () {
              if (name.toUpperCase() == 'SMART COMBO') {
                if (selectedBranchId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SmartComboPriceScreen(branchId: selectedBranchId!),
                    ),
                  );
                } else {
                  _showThemedMessage('Please select a branch first!');
                }
              } else {
                setState(() {
                  selectedCategoryIndex = index;
                  _searchController.clear();
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? primary : Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: primary.withAlpha(80),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        const BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.06),
                          blurRadius: 6,
                        ),
                      ],
              ),
              alignment: Alignment.center,
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFoodCard(FoodItem item) {
    return GestureDetector(
      onTap: () {
        if (item.category.toUpperCase() == 'PIZZA') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PizzaDetailScreen(
                item: item,
                selectedBranchId: selectedBranchId ?? '',
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FoodDetailScreen(
                item: item,
                selectedBranchId: selectedBranchId ?? '',
              ),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.06),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: item.imageUrl.isEmpty
                    ? Container(
                        color: primaryLight,
                        child: const Icon(
                          Icons.fastfood_rounded,
                          size: 50,
                          color: primary,
                        ),
                      )
                    : Image.network(
                        item.imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: primaryLight,
                          child: const Icon(
                            Icons.fastfood_rounded,
                            size: 50,
                            color: primary,
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.description,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _formatPrice(item),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: primary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPrice(FoodItem item) {
    try {
      if (item.prices.isNotEmpty) {
        final firstVal =
            item.prices['small'] ??
            item.prices['Small'] ??
            item.prices.values.first;

        final parsed = num.tryParse(firstVal.toString()) ?? 0;
        return 'From Rs. ${parsed.round()}';
      }

      final dynamic rawPrice = (item as dynamic).price;

      if (rawPrice != null) {
        if (rawPrice is num) {
          return 'Rs. ${rawPrice.round()}';
        }
        final parsed = num.tryParse(rawPrice.toString());
        if (parsed != null) {
          return 'Rs. ${parsed.round()}';
        }
      }
    } catch (e) {
      debugPrint('Price formatting error: $e');
    }

    return 'Rs. 0';
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 48, color: primary.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              isSearching ? 'No results found' : 'No items in this category',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 15,
              ),
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Try a different search term',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}