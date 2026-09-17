import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'home_screen.dart';
import 'order_history.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 👈 Unified brand palette: maroon + orange + white/cream
  static const Color _maroon = Color(0xFFA70000);
  static const Color _maroonDark = Color(0xFF7A0000);
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _cream = Color(0xFFFFFDF2);

  // 👈 CHANGED: Track tab (SizedBox) hata diya gaya hai, ab sirf 4 screens hain
  final List<Widget> _screens = [
    const HomeScreen(),
    OrderHistoryScreen(),
    const NotificationScreen(),
    const ProfileScreen(),
  ];

  // Selected icon design — orange circle with a soft glow, white icon on top
  // so it pops against the maroon bar.
  Widget selectedIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _orange,
        shape: BoxShape.circle,
        border: Border.all(color: _cream, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _orange.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 21),
    );
  }

  // Normal icon design — soft cream so it stays readable on the maroon bar
  Widget unselectedIcon(IconData icon) {
    return Icon(icon, color: _cream.withOpacity(0.75), size: 22);
  }

  // Notification icon (selected or not) with an unread-count badge.
  // Counts BOTH this user's own notifications and store-wide 'ALL'
  // broadcasts — matching the same query NotificationScreen uses, so the
  // badge number always matches what the user sees when they open it.
  Widget _notificationIconWithBadge({
    required bool selected,
    required String? currentUserId,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: currentUserId == null
          ? null
          : FirebaseFirestore.instance
                .collection('notifications')
                .where('userId', whereIn: [currentUserId, 'ALL'])
                .where('isRead', isEqualTo: false)
                .snapshots(),

      builder: (context, snapshot) {
        int unreadCount = 0;

        if (snapshot.hasData) {
          // The query above only filters by userId + isRead — it doesn't
          // know about per-user "deleted" notifications. Deleting a
          // notification just adds the uid to that doc's `hiddenFor`
          // array (see NotificationService.hideNotificationForUser), so
          // without this filter, a deleted-but-unread notification kept
          // counting toward the badge even after it disappeared from the
          // list — matching the same client-side filter NotificationScreen
          // uses.
          unreadCount = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final hiddenFor = List<String>.from(data['hiddenFor'] ?? const []);
            return !hiddenFor.contains(currentUserId);
          }).length;
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            selected
                ? selectedIcon(Icons.notifications)
                : unselectedIcon(Icons.notifications),

            if (unreadCount > 0)
              Positioned(
                right: selected ? -2 : -5,
                top: selected ? -2 : -5,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: _cream, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 14,
                    minHeight: 14,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
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

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF2),

      body: IndexedStack(index: _currentIndex, children: _screens),

      // Bottom Navigation Bar — plain rectangle, flush with the screen
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_maroon, _maroonDark],
          ),
          boxShadow: [
            BoxShadow(
              color: _maroon.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: BottomNavigationBar(
              currentIndex: _currentIndex,

              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },

              type: BottomNavigationBarType.fixed,

              backgroundColor: Colors.transparent,
              elevation: 0,

              selectedItemColor: _orange,
              unselectedItemColor: _cream.withOpacity(0.75),

              showSelectedLabels: false,
              showUnselectedLabels: false,

              selectedFontSize: 0,
              unselectedFontSize: 0,

              items: [
                // 1. HOME
                BottomNavigationBarItem(
                  icon: unselectedIcon(Icons.home),
                  activeIcon: selectedIcon(Icons.home),
                  label: 'Home',
                ),

                // 2. MY ORDERS
                BottomNavigationBarItem(
                  icon: unselectedIcon(Icons.shopping_bag),
                  activeIcon: selectedIcon(Icons.shopping_bag),
                  label: 'My Orders',
                ),

                // 3. NOTIFICATIONS
                BottomNavigationBarItem(
                  icon: _notificationIconWithBadge(
                    selected: false,
                    currentUserId: currentUser?.uid,
                  ),
                  activeIcon: _notificationIconWithBadge(
                    selected: true,
                    currentUserId: currentUser?.uid,
                  ),
                  label: 'Alerts',
                ),

                // 4. PROFILE
                BottomNavigationBarItem(
                  icon: unselectedIcon(Icons.person),
                  activeIcon: selectedIcon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ), // closes BottomNavigationBar(
          ), // closes SizedBox(
        ), // closes SafeArea(
      ), // closes Container(
    ); // closes Scaffold( + ends return statement
  }
}
