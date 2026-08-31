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

  // 👈 CHANGED: Track tab (SizedBox) hata diya gaya hai, ab sirf 4 screens hain
  final List<Widget> _screens = [
    const HomeScreen(),
     OrderHistoryScreen(),
    const NotificationScreen(),
    const ProfileScreen(),
  ];

  // Selected icon design
  Widget selectedIcon(IconData icon) {
    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFFFF8A00), // Orange circle
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: const Color(0xFFA62600), size: 27),
    );
  }

  // Normal icon design
  Widget unselectedIcon(IconData icon) {
    return Icon(icon, color: const Color(0xFFA62600), size: 27);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF2),

      body: IndexedStack(index: _currentIndex, children: _screens),

      // Floating Bottom Navigation Bar
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 88,
          margin: const EdgeInsets.only(left: 24, right: 24, bottom: 18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFEF5),
            borderRadius: BorderRadius.circular(40),

            // Soft shadow
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 15,
                spreadRadius: 1,
                offset: const Offset(0, 5),
              ),
            ],
          ),

          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),

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

              selectedItemColor: const Color(0xFFA62600),
              unselectedItemColor: const Color(0xFFA62600),

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
                  icon: StreamBuilder<QuerySnapshot>(
                    stream: currentUser == null
                        ? null
                        : FirebaseFirestore.instance
                              .collection('notifications')
                              .where('userId', isEqualTo: currentUser.uid)
                              .where('isRead', isEqualTo: false)
                              .snapshots(),

                    builder: (context, snapshot) {
                      int unreadCount = 0;

                      if (snapshot.hasData) {
                        unreadCount = snapshot.data!.docs.length;
                      }

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          unselectedIcon(Icons.notifications),

                          if (unreadCount > 0)
                            Positioned(
                              right: -5,
                              top: -5,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 15,
                                  minHeight: 15,
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
                  ),

                  activeIcon: StreamBuilder<QuerySnapshot>(
                    stream: currentUser == null
                        ? null
                        : FirebaseFirestore.instance
                              .collection('notifications')
                              .where('userId', isEqualTo: currentUser.uid)
                              .where('isRead', isEqualTo: false)
                              .snapshots(),

                    builder: (context, snapshot) {
                      int unreadCount = 0;

                      if (snapshot.hasData) {
                        unreadCount = snapshot.data!.docs.length;
                      }

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          selectedIcon(Icons.notifications),

                          if (unreadCount > 0)
                            Positioned(
                              right: -2,
                              top: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 15,
                                  minHeight: 15,
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
            ),
          ),
        ),
      ),
    );
  }
}
