import 'dart:async';
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

  
  StreamSubscription<QuerySnapshot>? _notifSub;
  bool _skippedInitialNotifSnapshot = false;
  OverlayEntry? _bannerEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _listenForNewNotifications(),
    );
  }

  void _listenForNewNotifications() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _notifSub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', whereIn: [uid, 'ALL'])
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (!_skippedInitialNotifSnapshot) {
           
            _skippedInitialNotifSnapshot = true;
            return;
          }
          if (snap.docChanges.isEmpty) return;

          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data() ?? {};
            final hiddenFor = List<String>.from(data['hiddenFor'] ?? const []);
            if (hiddenFor.contains(uid)) continue;
            _showNotificationBanner(
              title: (data['title'] ?? 'New notification').toString(),
              body: (data['body'] ?? '').toString(),
            );
          }
        });
  }

  void _showNotificationBanner({required String title, required String body}) {
    if (!mounted) return;
    _bannerEntry?.remove();

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 8,
        left: 12,
        right: 12,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                _bannerEntry?.remove();
                _bannerEntry = null;
                setState(() => _currentIndex = 2); 
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _maroon,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.notifications,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _cream.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _bannerEntry = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 4), () {
      if (_bannerEntry == entry) {
        entry.remove();
        _bannerEntry = null;
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _bannerEntry?.remove();
    super.dispose();
  }

  
  static const Color _maroon = Color(0xFFA70000);
  static const Color _maroonDark = Color(0xFF7A0000);
  static const Color _orange = Color(0xFFFF8A00);
  static const Color _cream = Color(0xFFFFFDF2);

 
  final List<Widget> _screens = [
    const HomeScreen(),
    OrderHistoryScreen(),
    const NotificationScreen(),
    const ProfileScreen(),
  ];

  
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
            color: _orange.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 21),
    );
  }

  
  Widget unselectedIcon(IconData icon) {
    return Icon(icon, color: _cream.withValues(alpha: 0.75), size: 22);
  }

  
  Widget _notificationIconWithBadge({
    required bool selected,
    required String? currentUserId,
    required DateTime? accountCreatedAt,
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
         
          unreadCount = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final hiddenFor = List<String>.from(data['hiddenFor'] ?? const []);
            if (hiddenFor.contains(currentUserId)) return false;

            if (data['userId'] == 'ALL' && accountCreatedAt != null) {
              final ts = data['timestamp'];
              if (ts is Timestamp && ts.toDate().isBefore(accountCreatedAt)) {
                return false;
              }
            }
            return true;
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
    final accountCreatedAt = currentUser?.metadata.creationTime;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF2),

      body: IndexedStack(index: _currentIndex, children: _screens),

      // Bottom Navigation Bar 
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_maroon, _maroonDark],
          ),
          boxShadow: [
            BoxShadow(
              color: _maroon.withValues(alpha: 0.3),
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
              unselectedItemColor: _cream.withValues(alpha: 0.75),

              showSelectedLabels: false,
              showUnselectedLabels: false,

              selectedFontSize: 0,
              unselectedFontSize: 0,

              items: [
                // Home
                BottomNavigationBarItem(
                  icon: unselectedIcon(Icons.home),
                  activeIcon: selectedIcon(Icons.home),
                  label: 'Home',
                ),

                // My orders
                BottomNavigationBarItem(
                  icon: unselectedIcon(Icons.shopping_bag),
                  activeIcon: selectedIcon(Icons.shopping_bag),
                  label: 'My Orders',
                ),

                // Notifications
                BottomNavigationBarItem(
                  icon: _notificationIconWithBadge(
                    selected: false,
                    currentUserId: currentUser?.uid,
                    accountCreatedAt: accountCreatedAt,
                  ),
                  activeIcon: _notificationIconWithBadge(
                    selected: true,
                    currentUserId: currentUser?.uid,
                    accountCreatedAt: accountCreatedAt,
                  ),
                  label: 'Alerts',
                ),

                //  Profile
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
