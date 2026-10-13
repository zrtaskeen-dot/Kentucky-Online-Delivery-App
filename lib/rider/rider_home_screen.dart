import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../rider/rider_logic.dart';
import '../notification_service.dart';
import 'rider_profile.dart';
import 'rider_order_track.dart';

String resolveOrderStatus(Map data) {
  final camel = (data['orderStatus'] ?? '').toString();
  final snake = (data['order_status'] ?? '').toString();
  if (snake.isNotEmpty && snake.toLowerCase() != 'pending') return snake;
  if (camel.isNotEmpty && camel.toLowerCase() != 'pending') return camel;
  return camel.isNotEmpty ? camel : snake;
}

class RiderHomeScreen extends StatefulWidget {
  final String riderId;
  const RiderHomeScreen({super.key, required this.riderId});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _EarningEntry {
  final String name;
  final bool isOnline;
  final DateTime? time;
  final double amount;

  _EarningEntry({
    required this.name,
    required this.isOnline,
    required this.time,
    required this.amount,
  });
}

class _RiderHomeScreenState extends State<RiderHomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const primary = Color(0xFFA70000);
  static const primaryDark = Color(0xFF7A0000);
  static const accentOrange = Color(0xFFFF8A00);
  static const _pendingRed = Color(0xFFD32F2F);
  static const cream = Color(0xFFFFFDF2);
  static const bgColor = Colors.white;

  DateTime? _customStart;
  DateTime? _customEnd;

  late final RiderController _riderController = RiderController();
  Timer? _heartbeatTimer;
  static const Duration _heartbeatEvery = Duration(seconds: 1);

  // Updates live GPS location for all On the Way orders
  StreamSubscription<QuerySnapshot>? _onTheWaySub;

  void _watchOnTheWayOrders() {
    _onTheWaySub = FirebaseFirestore.instance
        .collection('orders')
        .where('riderId', isEqualTo: widget.riderId)
        .where('orderStatus', isEqualTo: 'On the Way')
        .snapshots()
        .listen(
          (snap) =>
              _riderController.syncOnTheWayOrders(snap.docs.map((d) => d.id)),
          onError: (e) => debugPrint('On the Way watcher error: $e'),
        );
  }

  void _goOnline() {
    _riderController.toggleAvailability(widget.riderId, true);
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatEvery, (_) {
      _riderController.sendHeartbeat(widget.riderId);
    });
  }

  void _goOffline() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _riderController.toggleAvailability(widget.riderId, false);
  }

  @override
  void initState() {
    super.initState();
    NotificationService().saveRiderTokenToDatabase(widget.riderId);
    WidgetsBinding.instance.addObserver(this);
    _goOnline();
    _watchOnTheWayOrders();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _goOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _goOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goOffline();
    _onTheWaySub?.cancel();
    _riderController.stopLiveLocationTracking();
    super.dispose();
  }

  Widget selectedIcon(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: accentOrange,
        shape: BoxShape.circle,
        border: Border.all(color: cream, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentOrange.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 21),
    );
  }

  Widget unselectedIcon(IconData icon) {
    return Icon(icon, color: cream.withValues(alpha: 0.75), size: 22);
  }

  // Shows new assigned orders on the Orders tab
  Widget _buildOrdersNavIcon({required bool selected}) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('riderId', isEqualTo: widget.riderId)
          .where('orderStatus', isEqualTo: 'Assigned')
          .snapshots(),
      builder: (context, camelSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('riderId', isEqualTo: widget.riderId)
              .where('order_status', isEqualTo: 'Assigned')
              .snapshots(),
          builder: (context, snakeSnapshot) {
            final newOrderIds = <String>{
              ...?camelSnapshot.data?.docs.map((d) => d.id),
              ...?snakeSnapshot.data?.docs.map((d) => d.id),
            };
            final int newOrdersCount = newOrderIds.length;
            final bool showBadge = newOrdersCount > 0 && !selected;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                selected
                    ? selectedIcon(Icons.shopping_bag)
                    : unselectedIcon(Icons.shopping_bag),
                if (showBadge)
                  Positioned(
                    right: selected ? -2 : -5,
                    top: selected ? -2 : -5,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      decoration: BoxDecoration(
                        color: accentOrange,
                        shape: BoxShape.circle,
                        border: Border.all(color: cream, width: 1.5),
                      ),
                      child: Text(
                        newOrdersCount > 9 ? '9+' : '$newOrdersCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RiderController>.value(
      value: _riderController,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Consumer<RiderController>(
          builder: (context, rc, _) {
            if (_currentIndex == 0) return _buildDashboardTab(rc);
            if (_currentIndex == 1) return _buildOrdersTab(rc);
            return RiderProfileScreen(riderId: widget.riderId);
          },
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [primary, primaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 66,
              child: Theme(
                data: Theme.of(context).copyWith(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  selectedItemColor: accentOrange,
                  unselectedItemColor: cream.withValues(alpha: 0.75),
                  showSelectedLabels: false,
                  showUnselectedLabels: false,
                  selectedFontSize: 0,
                  unselectedFontSize: 0,
                  items: [
                    BottomNavigationBarItem(
                      icon: unselectedIcon(Icons.home),
                      activeIcon: selectedIcon(Icons.home),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: _buildOrdersNavIcon(selected: false),
                      activeIcon: _buildOrdersNavIcon(selected: true),
                      label: 'Orders',
                    ),
                    BottomNavigationBarItem(
                      icon: unselectedIcon(Icons.account_circle),
                      activeIcon: selectedIcon(Icons.account_circle),
                      label: 'Profile',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Earnings date filter

  String _formatDateShort(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _earningsPeriodLabel() {
    if (_customStart != null && _customEnd != null) {
      return '${_formatDateShort(_customStart!)} - ${_formatDateShort(_customEnd!)}';
    }
    return 'All Time';
  }

  bool _dateInEarningsPeriod(DateTime dt) {
    if (_customStart == null || _customEnd == null) return true;
    final startOfDay = DateTime(
      _customStart!.year,
      _customStart!.month,
      _customStart!.day,
    );
    final endOfDay = DateTime(
      _customEnd!.year,
      _customEnd!.month,
      _customEnd!.day,
      23,
      59,
      59,
      999,
    );
    return !dt.isBefore(startOfDay) && !dt.isAfter(endOfDay);
  }

  DateTime? _extractOrderDate(Map<String, dynamic> d) {
    final raw =
        d['statusUpdatedAt'] ??
        d['deliveredAt'] ??
        d['createdAt'] ??
        d['orderDate'] ??
        d['timestamp'] ??
        d['created_at'] ??
        d['orderTime'];

    DateTime? dt;
    if (raw is Timestamp) dt = raw.toDate();
    if (raw is DateTime) dt = raw;
    if (dt == null) return null;
    return dt.toUtc().add(const Duration(hours: 5));
  }

  void _clearCustomRange() {
    setState(() {
      _customStart = null;
      _customEnd = null;
    });
  }

  Future<DateTime?> _showThemedDatePicker(DateTime initial) {
    final today = DateTime.now();
    final safeInitial = initial.isAfter(today) ? today : initial;
    return showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: DateTime(2020),
      lastDate: today,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: primary),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded, size: 18, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value != null ? _formatDateShort(value) : 'Tap to select',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: value != null ? Colors.black87 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCustomRangeSheet() {
    DateTime? tempStart = _customStart;
    DateTime? tempEnd = _customEnd;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                decoration: const BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const Text(
                      'Select Date Range',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dateField(
                      label: 'Start Date',
                      value: tempStart,
                      onTap: () async {
                        final picked = await _showThemedDatePicker(
                          tempStart ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => tempStart = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    _dateField(
                      label: 'End Date',
                      value: tempEnd,
                      onTap: () async {
                        final picked = await _showThemedDatePicker(
                          tempEnd ?? tempStart ?? DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => tempEnd = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (_customStart != null || _customEnd != null)
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: primary.withValues(alpha: 0.4),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                _clearCustomRange();
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Clear',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        if (_customStart != null || _customEnd != null)
                          const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: (tempStart != null && tempEnd != null)
                                ? () {
                                    var s = tempStart!;
                                    var e = tempEnd!;
                                    if (e.isBefore(s)) {
                                      final t = s;
                                      s = e;
                                      e = t;
                                    }
                                    setState(() {
                                      _customStart = s;
                                      _customEnd = e;
                                    });
                                    Navigator.pop(context);
                                  }
                                : null,
                            child: const Text(
                              'Apply',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEarningsPeriodDropdown() {
    final hasRange = _customStart != null && _customEnd != null;
    return GestureDetector(
      onTap: _openCustomRangeSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, size: 16, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasRange ? _earningsPeriodLabel() : 'Select Date Range',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
            if (hasRange)
              GestureDetector(
                onTap: _clearCustomRange,
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: primary,
                ),
              )
            else
              const Icon(Icons.keyboard_arrow_down_rounded, color: primary),
          ],
        ),
      ),
    );
  }

  Widget _earningsSummaryStat(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Rs. ${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatOrderTime(DateTime? dt) {
    if (dt == null) return '--:--';
    int hour12 = dt.hour % 12;
    if (hour12 == 0) hour12 = 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$mm $period';
  }

  Widget _earningsOrderTile(_EarningEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF3E3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: entry.isOnline
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.isOnline ? 'Online' : 'COD',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: entry.isOnline
                              ? Colors.green.shade700
                              : Colors.black54,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatOrderTime(entry.time),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Rs. ${entry.amount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(RiderController rc) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.riderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: CircularProgressIndicator(color: primary));
        }
        final d = snapshot.data!.data() as Map<String, dynamic>;
        final name = d['name'] ?? 'Rider';
        final isAvailable = d['isAvailable'] ?? false;

        return SingleChildScrollView(
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    height: 280,
                    decoration: const BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.elliptical(200, 30),
                        bottomRight: Radius.elliptical(200, 30),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello $name',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Icon(
                              Icons.delivery_dining,
                              size: 130,
                              color: accentOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                isAvailable ? "You're Online, $name" : "You're Offline, $name",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),

                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: isAvailable ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isAvailable
                            ? 'Available for orders'
                            : 'Currently unavailable',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isAvailable ? primary : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const SizedBox(height: 40),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .where('riderId', isEqualTo: widget.riderId)
                    .snapshots(),
                builder: (context, orderSnapshot) {
                  int totalOrders = 0;
                  int delivered = 0;
                  int pending = 0;
                  double totalEarnings = 0;
                  double codEarnings = 0;
                  double onlineEarnings = 0;
                  final List<_EarningEntry> earningEntries = [];

                  if (orderSnapshot.hasData) {
                    final docs = orderSnapshot.data!.docs;
                    totalOrders = docs.length;
                    for (var doc in docs) {
                      final orderData = doc.data() as Map<String, dynamic>;
                      final status = resolveOrderStatus(orderData);
                      if (status == 'Delivered') {
                        delivered++;

                        final bill = orderData['totalAmount'];
                        final billAmt = (bill is num) ? bill.toDouble() : 0.0;
                        final orderDate = _extractOrderDate(orderData);
                        final inSelectedPeriod =
                            orderDate == null ||
                            _dateInEarningsPeriod(orderDate);

                        if (inSelectedPeriod) {
                          final method =
                              (orderData['paymentMethod'] ??
                                      orderData['payment_method'] ??
                                      '')
                                  .toString()
                                  .toLowerCase();
                          final isOnline =
                              method.contains('easypaisa') ||
                              method.contains('jazzcash') ||
                              method == 'online';

                          totalEarnings += billAmt;
                          if (isOnline) {
                            onlineEarnings += billAmt;
                          } else {
                            codEarnings += billAmt;
                          }

                          earningEntries.add(
                            _EarningEntry(
                              name:
                                  (orderData['customerName'] ??
                                          orderData['customer_name'] ??
                                          'Customer')
                                      .toString(),
                              isOnline: isOnline,
                              time: orderDate,
                              amount: billAmt,
                            ),
                          );
                        }
                      } else if (status == 'Accepted' ||
                          status == 'Delivery Started' ||
                          status == 'Picked Up' ||
                          status == 'On the Way' ||
                          status == 'Assigned') {
                        pending++;
                      }
                    }
                  }

                  // Most recent delivery first.
                  earningEntries.sort((a, b) {
                    if (a.time == null && b.time == null) return 0;
                    if (a.time == null) return 1;
                    if (b.time == null) return -1;
                    return b.time!.compareTo(a.time!);
                  });

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statItem('Total Orders', totalOrders.toString()),
                            _statItem('Delivered', delivered.toString()),
                            _statItem('Pending', pending.toString()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Earnings',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildEarningsPeriodDropdown(),
                              const SizedBox(height: 18),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _earningsSummaryStat(
                                    'Total',
                                    totalEarnings,
                                    primary,
                                  ),
                                  _earningsSummaryStat(
                                    'COD',
                                    codEarnings,
                                    Colors.black87,
                                  ),
                                  _earningsSummaryStat(
                                    'Online',
                                    onlineEarnings,
                                    Colors.green.shade700,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Orders (${earningEntries.length})',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (earningEntries.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    'No delivered orders in this period.',
                                    style: TextStyle(
                                      color: Colors.black38,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              else
                                ...earningEntries.map(
                                  (e) => _earningsOrderTile(e),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrdersTab(RiderController rc) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          title: const Text(
            'Current Orders',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          backgroundColor: bgColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => setState(() => _currentIndex = 0),
          ),
          actions: [
            IconButton(
              tooltip: 'Delivery map',
              icon: const Icon(Icons.map_rounded, color: primary),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RiderDeliveriesMapScreen(
                    riderId: widget.riderId,
                    riderController: _riderController,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('riderId', isEqualTo: widget.riderId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: primary),
              );
            }

            final allDocs = snapshot.data!.docs;
            final assignedDocs = allDocs.where((d) {
              final data = d.data() as Map;
              return resolveOrderStatus(data) == 'Assigned';
            }).toList();
            final acceptedDocs = allDocs.where((d) {
              final data = d.data() as Map;
              final s = resolveOrderStatus(data);
              return s == 'Accepted' ||
                  s == 'Delivery Started' ||
                  s == 'On the Way';
            }).toList();

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Orders',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  assignedDocs.isEmpty
                      ? _emptyBox('No new orders assigned.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: assignedDocs.length,
                          itemBuilder: (_, i) => _orderCard(
                            orderId: assignedDocs[i].id,
                            data:
                                assignedDocs[i].data() as Map<String, dynamic>,
                            isAccepted: false,
                            rc: rc,
                          ),
                        ),
                  const SizedBox(height: 24),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: Colors.black26)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'ACTIVE ORDERS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.black26)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  acceptedDocs.isEmpty
                      ? _emptyBox('No active orders.')
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: acceptedDocs.length,
                          itemBuilder: (_, i) => _orderCard(
                            orderId: acceptedDocs[i].id,
                            data:
                                acceptedDocs[i].data() as Map<String, dynamic>,
                            isAccepted: true,
                            rc: rc,
                          ),
                        ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _orderCard({
    required String orderId,
    required Map<String, dynamic> data,
    required bool isAccepted,
    required RiderController rc,
  }) {
    final customerName =
        data['customerName'] ?? data['customer_name'] ?? 'Unknown';
    final address =
        data['deliveryAddress'] ?? data['delivery_address'] ?? 'No address';
    final totalBill = data['totalAmount'] ?? 0;
    final paymentMethod = data['paymentMethod'] ?? data['payment_method'] ?? '';
    final List items = data['items'] ?? [];
    final firstImage = items.isNotEmpty
        ? (items[0] as Map)['imageUrl'] ?? ''
        : '';
    final status = resolveOrderStatus(data);
    final customerId = data['customerId'] ?? data['userId'] ?? '';

    return GestureDetector(
      onTap: () => _showOrderDetail(
        context: context,
        data: data,
        orderId: orderId,
        isAccepted: isAccepted,
        rc: rc,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: firstImage.isNotEmpty
                    ? Image.network(
                        firstImage,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderImg(),
                      )
                    : _placeholderImg(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow(Icons.person_outline, customerName),
                    const SizedBox(height: 5),
                    _infoRow(Icons.location_on_outlined, address),
                    const SizedBox(height: 5),
                    _infoRow(
                      Icons.payment_outlined,
                      '$paymentMethod  •  Rs. $totalBill',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!isAccepted)
                GestureDetector(
                  onTap: () =>
                      rc.acceptOrder(orderId, widget.riderId, customerId),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF4CAF50),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              if (isAccepted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'On the Way':
        return Colors.orange.shade700;
      case 'Delivered':
        return Colors.green.shade700;
      case 'Undelivered':
        return Colors.red.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  void _showOrderDetail({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String orderId,
    required bool isAccepted,
    required RiderController rc,
  }) {
    final customerName =
        data['customerName'] ?? data['customer_name'] ?? 'Unknown';
    final address =
        data['deliveryAddress'] ?? data['delivery_address'] ?? 'No address';
    final totalBill = data['totalAmount'] ?? 0;
    final paymentMethod = data['paymentMethod'] ?? data['payment_method'] ?? '';
    final phone =
        data['phone'] ?? data['phoneNumber'] ?? data['phone_number'] ?? '';
    final lat = data['latitude'];
    final lng = data['longitude'];
    final customerId = data['customerId'] ?? data['userId'] ?? '';

    // "An update is running" for THIS sheet. It lives outside the builder, so
    // rebuilds (or dragging the sheet down and up) never reset it.
    final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

    String failureText() =>
        rc.error.startsWith('Order') ? rc.error : 'Failed to update status';

    Future<void> runStatusUpdate(
      BuildContext sheetContext,
      String target,
      String label,
    ) async {
      if (busy.value) return;
      busy.value = true;
      try {
        final ok = await rc.updateOrderStatus(orderId, target);
        if (ok) {
          if (target == 'Delivered') {
            // Delivered: close the sheet right away.
            if (sheetContext.mounted) Navigator.pop(sheetContext);
            if (mounted) _showTopBanner(this.context, 'Order marked as $label');
          } else if (sheetContext.mounted) {
            _showTopBanner(sheetContext, 'Order marked as $label');
          }
        } else if (sheetContext.mounted) {
          _showTopBanner(sheetContext, failureText());
        }
      } finally {
        busy.value = false;
      }
    }

    Future<void> runUndelivered(BuildContext sheetContext) async {
      if (busy.value) return;
      busy.value = true;
      try {
        final result = await showUndeliveredFlow(
          sheetContext,
          rc: rc,
          orderId: orderId,
        );
        if (result == null) return; // reasons sheet closed
        if (result) {
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          if (mounted) {
            _showTopBanner(this.context, 'Order marked as Undelivered');
          }
        } else if (sheetContext.mounted) {
          _showTopBanner(sheetContext, failureText());
        }
      } finally {
        busy.value = false;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        // Always the latest order from Firestore, never a copy from the list.
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .snapshots(),
        builder: (context, snap) {
          final live = snap.data?.data();
          // '' until the first snapshot arrives: every button stays disabled.
          final String status = live != null ? resolveOrderStatus(live) : '';

          return Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Order Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _detailRow(Icons.person_rounded, 'Customer', customerName),
                  const SizedBox(height: 14),
                  _detailRow(
                    Icons.phone_rounded,
                    'Phone',
                    phone,
                    onTap: () => _callPhone(phone),
                  ),
                  const SizedBox(height: 14),
                  _detailRow(Icons.payment_rounded, 'Payment', paymentMethod),
                  const SizedBox(height: 14),
                  _detailRow(
                    Icons.receipt_long_rounded,
                    'Total Bill',
                    'Rs. $totalBill',
                  ),
                  const SizedBox(height: 14),

                  _detailRow(
                    Icons.location_on_rounded,
                    'Address',
                    address,
                    onTap: (lat != null && lng != null)
                        ? () => _openMap(lat.toDouble(), lng.toDouble())
                        : null,
                    isLink: true,
                  ),
                  const SizedBox(height: 24),

                  if (isAccepted) ...[
                    const Text(
                      'Update Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: busy,
                      builder: (context, isBusy, _) {
                        return Column(
                          children: [
                            _statusButton(
                              label: 'ON THE WAY',
                              targetStatus: 'On the Way',
                              liveStatus: status,
                              busy: isBusy,
                              onPressed: () => runStatusUpdate(
                                context,
                                'On the Way',
                                'ON THE WAY',
                              ),
                            ),
                            const SizedBox(height: 10),
                            _statusButton(
                              label: 'DELIVERED',
                              targetStatus: 'Delivered',
                              liveStatus: status,
                              busy: isBusy,
                              onPressed: () => runStatusUpdate(
                                context,
                                'Delivered',
                                'DELIVERED',
                              ),
                            ),

                            // Only while the order is On the Way, i.e.
                            // exactly when DELIVERED is active.
                            if (status == 'On the Way') ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: isBusy
                                      ? null
                                      : () => runUndelivered(context),
                                  icon: const Icon(
                                    Icons.report_gmailerrorred_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'UNDELIVERED',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primary,
                                    disabledForegroundColor: primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    side: BorderSide(
                                      color: isBusy
                                          ? primary.withValues(alpha: 0.3)
                                          : primary,
                                      width: 1.4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const List<String> _statusSequence = [
    'Accepted',
    'On the Way',
    'Delivered',
  ];

  Widget _statusButton({
    required String label,
    required String targetStatus,
    required String liveStatus, // latest status from Firestore ('' = loading)
    required bool busy,
    required VoidCallback onPressed,
  }) {
    // -1 = not part of the delivery flow (loading, Undelivered, Cancelled...)
    final currentIndex = _statusSequence.indexOf(liveStatus);
    final targetIndex = _statusSequence.indexOf(targetStatus);

    final bool isDone = currentIndex != -1 && currentIndex >= targetIndex;
    final bool isActive =
        !busy && currentIndex != -1 && currentIndex == targetIndex - 1;

    Color background;
    Widget label_;
    if (isDone) {
      background = accentOrange;
      label_ = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 1,
            ),
          ),
        ],
      );
    } else if (isActive) {
      background = _pendingRed;
      label_ = Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
          letterSpacing: 1,
        ),
      );
    } else {
      background = _pendingRed.withValues(alpha: 0.45);
      label_ = Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontWeight: FontWeight.bold,
          fontSize: 15,
          letterSpacing: 1,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          disabledBackgroundColor: background,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isActive ? 4 : 0,
        ),
        onPressed: isActive ? onPressed : null,
        child: label_,
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
    bool isLink = false,
    bool locked = false,
  }) {
    final effectiveOnTap = locked ? null : onTap;
    return GestureDetector(
      onTap: effectiveOnTap,
      child: Opacity(
        opacity: locked ? 0.5 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: locked ? Colors.grey.shade200 : const Color(0xFFF0F0F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: locked ? Colors.grey : primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: locked
                          ? Colors.grey
                          : (isLink && effectiveOnTap != null
                                ? primary
                                : Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              const Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: Colors.grey,
              )
            else if (effectiveOnTap != null)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }

  void _openMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the dialer.')),
        );
      }
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 14),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _placeholderImg() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.fastfood, color: Colors.white, size: 35),
    );
  }

  Widget _emptyBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  Widget _statItem(String title, String count) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          count,
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

void _showTopBanner(
  BuildContext context,
  String message, {
  Color color = const Color(0xFFA70000), // app maroon
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _TopBanner(message: message, color: color, onDone: entry.remove),
  );
  overlay.insert(entry);
}

class _TopBanner extends StatefulWidget {
  final String message;
  final Color color;
  final VoidCallback onDone;
  const _TopBanner({
    required this.message,
    required this.color,
    required this.onDone,
  });

  @override
  State<_TopBanner> createState() => _TopBannerState();
}

class _TopBannerState extends State<_TopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2600), () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 14,
      right: 14,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _ctrl,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.6),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
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
  }
}
