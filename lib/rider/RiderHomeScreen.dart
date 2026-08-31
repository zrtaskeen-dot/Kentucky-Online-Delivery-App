import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../logic/rider_logic.dart';
import '../services/notification_service.dart';
import 'rider_profile.dart';

class RiderHomeScreen extends StatefulWidget {
  final String riderId;
  const RiderHomeScreen({super.key, required this.riderId});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  int _currentIndex = 0;
  static const primary = Color(0xFFA30000); // Maroon - icons always this color
  static const accentOrange = Color(0xFFFF9831); // Selected background circle
  static const navBarBg = Color(0xFFFFFFF0); // bottom bar bg
  static const bgColor = Color(0xFFFFFDF0);

  @override
  void initState() {
    super.initState();
    NotificationService().saveRiderTokenToDatabase(widget.riderId);
  }

  // 👈 UPDATED: Added customerId to trigger push notifications via Node.js backend
  Future<void> _updateOrderStatus(
    RiderController rc,
    String orderId,
    String status,
    String customerId,
  ) async {
    // 1. Update Firestore status
    await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
      'order_status': status,
      'statusUpdatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Trigger push notification through backend API
    if (customerId.isNotEmpty) {
      await rc.notifyCustomerForStatus(customerId, status);
    }

    // 3. Stop live tracking if delivered
    if (status == 'Delivered') {
      rc.stopLiveLocationTracking();
    }
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RiderController>(
      create: (_) => RiderController(),
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
                  color: Colors.black.withOpacity(0.1),
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
                      icon: _buildNavItem(Icons.shopping_bag, 1),
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
                            'Hello $name 🛵',
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
                'Are you available, $name?',
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
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        'Available',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isAvailable ? primary : Colors.black87,
                        ),
                      ),
                      GestureDetector(
                        onTap: rc.isLoading
                            ? null
                            : () => rc.toggleAvailability(
                                widget.riderId,
                                !isAvailable,
                              ),
                        child: Container(
                          width: 70,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: isAvailable
                                ? const Color(0xFFE57373)
                                : Colors.grey.shade400,
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: isAvailable
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: primary,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Unavailable',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: !isAvailable ? Colors.grey : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (rc.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: LinearProgressIndicator(color: primary),
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

                  if (orderSnapshot.hasData) {
                    final docs = orderSnapshot.data!.docs;
                    totalOrders = docs.length;
                    for (var doc in docs) {
                      final status =
                          (doc.data() as Map<String, dynamic>)['order_status'];
                      if (status == 'Delivered') {
                        delivered++;
                      } else if (status == 'Accepted' ||
                          status == 'Picked Up' ||
                          status == 'On the Way' ||
                          status == 'Assigned') {
                        pending++;
                      }
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statItem('Total Orders', totalOrders.toString()),
                        _statItem('Delivered', delivered.toString()),
                        _statItem('Pending', pending.toString()),
                      ],
                    ),
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
              return s == 'Accepted' || s == 'Picked Up' || s == 'On the Way';
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
    final totalBill = data['total_bill'] ?? 0;
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
              color: primary.withOpacity(0.3),
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

  void _showOrderDetail({
    required BuildContext context,
    required Map<String, dynamic> data,
    required String orderId,
    required bool isAccepted,
    required RiderController rc,
  }) {
    final customerName = data['customer_name'] ?? 'Unknown';
    final address = data['delivery_address'] ?? 'No address';
    final totalBill = data['total_bill'] ?? 0;
    final paymentMethod = data['payment_method'] ?? '';
    final phone = data['phone_number'] ?? '';
    final lat = data['latitude'];
    final lng = data['longitude'];
    final currentStatus = data['order_status'] ?? '';
    final customerId = data['customerId'] ?? data['userId'] ?? ''; // 👈 Extracted customerId

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                const SizedBox(height: 6),
                const Text(
                  'Customer aur admin ko delivery ka pata chalay.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                // 👈 Updated to pass customerId
                _statusButton('PICKED UP', primary, orderId, currentStatus, rc, customerId),
                const SizedBox(height: 10),
                _statusButton(
                  'ON THE WAY',
                  Colors.orange.shade700,
                  orderId,
                  currentStatus,
                  rc,
                  customerId,
                ),
                const SizedBox(height: 10),
                _statusButton(
                  'DELIVERED',
                  const Color(0xFF6B2000),
                  orderId,
                  currentStatus,
                  rc,
                  customerId,
                ),
              ],

              const SizedBox(height: 16),
              if (lat != null && lng != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.map_rounded, color: Colors.white),
                    label: const Text(
                      'Navigate to Customer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _openMap(lat.toDouble(), lng.toDouble()),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 👈 UPDATED: Added customerId parameter
  Widget _statusButton(
    String label,
    Color color,
    String orderId,
    String currentStatus,
    RiderController rc,
    String customerId,
  ) {
    final statusMap = {
      'PICKED UP': 'Picked Up',
      'ON THE WAY': 'On the Way',
      'DELIVERED': 'Delivered',
    };
    final firestoreStatus = statusMap[label] ?? label;
    final isActive = currentStatus == firestoreStatus;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? color : color.withOpacity(0.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isActive ? 4 : 0,
        ),
        onPressed: () async {
          Navigator.pop(context);
          // 👈 Sends update to Firestore and triggers backend push notification
          await _updateOrderStatus(rc, orderId, firestoreStatus, customerId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Status updated: $firestoreStatus'),
                backgroundColor: color,
              ),
            );
          }
        },
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
    bool isLink = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: primary),
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
                    color: isLink && onTap != null
                        ? Colors.blue
                        : Colors.black87,
                    decoration: isLink && onTap != null
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey,
            ),
        ],
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
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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