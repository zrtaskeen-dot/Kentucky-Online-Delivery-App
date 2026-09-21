import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'cart_provider.dart';
import 'firebase.dart';
import 'order_detail.dart';

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
  static const bgColor = Colors.white;
  static const primary = Color(0xFFA62600);
  static const creamText = Color(0xFFFEF9E7);
  static const fieldBg = Color(0xFFFFFDFA);

  String _deliveryMode = '';
  String _paymentMode = 'COD';
  String? _selectedProvider;

  bool _isLoading = false;
  bool _isVerifyingImage = false;
  String _restaurantTiming = '';

  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  DateTime? get _scheduledDateTime {
    if (_scheduledDate == null || _scheduledTime == null) return null;
    return DateTime(
      _scheduledDate!.year,
      _scheduledDate!.month,
      _scheduledDate!.day,
      _scheduledTime!.hour,
      _scheduledTime!.minute,
    );
  }

  bool get _isScheduledWithinOneAndHalfHours {
    final dt = _scheduledDateTime;
    if (dt == null) return false;
    return dt.difference(DateTime.now()) <= const Duration(minutes: 90);
  }
  // NOTE: retained for potential future use, but no longer drives the
  // receipt-upload flow — Deliver Later now always defers the receipt to
  // the My Orders screen (see handleOrderConfirmation / _buildPaymentSelector).

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _transactionIdController =
      TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();

  String _receiverPhone = "03185940648";
  bool _loadingManagerPhone = false;

  static const String _cloudinaryUrl =
      "https://api.cloudinary.com/v1_1/dqjqkwwwh/image/upload";
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
        final phone = (data['phone'] ?? data['phone_number'] ?? '')
            .toString()
            .trim();
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
    if (_restaurantTiming.isEmpty ||
        !_restaurantTiming.toLowerCase().contains(' to ')) {
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

  Future<bool> _verifyImageWithMLKit(File file, String provider) async {
    setState(() => _isVerifyingImage = true);
    final inputImage = InputImage.fromFile(file);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final RecognizedText recognizedText = await textRecognizer.processImage(
        inputImage,
      );
      final String scannedText = recognizedText.text.toLowerCase();
      await textRecognizer.close();

      bool isValid = false;

      if (provider == 'EasyPaisa') {
        isValid =
            scannedText.contains('easypaisa') ||
            scannedText.contains('easy paisa') ||
            scannedText.contains('telenor microfinance');
      } else if (provider == 'JazzCash') {
        isValid =
            scannedText.contains('jazzcash') ||
            scannedText.contains('jazz cash') ||
            scannedText.contains('mobilink microfinance');
      }

      setState(() => _isVerifyingImage = false);

      if (!isValid) {
        _showThemedSnack("Invalid $provider receipt.");
        return false;
      }

      return true;
    } catch (e) {
      await textRecognizer.close();
      setState(() => _isVerifyingImage = false);
      _showThemedSnack("Screenshot reading failed.");
      return false;
    }
  }

  Future<void> _pickReceiptImage() async {
    if (_selectedProvider == null) {
      _showThemedSnack("Select payment method first.");
      return;
    }

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile == null) return;

      File tempFile = File(pickedFile.path);

      bool isVerified = await _verifyImageWithMLKit(
        tempFile,
        _selectedProvider!,
      );
      if (!isVerified) return;

      setState(() {
        _imageFile = tempFile;
      });
    } catch (e) {
      _showThemedSnack("Image selection failed.");
    }
  }

  void _showFullImageDialog() {
    if (_imageFile == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              clipBehavior: Clip.none,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_imageFile!),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.6),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemedSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickScheduleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 2)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primary,
              onPrimary: creamText,
              surface: bgColor,
              onSurface: Colors.black,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: bgColor),
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
              primary: primary,
              onPrimary: creamText,
              surface: bgColor,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      if (!_isTimeWithinOperatingHours(picked)) {
        _showThemedSnack("Outside operating hours.");
        return;
      }

      final candidateDate = _scheduledDate ?? DateTime.now();
      final candidateDateTime = DateTime(
        candidateDate.year,
        candidateDate.month,
        candidateDate.day,
        picked.hour,
        picked.minute,
      );
      final minAllowedDateTime = DateTime.now().add(
        const Duration(minutes: 90),
      );

      if (candidateDateTime.isBefore(minAllowedDateTime)) {
        _showThemedSnack("Select time 1.5h+ ahead.");
        return;
      }

      setState(() => _scheduledTime = picked);
    }
  }

  String _formatDate(DateTime d) {
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
        ..files.add(
          await http.MultipartFile.fromPath('file', _imageFile!.path),
        );

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
      final userId =
          FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';
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
      _showThemedSnack("Select delivery option.");
      return;
    }

    if (_paymentMode == 'Online' && _selectedProvider == null) {
      _showThemedSnack("Select payment method.");
      return;
    }

    final bool needsReceipt =
        _paymentMode == 'Online' && _deliveryMode != 'later';

    if (needsReceipt && _imageFile == null) {
      _showThemedSnack("Upload receipt screenshot.");
      return;
    }

    if (_deliveryMode == 'later') {
      if (_scheduledDate == null || _scheduledTime == null) {
        _showThemedSnack("Select date and time.");
        return;
      }

      final minAllowedDateTime = DateTime.now().add(
        const Duration(minutes: 90),
      );
      if (_scheduledDateTime != null &&
          _scheduledDateTime!.isBefore(minAllowedDateTime)) {
        _showThemedSnack("Pick time 1.5h+ ahead.");
        return;
      }
    }

    setState(() => _isLoading = true);

    String? receiptImageUrl;
    if (needsReceipt) {
      receiptImageUrl = await _uploadReceiptImage();
      if (receiptImageUrl == null) {
        setState(() => _isLoading = false);
        _showThemedSnack("Receipt upload failed.");
        return;
      }
    }

    try {
      final cartProvider = Provider.of<CartProvider>(context, listen: false);
      String activeBranchId = cartProvider.selectedBranchId;

      String deliveryTimeLabel = "Standard Delivery";
      if (_deliveryMode == 'later' &&
          _scheduledDate != null &&
          _scheduledTime != null) {
        deliveryTimeLabel =
            "${_formatDate(_scheduledDate!)} at ${_formatTime(_scheduledTime!)}";
      }

      final String finalPaymentMethod = _paymentMode == 'COD'
          ? 'Cash On Delivery'
          : (_selectedProvider == 'DeliveryPayment'
                ? 'Delivery Payment (EasyPaisa/JazzCash)'
                : (_selectedProvider ?? 'Online Payment'));

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
        transactionId: _transactionIdController.text.isNotEmpty
            ? _transactionIdController.text
            : "N/A",
        branchId: activeBranchId,
        receiptImageUrl: receiptImageUrl,
      );

      await _clearFirestoreCart();
      if (mounted) {
        cartProvider.clearCart();
      }

      setState(() => _isLoading = false);
      showOrderPopup(
        deliveryTimeLabel,
        newOrderId,
        finalPaymentMethod,
        receiptImageUrl != null,
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showThemedSnack("Order failed.");
    }
  }

  void showOrderPopup(
    String deliveryTimeLabel,
    String orderId,
    String finalPaymentMethod,
    bool receiptUploaded,
  ) {
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
          receiptUploaded: receiptUploaded,
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
    final int totalItemCount = widget.cartItems.fold(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Delivery Options",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
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
              color: isSelected
                  ? primary.withOpacity(0.15)
                  : primary.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? primary : Colors.transparent,
              border: Border.all(
                color: isSelected ? primary : Colors.black45,
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
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
        color: fieldBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isExpanded ? primary : Colors.black12,
          width: isExpanded ? 1.5 : 1.0,
        ),
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
        color: fieldBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isExpanded ? primary : Colors.black12,
          width: isExpanded ? 1.5 : 1.0,
        ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.access_time_filled_rounded,
                      color: primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Hours: $_restaurantTiming",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
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
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          color: primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        "Select Slot",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Schedule up to 3 days",
                    style: TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildAttractiveSlotTile(
                          icon: Icons.calendar_month_rounded,
                          title: "Date",
                          value: _scheduledDate != null
                              ? _formatDate(_scheduledDate!)
                              : "Select Date",
                          isSet: _scheduledDate != null,
                          onTap: _pickScheduleDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildAttractiveSlotTile(
                          icon: Icons.access_time_filled_rounded,
                          title: "Time",
                          value: _scheduledTime != null
                              ? _formatTime(_scheduledTime!)
                              : "Select Time",
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
          color: isSet ? primary.withOpacity(0.06) : fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSet ? primary : Colors.black12,
            width: isSet ? 1.5 : 1.0,
          ),
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
                    color: isSet ? primary : Colors.grey[600],
                  ),
                ),
                Icon(icon, size: 16, color: isSet ? primary : Colors.grey[600]),
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
    final bool isLaterMode = _deliveryMode == 'later';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              _paymentOptionTile(
                icon: Icons.payments_rounded,
                title: "Cash On Delivery",
                value: 'COD',
              ),
              const Divider(height: 1, color: Colors.black12),
              if (isLaterMode)
                // Deliver Later: EasyPaisa/JazzCash are combined into one
                // simple option — the specific screenshot/provider details
                // are handled later from My Orders, not at checkout.
                _paymentOptionTile(
                  icon: Icons.receipt_long_rounded,
                  title: "Delivery Payment",
                  value: 'DeliveryPayment',
                )
              else ...[
                _paymentOptionTile(
                  icon: Icons.phone_android_rounded,
                  title: "EasyPaisa",
                  value: 'EasyPaisa',
                ),
                const Divider(height: 1, color: Colors.black12),
                _paymentOptionTile(
                  icon: Icons.smartphone_rounded,
                  title: "JazzCash",
                  value: 'JazzCash',
                ),
              ],
            ],
          ),
        ),
        if (_selectedProvider != null) ...[
          const SizedBox(height: 14),
          if (isLaterMode)
            _buildScheduledReceiptNotice()
          else ...[
            _buildReceiverInfoBanner(),
            const SizedBox(height: 14),
            _buildReceiptUploadUI(),
          ],
        ],
      ],
    );
  }

  Widget _paymentOptionTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    final bool isSelected = value == 'COD'
        ? _paymentMode == 'COD'
        : _selectedProvider == value;
    return InkWell(
      onTap: () => setState(() {
        _paymentMode = value == 'COD' ? 'COD' : 'Online';
        _selectedProvider = value == 'COD' ? null : value;
        _imageFile = null;
        _transactionIdController.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? primary : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isSelected ? primary : Colors.black87,
                ),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? primary : Colors.black38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiverInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Send to (${_selectedProvider ?? ''})",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _receiverPhone));
                  _showThemedSnack("Number copied!");
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.copy_rounded, size: 14, color: primary),
                      SizedBox(width: 4),
                      Text(
                        "Copy",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _loadingManagerPhone
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                )
              : Text(
                  _receiverPhone,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: Colors.black87,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildScheduledReceiptNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary.withOpacity(0.3)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: primary, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Payment through EasyPaisa or JazzCash.",
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: primary, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Upload receipt 1.5 hours before delivery.",
                  style: TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
              ),
            ],
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
            const Icon(Icons.receipt_long_rounded, color: primary, size: 18),
            const SizedBox(width: 8),
            Text(
              "${_selectedProvider ?? 'Payment'} Screenshot",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _imageFile != null
            ? _buildReceiptPreview()
            : GestureDetector(
                onTap: _isVerifyingImage ? null : _pickReceiptImage,
                child: _buildReceiptEmptyState(),
              ),
      ],
    );
  }

  Widget _buildReceiptEmptyState() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.4), width: 1.5),
      ),
      child: _isVerifyingImage
          ? const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(
                    color: primary,
                    strokeWidth: 2.5,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  "Verifying screenshot...",
                  style: TextStyle(
                    color: primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_rounded,
                    size: 28,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Upload ${_selectedProvider ?? 'Payment'} Receipt",
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Valid ${_selectedProvider ?? ''} receipt only",
                  style: TextStyle(color: Colors.grey[600], fontSize: 11.5),
                ),
              ],
            ),
    );
  }

  Widget _buildReceiptPreview() {
    return Column(
      children: [
        GestureDetector(
          onTap: _showFullImageDialog,
          child: Container(
            height: 160,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primary.withOpacity(0.3), width: 1.5),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_imageFile!, fit: BoxFit.cover),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          "Tap to view",
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickReceiptImage,
            icon: const Icon(Icons.edit_rounded, size: 16, color: primary),
            label: const Text(
              "Change Screenshot",
              style: TextStyle(color: primary, fontSize: 13),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(int totalItemCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Order Summary",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total Items",
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              Text(
                "$totalItemCount",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Grand Total",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                "RS. ${widget.totalAmount.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: (_isLoading || _isVerifyingImage)
                ? null
                : handleOrderConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    _deliveryMode == 'later'
                        ? "Confirm Schedule"
                        : "Place Order",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
