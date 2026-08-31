import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/rider_logic.dart';

class RiderOrderScreen extends StatelessWidget {
  final String riderId;

  const RiderOrderScreen({super.key, required this.riderId});

  List<Map<String, dynamic>> _normalizeItems(Map<String, dynamic> data) {
    final rawItems = data['items'] ?? data['cartItems'];
    if (rawItems == null) return [];

    if (rawItems is List) {
      return rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (rawItems is Map) {
      final entries = rawItems.entries.toList();
      entries.sort((a, b) {
        final aNum = int.tryParse(a.key.toString());
        final bNum = int.tryParse(b.key.toString());
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        return a.key.toString().compareTo(b.key.toString());
      });
      return entries
          .map((e) => e.value)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  double _parsePrice(Map<String, dynamic> data) {
    final rawAmount =
        data['totalAmount'] ??
        data['total_bill'] ??
        data['grandTotal'] ??
        data['totalPrice'] ??
        data['finalAmount'] ??
        data['total'] ??
        data['price'] ??
        data['amount'];

    if (rawAmount != null) {
      if (rawAmount is num) return rawAmount.toDouble();
      if (rawAmount is String) {
        final parsed = double.tryParse(rawAmount.trim());
        if (parsed != null) return parsed;
      }
    }

    final items = _normalizeItems(data);
    if (items.isNotEmpty) {
      double total = 0.0;
      for (var item in items) {
        final p = item['price'] ?? item['itemPrice'] ?? item['unitPrice'];
        final q = item['quantity'] ?? item['qty'] ?? 1;

        double itemPrice = 0.0;
        if (p is num) itemPrice = p.toDouble();
        if (p is String) itemPrice = double.tryParse(p) ?? 0.0;

        int itemQty = 1;
        if (q is num) itemQty = q.toInt();
        if (q is String) itemQty = int.tryParse(q) ?? 1;

        total += (itemPrice * itemQty);
      }
      if (total > 0) return total;
    }

    return 0.0;
  }

  String _getItemTitle(Map<String, dynamic> data) {
    if (data['itemName'] != null && data['itemName'].toString().isNotEmpty) {
      return data['itemName'].toString();
    }
    if (data['name'] != null && data['name'].toString().isNotEmpty) {
      return data['name'].toString();
    }

    final items = _normalizeItems(data);
    if (items.isNotEmpty) {
      final firstName = items[0]['name']?.toString() ?? 'Food Item';
      if (items.length > 1) {
        return "$firstName +${items.length - 1} more";
      }
      return firstName;
    }

    return 'Order Item';
  }

  String _getItemImage(Map<String, dynamic> data) {
    if (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) {
      return data['imageUrl'].toString();
    }

    final items = _normalizeItems(data);
    if (items.isNotEmpty) {
      final img = items[0]['imageUrl'];
      if (img != null && img.toString().isNotEmpty) return img.toString();
    }
    return '';
  }

  // Safe Customer ID Extractor Helper
  String _extractCustomerId(Map<String, dynamic> data) {
    return data['customerId']?.toString() ??
        data['userId']?.toString() ??
        data['customer_id']?.toString() ??
        data['user_id']?.toString() ??
        '';
  }

  @override
  Widget build(BuildContext context) {
    final riderController = Provider.of<RiderController>(context);

    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFFFFFDF0),
        appBar: AppBar(
          title: const Text(
            'Current Orders',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          backgroundColor: const Color(0xFFFFFDF0),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stream 1: Pending Orders
                StreamBuilder<QuerySnapshot>(
                  stream: riderController.getPendingOrders(riderId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFA30000),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            "No incoming new orders.",
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final orderId = docs[index].id;
                        final customerId = _extractCustomerId(data);

                        return _buildOrderCard(
                          orderId: orderId,
                          customerId: customerId,
                          title: _getItemTitle(data),
                          customer:
                              data['customer_name'] ??
                              data['customerName'] ??
                              data['name'] ??
                              'Customer',
                          address:
                              data['delivery_address'] ??
                              data['address'] ??
                              'No Address Provided',
                          lat: (data['latitude'] as num?)?.toDouble(),
                          lng: (data['longitude'] as num?)?.toDouble(),
                          imageUrl: _getItemImage(data),
                          price: _parsePrice(data),
                          isAccepted: false,
                          riderController: riderController,
                          context: context,
                        );
                      },
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "- - - - - - - - - - - - - -",
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          "ACCEPTED ORDERS",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          "- - - - - - - - - - - - - -",
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),

                // Stream 2: Accepted Orders
                StreamBuilder<QuerySnapshot>(
                  stream: riderController.getAcceptedOrders(riderId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFA30000),
                        ),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            "No accepted orders yet.",
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final orderId = docs[index].id;
                        final customerId = _extractCustomerId(data);

                        return _buildOrderCard(
                          orderId: orderId,
                          customerId: customerId,
                          title: _getItemTitle(data),
                          customer:
                              data['customer_name'] ??
                              data['customerName'] ??
                              data['name'] ??
                              'Customer',
                          address:
                              data['delivery_address'] ??
                              data['address'] ??
                              'No Address Provided',
                          lat: (data['latitude'] as num?)?.toDouble(),
                          lng: (data['longitude'] as num?)?.toDouble(),
                          imageUrl: _getItemImage(data),
                          price: _parsePrice(data),
                          isAccepted: true,
                          riderController: riderController,
                          context: context,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard({
    required String orderId,
    required String customerId,
    required String title,
    required String customer,
    required String address,
    required double? lat,
    required double? lng,
    required String imageUrl,
    required double price,
    required bool isAccepted,
    required RiderController riderController,
    required BuildContext context,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFA62B00),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.black26,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.fastfood,
                        color: Colors.white,
                        size: 35,
                      ),
                    ),
                  )
                : Container(
                    color: Colors.black26,
                    width: 80,
                    height: 80,
                    child: const Icon(
                      Icons.fastfood,
                      color: Colors.white,
                      size: 35,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Rs. ${price.toStringAsFixed(0)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    children: [
                      const TextSpan(
                        text: 'Customer Name  ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: customer),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    children: [
                      const TextSpan(
                        text: 'Address  ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: address),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAccepted) ...[
                GestureDetector(
                  onTap: () {
                    riderController.launchCustomerNavigation(
                      lat: lat,
                      lng: lng,
                      fallbackAddress: address,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(
                      Icons.navigation,
                      color: Color(0xFFA62B00),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Status Update Notification Trigger Button
                GestureDetector(
                  onTap: () async {
                    if (customerId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Error: Customer ID not found!"),
                          backgroundColor: Colors.black,
                        ),
                      );
                      return;
                    }
                    await riderController.notifyCustomerForStatus(
                      customerId,
                      "On The Way 🛵",
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Notification sent to customer!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber,
                    ),
                    child: const Icon(
                      Icons.notifications_active,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                ),
              ] else ...[
                GestureDetector(
                  onTap: () async {
                    if (customerId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Customer ID missing in order doc!"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }

                    await riderController.acceptOrder(
                      orderId,
                      riderId,
                      customerId,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF4CAF50),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
