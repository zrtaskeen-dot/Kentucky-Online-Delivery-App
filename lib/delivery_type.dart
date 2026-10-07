import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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

  // EasyPaisa / JazzCash numbers come from Firestore: payment_method/{branchId}
  // with fields 'easyPaisaNumber' and 'jazzCashNumber'.
  String _easyPaisaNumber = '';
  String _jazzCashNumber = '';
  bool _loadingPaymentNumbers = false;

  // Number to pay, according to the provider the user selected.
  String get _receiverPhone {
    if (_selectedProvider == 'EasyPaisa') return _easyPaisaNumber;
    if (_selectedProvider == 'JazzCash') return _jazzCashNumber;
    return '';
  }

  static const String _cloudinaryUrl =
      "https://api.cloudinary.com/v1_1/dqjqkwwwh/image/upload";
  static const String _receiptUploadPreset = "payment_receipts";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRestaurantTiming();
      _fetchPaymentNumbers();
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

  Future<void> _fetchPaymentNumbers() async {
    setState(() => _loadingPaymentNumbers = true);
    try {
      final branchId = Provider.of<CartProvider>(
        context,
        listen: false,
      ).selectedBranchId;

      if (branchId.isEmpty) {
        if (mounted) setState(() => _loadingPaymentNumbers = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('payment_method')
          .doc(branchId)
          .get();

      if (!mounted) return;
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _easyPaisaNumber = (data['easyPaisaNumber'] ?? '').toString().trim();
          _jazzCashNumber = (data['jazzCashNumber'] ?? '').toString().trim();
          _loadingPaymentNumbers = false;
        });
        return;
      }

      setState(() => _loadingPaymentNumbers = false);
    } catch (e) {
      debugPrint('Failed to fetch payment numbers: $e');
      if (mounted) setState(() => _loadingPaymentNumbers = false);
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
                backgroundColor: Colors.black.withValues(alpha: 0.6),
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

  // Success/error colors match the same scheme used on the sign-up screen
  // (green for success, red for error) so feedback looks consistent across
  // the app. isError defaults to true since most existing call sites here
  // are reporting a validation problem or a failure.
  static const Color _successBorder = Color(0xFF4A7C59);
  static const Color _successBg = Color(0xFFEAF3ED);
  static const Color _successText = Color(0xFF2F5B3E);
  static const Color _errorBorder = Color(0xFFC62828);
  static const Color _errorBg = Color(0xFFFDECEA);
  static const Color _errorText = Color(0xFFB71C1C);

  void _showThemedSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    final borderColor = isError ? _errorBorder : _successBorder;
    final fillColor = isError ? _errorBg : _successBg;
    final textColor = isError ? _errorText : _successText;
    final icon = isError ? Icons.cancel_rounded : Icons.check_circle_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateOptionLabel(DateTime date, DateTime today) {
    final diff = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return "Today";
    if (diff == 1) return "Tomorrow";
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return weekdays[date.weekday - 1];
  }

  // Generates delivery-time slots (every 30 min) within operating hours.
  // Restaurant operating hours as (open, close) TimeOfDay, falling back
  // to a sane default if the fetched timing string can't be parsed.
  (TimeOfDay, TimeOfDay) _operatingHours() {
    TimeOfDay open = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay close = const TimeOfDay(hour: 23, minute: 0);

    if (_restaurantTiming.isNotEmpty &&
        _restaurantTiming.toLowerCase().contains(' to ')) {
      final parts = _restaurantTiming.toLowerCase().split(' to ');
      final o = _parseTimeString(parts[0]);
      final c = _parseTimeString(parts[1]);
      if (o != null && c != null) {
        open = o;
        close = c;
      }
    }
    return (open, close);
  }

  bool _isWithinOperatingHours(TimeOfDay selected) {
    final (open, close) = _operatingHours();
    final int openMins = open.hour * 60 + open.minute;
    int closeMins = close.hour * 60 + close.minute;
    int selectedMins = selected.hour * 60 + selected.minute;

    if (closeMins <= openMins) {
      // Wraps past midnight (e.g. "6 PM to 2 AM").
      closeMins += 24 * 60;
      if (selectedMins < openMins) selectedMins += 24 * 60;
    }
    return selectedMins >= openMins && selectedMins <= closeMins;
  }

  // Custom bottom sheet, styled to match the rest of the app, so the
  // Date/Time pickers no longer look like stock Material dialogs.
  Widget _buildThemedPickerSheet({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: primary.withValues(alpha: 0.15)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(child: child),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerOptionTile({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primary : fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSelected ? primary : Colors.black12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickScheduleDate() async {
    final DateTime today = DateTime.now();
    final DateTime todayDateOnly = DateTime(today.year, today.month, today.day);
    final List<DateTime> options = List.generate(
      4,
      (i) => todayDateOnly.add(Duration(days: i)),
    );

    final DateTime? picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _buildThemedPickerSheet(
          title: "Select Date",
          subtitle: "Schedule up to 3 days ahead",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: options.map((date) {
              final bool isSelected =
                  _scheduledDate != null && _isSameDate(_scheduledDate!, date);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _pickerOptionTile(
                  label: _dateOptionLabel(date, today),
                  subtitle: _formatDate(date),
                  isSelected: isSelected,
                  onTap: () => Navigator.pop(context, date),
                ),
              );
            }).toList(),
          ),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _scheduledDate = picked;
        // The previously picked time was validated against the old
        // date and may now be in the past (or otherwise invalid) for
        // the newly picked date — clear it and make them re-pick.
        _scheduledTime = null;
      });
    }
  }

  Future<void> _pickScheduleTime() async {
    final DateTime baseDate = _scheduledDate ?? DateTime.now();
    final DateTime minAllowed = DateTime.now().add(const Duration(minutes: 90));
    final (openTime, _) = _operatingHours();

    // Sensible starting position for the wheel: the currently picked
    // time if there is one, else opening time — nudged forward to the
    // earliest allowed instant if that falls before it (e.g. today,
    // opening time has already passed).
    DateTime initial = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      (_scheduledTime ?? openTime).hour,
      (_scheduledTime ?? openTime).minute,
    );
    if (initial.isBefore(minAllowed)) initial = minAllowed;

    final TimeOfDay? picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        DateTime dialedTime = initial;
        String? errorText;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _buildThemedPickerSheet(
              title: "Select Time",
              subtitle: _scheduledDate != null
                  ? _formatDate(_scheduledDate!)
                  : null,
              child: Column(
                children: [
                  SizedBox(
                    height: 190,
                    child: CupertinoTheme(
                      data: const CupertinoThemeData(
                        brightness: Brightness.light,
                        textTheme: CupertinoTextThemeData(
                          dateTimePickerTextStyle: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        use24hFormat: false,
                        initialDateTime: dialedTime,
                        onDateTimeChanged: (dt) => setSheetState(() {
                          dialedTime = dt;
                          // Clear a stale error the moment they change
                          // the dial — the old message no longer
                          // necessarily applies to the new value.
                          errorText = null;
                        }),
                      ),
                    ),
                  ),
                  // Shown INSIDE the sheet itself (not a SnackBar) so it
                  // can never end up rendered behind the popup — a
                  // SnackBar anchors to the Scaffold underneath, which
                  // sits below this modal sheet's own overlay layer.
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDECEA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFC62828),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFC62828),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Color(0xFFB71C1C),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final TimeOfDay tod = TimeOfDay(
                          hour: dialedTime.hour,
                          minute: dialedTime.minute,
                        );
                        final DateTime candidate = DateTime(
                          baseDate.year,
                          baseDate.month,
                          baseDate.day,
                          tod.hour,
                          tod.minute,
                        );

                        if (candidate.isBefore(minAllowed)) {
                          setSheetState(
                            () => errorText = "Select time 1.5h+ ahead.",
                          );
                          return;
                        }
                        if (!_isWithinOperatingHours(tod)) {
                          setSheetState(
                            () => errorText = "Outside operating hours.",
                          );
                          return;
                        }
                        Navigator.pop(context, tod);
                      },
                      child: const Text(
                        "Confirm Time",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (picked != null) {
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

      // Sirf isi branch ke items delete karo jahan se order hua; doosri
      // branches ke cart items mehfooz rehte hain.
      final activeBranchId = Provider.of<CartProvider>(
        context,
        listen: false,
      ).selectedBranchId;

      for (final doc in cartDocs.docs) {
        final docBranchId = (doc.data()['branchId'] ?? '').toString();
        if (docBranchId.isEmpty || docBranchId == activeBranchId) {
          await doc.reference.delete();
        }
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
          : (_selectedProvider ?? 'Online Payment');

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
       
        branchId: activeBranchId,
        receiptImageUrl: receiptImageUrl,
      );

      // Keep the user's profile in sync with whatever phone/address they
      // just used at checkout, so Profile always shows the latest values
      // instead of relying on the old "copy from last order" fallback.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'phone': widget.userPhone,
            'address': widget.addressDetails,
            'lat': widget.selectedLocation.latitude,
            'lng': widget.selectedLocation.longitude,
          }, SetOptions(merge: true));
        } catch (e) {
          // Non-fatal: the order itself already succeeded above, so we
          // don't want a profile-sync hiccup to look like a failed order.
          debugPrint('Failed to sync phone/address to profile: $e');
        }
      }

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
                  ? primary.withValues(alpha: 0.15)
                  : primary.withValues(alpha: 0.05),
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
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.access_time_filled_rounded,
                      color: primary,
                      size: 13,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "Hours: $_restaurantTiming",
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
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
                border: Border.all(color: primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.12),
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
          color: isSet ? primary.withValues(alpha: 0.06) : fieldBg,
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
              _onlinePaymentTile(isLaterMode: isLaterMode),
            ],
          ),
        ),
        // Deliver Now still shows who to pay + the receipt upload inline,
        // right below the selector, once a provider's been chosen in the
        // popup. Deliver Later needs neither here — the "pay 1.5h before
        // delivery" note now lives inside the popup itself, and receipt
        // upload happens later from My Orders.
        if (!isLaterMode &&
            _paymentMode == 'Online' &&
            _selectedProvider != null) ...[
          const SizedBox(height: 14),
          _buildReceiverInfoBanner(),
          const SizedBox(height: 14),
          _buildReceiptUploadUI(),
        ],
      ],
    );
  }

  // "Online Payment" no longer selects a provider by itself — tapping it
  // opens the EasyPaisa/JazzCash picker popup instead. The subtitle below
  // the title is the only inline confirmation of which provider is
  // currently chosen, since the tile no longer expands into anything.
  Widget _onlinePaymentTile({required bool isLaterMode}) {
    final bool isSelected = _paymentMode == 'Online';
    return InkWell(
      onTap: () => _openProviderPicker(isLaterMode: isLaterMode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.receipt_long_rounded,
              size: 20,
              color: isSelected ? primary : Colors.black54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Online Payment",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isSelected ? primary : Colors.black87,
                    ),
                  ),
                  if (isSelected && _selectedProvider != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Selected: $_selectedProvider",
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
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

  // Shared popup for both Deliver Now and Deliver Later — EasyPaisa /
  // JazzCash choice. Deliver Later additionally shows the "pay 1.5h
  // before delivery" note at the bottom.
  void _openProviderPicker({required bool isLaterMode}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(sheetContext).padding.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  "Choose Payment Method",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                _providerOptionTile(
                  sheetContext: sheetContext,
                  icon: Icons.phone_android_rounded,
                  title: "EasyPaisa",
                ),
                const SizedBox(height: 10),
                _providerOptionTile(
                  sheetContext: sheetContext,
                  icon: Icons.smartphone_rounded,
                  title: "JazzCash",
                ),
                if (isLaterMode) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: fieldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: primary,
                          size: 15,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You can make the payment 1.5 hours before your "
                            "scheduled delivery time.",
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _providerOptionTile({
    required BuildContext sheetContext,
    required IconData icon,
    required String title,
  }) {
    final bool isSelected = _selectedProvider == title;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          _paymentMode = 'Online';
          _selectedProvider = title;
          _imageFile = null;
          _transactionIdController.clear();
        });
        Navigator.pop(sheetContext);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.08) : fieldBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primary : Colors.black12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? primary : Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
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
        border: Border.all(color: primary.withValues(alpha: 0.3)),
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
                  if (_receiverPhone.isEmpty) return;
                  Clipboard.setData(ClipboardData(text: _receiverPhone));
                  _showThemedSnack("Number copied!", isError: false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.1),
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
          _loadingPaymentNumbers
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                )
              : Text(
                  _receiverPhone.isEmpty
                      ? 'Number not available for ${_selectedProvider ?? 'this method'}'
                      : _receiverPhone,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.black87,
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
        // Container(
        //   margin: const EdgeInsets.only(bottom: 10),
        //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        //   decoration: BoxDecoration(
        //     color: primary.withValues(alpha: 0.06),
        //     borderRadius: BorderRadius.circular(10),
        //     border: Border.all(color: primary.withValues(alpha: 0.25)),
        //   ),
        //   child: const Row(
        //     crossAxisAlignment: CrossAxisAlignment.start,
        //     children: [
        //       Icon(Icons.info_outline_rounded, size: 14, color: primary),
        //       SizedBox(width: 8),
        //       Expanded(
        //         child: Text(
        //           "Please upload a clear payment screenshot with the sender "
        //           "name, phone number, amount, and payment details visible.",
        //           style: TextStyle(
        //             fontSize: 11,
        //             fontWeight: FontWeight.w500,
        //             color: Colors.black87,
        //             height: 1.3,
        //           ),
        //         ),
        //       ),
        //     ],
        //   ),
        // ),
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
        color: primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.4), width: 1.5),
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
                    color: primary.withValues(alpha: 0.1),
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
              border: Border.all(
                color: primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
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
                      color: Colors.black.withValues(alpha: 0.6),
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

  double get _itemsSubtotal => widget.cartItems.fold(
    0.0,
    (sum, item) => sum + (item.price * item.quantity),
  );

  double get _deliveryChargeForDisplay {
    final fee = widget.totalAmount - _itemsSubtotal;
    return fee < 0 ? 0 : fee;
  }

  Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasize ? 15 : 13.5,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
              color: emphasize ? Colors.black87 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 16 : 13.5,
              fontWeight: FontWeight.bold,
              color: emphasize ? primary : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(int totalItemCount) {
    final double itemsTotal = _itemsSubtotal;
    final double deliveryCharge = _deliveryChargeForDisplay;
    // Already the grand total from CartScreen — not recomputed here, so the
    // number the user agreed to at checkout never silently changes.
    final double grandTotal = widget.totalAmount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "Order Summary",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _summaryRow("Total Items", "$totalItemCount"),
          _summaryRow(
            "Delivery Fee",
            deliveryCharge == 0
                ? "FREE"
                : "RS. ${deliveryCharge.toStringAsFixed(0)}",
          ),
          _summaryRow("Subtotal", "RS. ${itemsTotal.toStringAsFixed(0)}"),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: Colors.black12),
          ),
          _summaryRow(
            "Total",
            "RS. ${grandTotal.toStringAsFixed(0)}",
            emphasize: true,
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: (_isLoading || _isVerifyingImage)
                ? null
                : _startOrderReview,
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
                        : "Confirm Order",
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

  void _startOrderReview() {
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

    _showOrderReviewSheet();
  }

  String get _reviewPaymentMethodLabel {
    if (_paymentMode == 'COD') return 'Cash On Delivery';
    return _selectedProvider ?? 'Online Payment';
  }

  String get _reviewDeliveryTimeLabel {
    if (_deliveryMode == 'later' &&
        _scheduledDate != null &&
        _scheduledTime != null) {
      return "${_formatDate(_scheduledDate!)} at ${_formatTime(_scheduledTime!)}";
    }
    return "Standard Delivery";
  }

  void _showOrderReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Row(
                      children: [
                        Text(
                          "Review Your Order",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      children: [
                        if (_deliveryMode != 'later') ...[
                          _reviewWarningBanner(),
                          const SizedBox(height: 18),
                        ],
                        _reviewSectionLabel("Items"),
                        const SizedBox(height: 6),
                        // NOTE: assumes CartItem exposes a `name` getter,
                        // matching how `item.quantity` is already used
                        // elsewhere in this file. Adjust the field name
                        // below if your CartItem model differs.
                        ...widget.cartItems.map(
                          (item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                Text(
                                  "x${item.quantity}",
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(height: 1, color: Colors.black12),
                        ),
                        _reviewSectionLabel("Delivery Address"),
                        const SizedBox(height: 6),
                        Text(
                          widget.addressDetails,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _reviewSectionLabel("Delivery Time"),
                        const SizedBox(height: 6),
                        Text(
                          _reviewDeliveryTimeLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _reviewSectionLabel("Payment Method"),
                        const SizedBox(height: 6),
                        Text(
                          _reviewPaymentMethodLabel,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _reviewSectionLabel("Total"),
                        const SizedBox(height: 6),
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
                  ),
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      MediaQuery.of(context).padding.bottom + 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.black12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: primary),
                              minimumSize: const Size(double.infinity, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Edit Order",
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              handleOrderConfirmation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _deliveryMode == 'later'
                                  ? "Confirm Schedule"
                                  : "Confirm & Place Order",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _reviewSectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.6,
        color: primary,
      ),
    );
  }

  Widget _reviewWarningBanner() {
    const warningBg = Color(0xFFFFF3E0);
    const warningBorder = Color(0xFFFFB74D);
    const warningText = Color(0xFF8A5A00);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warningBorder, width: 1.2),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: warningText, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Once placed, this order cannot be cancelled. Please review "
              "the details below carefully before confirming.",
              style: TextStyle(
                color: warningText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}