import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'cart_provider.dart';
import 'firebase.dart';
import 'orderDetail.dart';

class DeliveryScreen extends StatefulWidget {
  final double totalAmount;
  final List<CartItem> cartItems;
  final String userName;
  final String userPhone;
  final LatLng selectedLocation;
  final String addressDetails;

  const DeliveryScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
    required this.userName,
    required this.userPhone,
    required this.selectedLocation,
    required this.addressDetails,
  });

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  String _deliveryMode = '';
  String _paymentMode = 'COD';
  String? _selectedProvider;

  bool _isLoading = false;
  bool _isVerifyingImage = false;
  String _restaurantTiming = '';

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _transactionIdController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  String _receiverPhone = "03185940648";
  bool _loadingManagerPhone = false;

  static const String _cloudinaryUrl = "https://api.cloudinary.com/v1_1/dqjqkwwwh/image/upload";
  static const String _receiptUploadPreset = "payment_receipts";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRestaurantTiming();
      _fetchManagerPhone();
    });
  }

  Future<void> _fetchRestaurantTiming() async {
    try {
      final branchId = Provider.of<CartProvider>(
        context,
        listen: false,
      ).selectedBranchId;
      if (branchId.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('restaurant_info')
          .doc(branchId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final timing = (data['timing'] ?? '').toString();
        if (timing.isNotEmpty) {
          setState(() => _restaurantTiming = timing);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch restaurant timing: $e');
    }
  }

  Future<void> _fetchManagerPhone() async {
    setState(() => _loadingManagerPhone = true);
    try {
      final branchId = Provider.of<CartProvider>(
        context,
        listen: false,
      ).selectedBranchId;

      if (branchId.isEmpty) {
        setState(() => _loadingManagerPhone = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('branchId', isEqualTo: branchId)
          .where('role', isEqualTo: 'manager')
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        final phone = (data['phone'] ?? data['phone_number'] ?? '').toString().trim();
        if (phone.isNotEmpty) {
          setState(() {
            _receiverPhone = phone;
            _loadingManagerPhone = false;
          });
          return;
        }
      }

      setState(() => _loadingManagerPhone = false);
    } catch (e) {
      debugPrint('Failed to fetch manager phone: $e');
      setState(() => _loadingManagerPhone = false);
    }
  }

  TimeOfDay? _parseTimeString(String timeStr) {
    try {
      timeStr = timeStr.trim().toLowerCase();
      bool isPm = timeStr.contains('pm');
      bool isAm = timeStr.contains('am');

      String cleanStr = timeStr.replaceAll(RegExp(r'[^\d:]'), '');
      List<String> parts = cleanStr.split(':');
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

      if (isPm && hour < 12) hour += 12;
      if (isAm && hour == 12) hour = 0;

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }

  bool _isTimeWithinOperatingHours(TimeOfDay selected) {
    if (_restaurantTiming.isEmpty || !_restaurantTiming.toLowerCase().contains(' to ')) {
      return true;
    }

    final parts = _restaurantTiming.toLowerCase().split(' to ');
    final openTime = _parseTimeString(parts[0]);
    final closeTime = _parseTimeString(parts[1]);

    if (openTime == null || closeTime == null) return true;

    int selectedMins = selected.hour * 60 + selected.minute;
    int openMins = openTime.hour * 60 + openTime.minute;
    int closeMins = closeTime.hour * 60 + closeTime.minute;

    if (openMins < closeMins) {
      return selectedMins >= openMins && selectedMins <= closeMins;
    } else {
      return selectedMins >= openMins || selectedMins <= closeMins;
    }
  }

  static const Color backgroundColor = Color(0xFFFFFDF0);
  static const Color orangeCardColor = Color(0xFFF9F0E0);
  static const Color buttonColor = Color(0xFFA62600);
  static const Color innerFieldColor = Color(0xFFFFFFF5);
  static const Color outlineColor = Colors.black26;

  // ML-KIT OCR BASED EASYPAISA / JAZZCASH VERIFICATION
  Future<bool> _verifyImageWithMLKit(File file, String provider) async {
    setState(() => _isVerifyingImage = true);
    final inputImage = InputImage.fromFile(file);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      final String scannedText = recognizedText.text.toLowerCase();
      await textRecognizer.close();

      bool isValid = false;

      if (provider == 'EasyPaisa') {
        isValid = scannedText.contains('easypaisa') ||
            scannedText.contains('easy paisa') ||
            scannedText.contains('telenor microfinance');
      } else if (provider == 'JazzCash') {
        isValid = scannedText.contains('jazzcash') ||
            scannedText.contains('jazz cash') ||
            scannedText.contains('mobilink microfinance');
      }

      setState(() => _isVerifyingImage = false);

      if (!isValid) {
        _showThemedSnack(
          "Invalid Screenshot! Please upload a correct $provider receipt screenshot.",
          buttonColor,
        );
        return false;
      }

      return true;
    } catch (e) {
      await textRecognizer.close();
      setState(() => _isVerifyingImage = false);
      _showThemedSnack(
        "Failed to read text from screenshot. Please try again.",
        buttonColor,
      );
      return false;
    }
  }

  Future<void> _pickReceiptImage() async {
    if (_selectedProvider == null) {
      _showThemedSnack("Please select EasyPaisa or JazzCash first.", buttonColor);
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile == null) return;

      File tempFile = File(pickedFile.path);

      // Verify screenshot using OCR
      bool isVerified = await _verifyImageWithMLKit(tempFile, _selectedProvider!);
      if (!isVerified) return;

      setState(() {
        _imageFile = tempFile;
      });

      _showThemedSnack("Valid $_selectedProvider receipt uploaded successfully!", buttonColor);
    } catch (e) {
      _showThemedSnack("Failed to pick image from gallery.", buttonColor);
    }
  }

  void _showThemedSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _pickScheduleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: buttonColor,
              onPrimary: Colors.white,
              surface: backgroundColor,
              onSurface: Colors.black,
            ),
            dialogBackgroundColor: backgroundColor,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _scheduledDate = picked);
    }
  }

  Future<void> _pickScheduleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: buttonColor,
              onPrimary: Colors.white,
              surface: backgroundColor,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (!_isTimeWithinOperatingHours(picked)) {
        _showThemedSnack(
          "Selected time is outside operating hours ($_restaurantTiming)",
          buttonColor,
        );
        return;
      }
      setState(() => _scheduledTime = picked);
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  Future<String?> _uploadReceiptImage() async {
    if (_imageFile == null) return null;

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_cloudinaryUrl))
        ..fields['upload_preset'] = _receiptUploadPreset
        ..fields['tags'] = _selectedProvider ?? 'payment_receipt'
        ..files.add(await http.MultipartFile.fromPath('file', _imageFile!.path));

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(responseBody);
      return data['secure_url'] as String?;
    } catch (e) {
      return null;
    }
  }

  Future<void> _clearFirestoreCart() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';
      final cartDocs = await FirebaseFirestore.instance
          .collection('carts')
          .where('userId', isEqualTo: userId)
          .get();

      for (final doc in cartDocs.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Failed to clear cart: $e');
    }
  }

  Future<void> handleOrderConfirmation() async {
    if (_deliveryMode.isEmpty) {
      _showThemedSnack("Please select a delivery option to proceed.", buttonColor);
      return;
    }

    if (_paymentMode == 'Online' && _selectedProvider == null) {
      _showThemedSnack("Please select your online payment provider.", buttonColor);
      return;
    }

    final bool needsReceipt = _paymentMode == 'Online';

    if (needsReceipt && _imageFile == null) {
      _showThemedSnack("Please upload a valid ${_selectedProvider ?? 'Online'} screenshot.", buttonColor);
      return;
    }

    if (_deliveryMode == 'later') {
      if (_scheduledDate == null || _scheduledTime == null) {
        _showThemedSnack("Please select date and time for scheduled delivery.", buttonColor);
        return;
      }
    }

    setState(() => _isLoading = true);

    String? receiptImageUrl;
    if (needsReceipt) {
      receiptImageUrl = await _uploadReceiptImage();
      if (receiptImageUrl == null) {
        setState(() => _isLoading = false);
        _showThemedSnack("Payment receipt upload failed. Please try again.", buttonColor);
        return;
      }
    }

    try {
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      String activeBranchId = cartProvider.selectedBranchId;

      String deliveryTimeLabel = "Standard Delivery";
      if (_deliveryMode == 'later' && _scheduledDate != null && _scheduledTime != null) {
        deliveryTimeLabel = "${_formatDate(_scheduledDate!)} at ${_formatTime(_scheduledTime!)}";
      }

      final String finalPaymentMethod = _paymentMode == 'COD' ? 'Cash On Delivery' : (_selectedProvider ?? 'Online Payment');

      final String newOrderId = await _firestoreService.saveOrder(
        name: widget.userName,
        phone: widget.userPhone,
        address: widget.addressDetails,
        latitude: widget.selectedLocation.latitude,
        longitude: widget.selectedLocation.longitude,
        totalAmount: widget.totalAmount,
        deliveryTime: deliveryTimeLabel,
        paymentMethod: finalPaymentMethod,
        cartItems: widget.cartItems,
        transactionId: _transactionIdController.text.isNotEmpty ? _transactionIdController.text : "N/A",
        branchId: activeBranchId,
        receiptImageUrl: receiptImageUrl,
      );

      final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId != null) {
        await FirebaseFirestore.instance.collection('users').doc(currentUserId).set({
          'phone_number': widget.userPhone,
          'address': widget.addressDetails,
          'name': widget.userName,
        }, SetOptions(merge: true));
      }

      await _clearFirestoreCart();
      if (mounted) {
        cartProvider.clearCart();
      }

      setState(() => _isLoading = false);
      showOrderPopup(deliveryTimeLabel, newOrderId, finalPaymentMethod);
    } catch (e) {
      setState(() => _isLoading = false);
      _showThemedSnack("Order processing failed: $e", buttonColor);
    }
  }

  void showOrderPopup(String deliveryTimeLabel, String orderId, String finalPaymentMethod) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(
          orderId: orderId,
          userName: widget.userName,
          userPhone: widget.userPhone,
          addressDetails: widget.addressDetails,
          totalAmount: widget.totalAmount,
          cartItems: widget.cartItems,
          paymentMethod: finalPaymentMethod,
          deliveryLocation: widget.selectedLocation,
          deliveryTime: deliveryTimeLabel,
        ),
      ),
    );
  }

  void _switchDeliveryMode(String mode) {
    if (_deliveryMode == mode) return;
    setState(() {
      _deliveryMode = mode;
      _paymentMode = 'COD';
      _selectedProvider = null;
      _imageFile = null;
      _transactionIdController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final int totalItemCount = widget.cartItems.fold(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: buttonColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: backgroundColor, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Delivery Options", style: TextStyle(color: backgroundColor, fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildDeliverNowSection(),
                    const SizedBox(height: 16),
                    _buildDeliverLaterSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildSummaryBar(totalItemCount),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withOpacity(0.25) : buttonColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isSelected ? Colors.black87 : buttonColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? buttonColor : Colors.transparent,
              border: Border.all(color: isSelected ? buttonColor : Colors.black45, width: 2),
            ),
            child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliverNowSection() {
    final bool isExpanded = _deliveryMode == 'now';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isExpanded ? orangeCardColor : innerFieldColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.bolt_rounded,
            title: "Deliver Now",
            isSelected: isExpanded,
            onTap: () => _switchDeliveryMode('now'),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            _buildPaymentSelector(),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliverLaterSection() {
    final bool isExpanded = _deliveryMode == 'later';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isExpanded ? orangeCardColor : innerFieldColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: outlineColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.schedule_rounded,
            title: "Deliver Later",
            isSelected: isExpanded,
            onTap: () => _switchDeliveryMode('later'),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 16),
            if (_restaurantTiming.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: innerFieldColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: outlineColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, color: buttonColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Operating hours: $_restaurantTiming",
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            _buildPaymentSelector(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: innerFieldColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: buttonColor.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: buttonColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.event_available_rounded, color: buttonColor, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text("Select Delivery Slot", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text("Schedule orders up to 3 days in advance", style: TextStyle(fontSize: 11.5, color: Colors.black54)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAttractiveSlotTile(
                          icon: Icons.calendar_month_rounded,
                          title: "Date",
                          value: _scheduledDate != null ? _formatDate(_scheduledDate!) : "Select Date",
                          isSet: _scheduledDate != null,
                          onTap: _pickScheduleDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildAttractiveSlotTile(
                          icon: Icons.access_time_filled_rounded,
                          title: "Time",
                          value: _scheduledTime != null ? _formatTime(_scheduledTime!) : "Select Time",
                          isSet: _scheduledTime != null,
                          onTap: _pickScheduleTime,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAttractiveSlotTile({
    required IconData icon,
    required String title,
    required String value,
    required bool isSet,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSet ? buttonColor.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSet ? buttonColor : outlineColor,
            width: isSet ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isSet)
              BoxShadow(
                color: buttonColor.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isSet ? buttonColor : Colors.grey[600],
                  ),
                ),
                Icon(
                  icon,
                  size: 16,
                  color: isSet ? buttonColor : Colors.grey[600],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSet ? FontWeight.bold : FontWeight.w500,
                fontSize: 13.5,
                color: isSet ? Colors.black87 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: innerFieldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: outlineColor),
          ),
          child: Column(
            children: [
              _paymentModeTile(icon: Icons.payments_rounded, title: "Cash On Delivery", value: 'COD'),
              const Divider(height: 1, color: outlineColor),
              _paymentModeTile(icon: Icons.account_balance_wallet_rounded, title: "Online Payment", value: 'Online'),
            ],
          ),
        ),
        if (_paymentMode == 'Online') ...[
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: innerFieldColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: outlineColor),
            ),
            child: Column(
              children: [
                _providerTile(provider: 'EasyPaisa', icon: Icons.phone_android_rounded),
                const Divider(height: 1, color: outlineColor),
                _providerTile(provider: 'JazzCash', icon: Icons.smartphone_rounded),
              ],
            ),
          ),
        ],
        if (_selectedProvider != null) ...[
          const SizedBox(height: 14),
          _buildReceiverInfoBanner(),
          const SizedBox(height: 14),
          _buildReceiptUploadUI(),
        ],
      ],
    );
  }

  Widget _paymentModeTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final bool isSelected = _paymentMode == value;
    return InkWell(
      onTap: () => setState(() {
        _paymentMode = value;
        _selectedProvider = null;
        _imageFile = null;
        _transactionIdController.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? buttonColor : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isSelected ? buttonColor : Colors.black87),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? buttonColor : Colors.transparent,
                border: Border.all(color: isSelected ? buttonColor : Colors.black38, width: 2),
              ),
              child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerTile({
    required String provider,
    required IconData icon,
  }) {
    final bool isSelected = _selectedProvider == provider;
    return InkWell(
      onTap: () => setState(() {
        _selectedProvider = provider;
        _imageFile = null;
        _transactionIdController.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? buttonColor : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                provider,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isSelected ? buttonColor : Colors.black87),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? buttonColor : Colors.transparent,
                border: Border.all(color: isSelected ? buttonColor : Colors.black38, width: 2),
              ),
              child: isSelected ? const Icon(Icons.check, size: 12, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiverInfoBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: buttonColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: buttonColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: _loadingManagerPhone
                ? const Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: buttonColor),
                      ),
                      SizedBox(width: 8),
                      Text(
                        "Retrieving account details...",
                        style: TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                    ],
                  )
                : RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                      children: [
                        const TextSpan(text: "Transfer payment via "),
                        TextSpan(text: _selectedProvider ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: " to "),
                        TextSpan(text: _receiverPhone, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const TextSpan(text: " and upload the screenshot."),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptUploadUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: buttonColor, size: 18),
            const SizedBox(width: 8),
            Text(
              "${_selectedProvider ?? 'Payment'} Screenshot",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _isVerifyingImage ? null : _pickReceiptImage,
          child: _imageFile != null
              ? _buildReceiptPreview()
              : _buildReceiptEmptyState(),
        ),
      ],
    );
  }

  Widget _buildReceiptEmptyState() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: buttonColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: buttonColor.withOpacity(0.4), width: 1.5),
      ),
      child: _isVerifyingImage
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(color: buttonColor, strokeWidth: 2.5),
                ),
                SizedBox(height: 12),
                Text(
                  "Verifying screenshot text...",
                  style: TextStyle(color: buttonColor, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [buttonColor.withOpacity(0.2), buttonColor.withOpacity(0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_upload_rounded, size: 28, color: buttonColor),
                ),
                const SizedBox(height: 10),
                Text(
                  "Upload ${_selectedProvider ?? 'Payment'} Screenshot",
                  style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "Only valid ${_selectedProvider ?? ''} receipt allowed",
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                ),
              ],
            ),
    );
  }

  Widget _buildReceiptPreview() {
    return Container(
      height: 160,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: buttonColor.withOpacity(0.3), width: 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_imageFile!, fit: BoxFit.cover),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(0.6)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, size: 14, color: buttonColor),
                  SizedBox(width: 4),
                  Text(
                    "Change Screenshot",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: buttonColor),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: buttonColor, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(int totalItemCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: innerFieldColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Order Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total Items", style: TextStyle(fontSize: 14, color: Colors.black54)),
              Text("$totalItemCount", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Grand Total", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text("RS. ${widget.totalAmount.toStringAsFixed(0)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: buttonColor)),
            ],
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: (_isLoading || _isVerifyingImage) ? null : handleOrderConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _deliveryMode == 'later' ? "Confirm Schedule" : "Place Order",
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}