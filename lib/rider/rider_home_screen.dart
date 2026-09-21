import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../rider/rider_logic.dart';
import '../notification_service.dart';
import 'rider_profile.dart';

class RiderHomeScreen extends StatefulWidget {
  final String riderId;
  const RiderHomeScreen({super.key, required this.riderId});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

// A single delivered order shown in the earnings list.
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
  // 👈 Matches Home screen's exact brand palette (maroon + orange + white)
  static const primary = Color(0xFFA70000); // Maroon (same as Home) - icons always this color
  static const accentOrange = Color(0xFFFF8A00); // Selected background circle (same as Home)
  static const navBarBg = Color(0xFFFFFDFA); // bottom bar bg (same as Home's card tint)
  static const bgColor = Colors.white; // (same as Home)

  // Earnings filter — a custom date range only. Null start/end means no
  // filter is applied (all delivered orders are counted).
  DateTime? _customStart;
  DateTime? _customEnd;

  // One controller instance kept alive for the whole screen lifetime so
  // lifecycle callbacks (initState/dispose/didChangeAppLifecycleState) can
  // flip availability without needing the widget tree / BuildContext.
  late final RiderController _riderController = RiderController();

  @override
  void initState() {
    super.initState();
    NotificationService().saveRiderTokenToDatabase(widget.riderId);
    WidgetsBinding.instance.addObserver(this);
    // App just opened in foreground -> rider is available automatically.
    _riderController.toggleAvailability(widget.riderId, true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // No manual toggle anymore — availability follows the app's own state.
    if (state == AppLifecycleState.resumed) {
      // Back in foreground -> available again.
      _riderController.toggleAvailability(widget.riderId, true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Backgrounded or closed -> unavailable, manager stops seeing rider.
      _riderController.toggleAvailability(widget.riderId, false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort: also mark unavailable if this screen is torn down
    // directly (e.g. logout) without an app-lifecycle event firing.
    _riderController.toggleAvailability(widget.riderId, false);
    super.dispose();
  }

  Widget _buildNavItem(IconData icon, int index) {
    final bool isSelected = _currentIndex == index;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected ? accentOrange : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 22, color: primary),
    );
  }

  // Same as _buildNavItem, but for the Orders tab specifically: overlays
  // a small red count badge showing how many newly-assigned orders are
  // waiting on this rider (order_status == 'Assigned', not yet
  // accepted). The badge hides itself while the rider is already on the
  // Orders tab — opening that tab is what counts as "having seen" the
  // new orders — and reappears if a fresh one comes in while they're
  // elsewhere in the app.
  Widget _buildOrdersNavIcon(int index) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('riderId', isEqualTo: widget.riderId)
          .where('order_status', isEqualTo: 'Assigned')
          .snapshots(),
      builder: (context, snapshot) {
        final int newOrdersCount = snapshot.data?.docs.length ?? 0;
        final bool showBadge = newOrdersCount > 0 && _currentIndex != index;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _buildNavItem(Icons.shopping_bag, index),
            if (showBadge)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: navBarBg, width: 1.5),
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
        bottomNavigationBar: SafeArea(
          child: Container(
            height: 68,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: navBarBg,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: Theme(
                data: Theme.of(context).copyWith(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: BottomNavigationBar(
                  currentIndex: _currentIndex,
                  onTap: (i) => setState(() => _currentIndex = i),
                  showSelectedLabels: false,
                  showUnselectedLabels: false,
                  backgroundColor: navBarBg,
                  type: BottomNavigationBarType.fixed,
                  items: [
                    BottomNavigationBarItem(
                      icon: _buildNavItem(Icons.home, 0),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: _buildOrdersNavIcon(1),
                      label: 'Orders',
                    ),
                    BottomNavigationBarItem(
                      icon: _buildNavItem(Icons.account_circle, 2),
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

  // ── Earnings date filter helpers (custom range only) ──────────────

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

  // Orders may record the delivery/creation time under different field
  // names — prefer the moment the order was actually delivered
  // (statusUpdatedAt) since that's when the earning was made, and fall
  // back to other common date fields if it isn't present. The result is
  // always converted to Pakistan Standard Time (UTC+5) so times shown on
  // screen are consistent no matter what timezone the phone is set to.
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

    // Normalize to Pakistan Standard Time (UTC+5), regardless of the
    // device's own timezone setting.
    return dt.toUtc().add(const Duration(hours: 5));
  }

  void _clearCustomRange() {
    setState(() {
      _customStart = null;
      _customEnd = null;
    });
  }

  // A single, themed date picker restricted so no future date (tomorrow
  // onward) can ever be picked.
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

  // Compact, app-themed bottom sheet with two simple date fields — no
  // giant calendar and no connecting bar between the start/end dates.
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

  // dt is already normalized to Pakistan Standard Time by
  // _extractOrderDate, so this just formats it as 12-hour with AM/PM.
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
                  // Read-only status — no toggle. This updates itself when
                  // the app opens (available) or is backgrounded/closed
                  // (unavailable), via didChangeAppLifecycleState above.
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
                      final status = orderData['order_status'];
                      if (status == 'Delivered') {
                        delivered++;
                        // Rider's earning for a delivered order = its bill.
                        final bill = orderData['totalAmount'];
                        final billAmt = (bill is num) ? bill.toDouble() : 0.0;

                        // Only count this order's earning toward the total
                        // if it falls inside the currently selected date
                        // filter (Today / This Week / All Time / Custom).
                        final orderDate = _extractOrderDate(orderData);
                        final inSelectedPeriod =
                            orderDate == null ||
                            _dateInEarningsPeriod(orderDate);

                        if (inSelectedPeriod) {
                          final method = (orderData['payment_method'] ?? '')
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
                              name: (orderData['customer_name'] ?? 'Customer')
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
            final assignedDocs = allDocs
                .where((d) => (d.data() as Map)['order_status'] == 'Assigned')
                .toList();
            final acceptedDocs = allDocs.where((d) {
              final s = (d.data() as Map)['order_status'];
              return s == 'Accepted' ||
                  s == 'Delivery Started' ||
                  s == 'Picked Up' ||
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
    final customerName = data['customer_name'] ?? 'Unknown';
    final address = data['delivery_address'] ?? 'No address';
    final totalBill = data['totalAmount'] ?? 0;
    final paymentMethod = data['payment_method'] ?? '';
    final List items = data['items'] ?? [];
    final firstImage = items.isNotEmpty
        ? (items[0] as Map)['imageUrl'] ?? ''
        : '';
    final status = data['order_status'] ?? '';
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
      case 'Delivery Started':
        return Colors.deepPurple.shade400;
      case 'Picked Up':
        return Colors.blue.shade700;
      case 'On the Way':
        return Colors.orange.shade700;
      case 'Delivered':
        return Colors.green.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  // NOTE: not currently wired to any button — the Start Delivery button
  // and each status button below call rc.updateOrderStatus() directly so
  // they can update this sheet's local state via onSuccess. Kept here in
  // case a screen outside the sheet needs the same status-update +
  // one-delivery-popup handling.
  Future<void> _handleStatusUpdate({
    required BuildContext context,
    required RiderController rc,
    required String orderId,
    required String newStatus,
  }) async {
    final success = await rc.updateOrderStatus(orderId, newStatus);
    if (!context.mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated: $newStatus'),
          backgroundColor: primary,
        ),
      );
    } else {
      _showOneDeliveryDialog(context, rc.error);
    }
  }

  void _showOneDeliveryDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'One Delivery at a Time',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message.isNotEmpty
                    ? message
                    : 'You can only have one delivery in progress. Please complete your current delivery before starting another.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'GOT IT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOrderDetail({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String orderId,
    required bool isAccepted,
    required RiderController rc,
  }) {
    final customerName = data['customer_name'] ?? 'Unknown';
    final address = data['delivery_address'] ?? 'No address';
    final totalBill = data['totalAmount'] ?? 0;
    final paymentMethod = data['payment_method'] ?? '';
    final phone = data['phone_number'] ?? '';
    final lat = data['latitude'];
    final lng = data['longitude'];
    final currentStatus = data['order_status'] ?? '';
    final customerId =
        data['customerId'] ?? data['userId'] ?? ''; // 👈 Extracted customerId

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          // Local session state for this sheet:
          // - started: whether "Start Delivery" has been tapped (or the
          //   order was already Picked Up/beyond when the sheet opened).
          //   Unlocks the address and the PICKED UP button.
          // - localStatus: tracks progress through the sequence within
          //   this sheet so buttons update immediately after each tap
          //   without waiting for a Firestore stream refresh.
          bool started = currentStatus != 'Accepted';
          String localStatus = currentStatus;

          return StatefulBuilder(
            builder: (context, setLocalState) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFDF0),
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
                      _detailRow(
                        Icons.person_rounded,
                        'Customer',
                        customerName,
                      ),
                      const SizedBox(height: 14),
                      _detailRow(
                        Icons.phone_rounded,
                        'Phone',
                        phone,
                        onTap: () => _callPhone(phone),
                      ),
                      const SizedBox(height: 14),
                      _detailRow(
                        Icons.payment_rounded,
                        'Payment',
                        paymentMethod,
                      ),
                      const SizedBox(height: 14),
                      _detailRow(
                        Icons.receipt_long_rounded,
                        'Total Bill',
                        'Rs. $totalBill',
                      ),
                      const SizedBox(height: 14),
                      // Locked (greyed out, not tappable) until the rider
                      // presses "Start Delivery". Once unlocked, tapping
                      // the address opens navigation — this replaces the
                      // separate "Navigate to Customer" button.
                      _detailRow(
                        Icons.location_on_rounded,
                        'Address',
                        address,
                        onTap: (started && lat != null && lng != null)
                            ? () => _openMap(lat.toDouble(), lng.toDouble())
                            : null,
                        isLink: true,
                        locked: !started,
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
                        // const SizedBox(height: 6),
                        // const Text(
                        //   'Customer aur admin ko delivery ka pata chalay.',
                        //   style: TextStyle(fontSize: 13, color: Colors.grey),
                        // ),
                        const SizedBox(height: 16),

                        // Start Delivery: this is the real "start" of the
                        // delivery. It writes order_status: 'Delivery
                        // Started' and runs the one-active-delivery check —
                        // if the rider already has another delivery in
                        // progress, the warning popup appears here instead
                        // of unlocking the rest of the sheet. On success it
                        // unlocks the address + the sequential status
                        // buttons below, and becomes disabled.
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: started
                                  ? primary.withValues(alpha: 0.35)
                                  : primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: started ? 0 : 3,
                            ),
                            icon: Icon(
                              Icons.local_shipping_rounded,
                              color: Colors.white.withValues(
                                alpha: started ? 0.7 : 1,
                              ),
                            ),
                            label: Text(
                              'Start Delivery',
                              style: TextStyle(
                                color: Colors.white.withValues(
                                  alpha: started ? 0.7 : 1,
                                ),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: started
                                ? null
                                : () async {
                                    final success = await rc.updateOrderStatus(
                                      orderId,
                                      'Delivery Started',
                                    );
                                    if (!context.mounted) return;
                                    if (success) {
                                      setLocalState(() {
                                        started = true;
                                        localStatus = 'Delivery Started';
                                      });
                                    } else {
                                      _showOneDeliveryDialog(context, rc.error);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(height: 10),

                        _statusButton(
                          label: 'PICKED UP',
                          color: primary,
                          orderId: orderId,
                          targetStatus: 'Picked Up',
                          localStatus: localStatus,
                          started: started,
                          rc: rc,
                          onSuccess: (s) =>
                              setLocalState(() => localStatus = s),
                        ),
                        const SizedBox(height: 10),
                        _statusButton(
                          label: 'ON THE WAY',
                          color: Colors.orange.shade700,
                          orderId: orderId,
                          targetStatus: 'On the Way',
                          localStatus: localStatus,
                          started: started,
                          rc: rc,
                          onSuccess: (s) =>
                              setLocalState(() => localStatus = s),
                        ),
                        const SizedBox(height: 10),
                        _statusButton(
                          label: 'DELIVERED',
                          color: const Color(0xFF6B2000),
                          orderId: orderId,
                          targetStatus: 'Delivered',
                          localStatus: localStatus,
                          started: started,
                          rc: rc,
                          onSuccess: (s) =>
                              setLocalState(() => localStatus = s),
                        ),
                      ],

                      const SizedBox(height: 20),
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

  // Sequence used to decide each status button's state: locked (can't
  // tap yet), active (tappable — it's the next step), or done (already
  // completed, can't be re-selected).
  static const List<String> _statusSequence = [
    'Accepted',
    'Delivery Started',
    'Picked Up',
    'On the Way',
    'Delivered',
  ];

  int _statusStepIndex(String status) {
    final i = _statusSequence.indexOf(status);
    return i == -1 ? 0 : i;
  }

  Widget _statusButton({
    required String label,
    required Color color,
    required String orderId,
    required String targetStatus,
    required String localStatus,
    required bool started,
    required RiderController rc,
    required void Function(String newStatus) onSuccess,
  }) {
    final currentIndex = _statusStepIndex(localStatus);
    final targetIndex = _statusStepIndex(targetStatus);

    final bool isDone = currentIndex >= targetIndex;
    final bool isActive = started && !isDone && currentIndex == targetIndex - 1;

    Color background;
    Widget label_;
    if (isDone) {
      background = color.withValues(alpha: 0.35);
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
      background = color;
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
      background = color.withValues(alpha: 0.25);
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
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isActive ? 4 : 0,
        ),
        onPressed: isActive
            ? () async {
                final success = await rc.updateOrderStatus(
                  orderId,
                  targetStatus,
                );
                if (!context.mounted) return;
                if (success) {
                  onSuccess(targetStatus);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.all(14),
                      content: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Order marked as $label',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                } else {
                  _showOneDeliveryDialog(context, rc.error);
                }
              }
            : null,
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