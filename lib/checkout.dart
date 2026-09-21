import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'cart_provider.dart';
import 'delivery_type.dart';
import 'location_picker.dart';

// Capitalizes the first letter of every word as the user types, and
// lower-cases the rest of that word (so "ALI" -> "Ali", "aLi" -> "Ali").
// Keeps the cursor exactly where it was, including mid-word edits.
class CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;

    for (int i = 0; i < newValue.text.length; i++) {
      final ch = newValue.text[i];
      if (ch.trim().isEmpty) {
        // whitespace — reset so the next letter typed is capitalized
        buffer.write(ch);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(ch.toLowerCase());
      }
    }

    return newValue.copyWith(
      text: buffer.toString(),
      selection: newValue.selection,
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  final double totalAmount;
  final List<CartItem> cartItems;
  final String branchId;
  final String? userEmail;

  const CheckoutScreen({
    super.key,
    required this.totalAmount,
    required this.cartItems,
    required this.branchId,
    this.userEmail,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutLocationScreenState();
}

class _CheckoutLocationScreenState extends State<CheckoutScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  // 👈 FIXED: this is now latlong2's LatLng (same type LocationPickerScreen
  // and DeliveryScreen use), instead of google_maps_flutter's LatLng.
  // Those were two different classes with the same name, which caused a
  // type-mismatch error when passing _pinLatLng into LocationPickerScreen.
  LatLng _pinLatLng = const LatLng(33.6844, 73.0479); // Default: Islamabad
  bool _saveInfoForNextTime = false;
  bool _locationLoading = true;

  // ────────────────────────────────────────────────────────────
  // 🗺️ DELIVERY ZONE BOUNDARY (Cantt area) — RECTANGLE CORNERS
  // Kept here too (in addition to LocationPickerScreen) purely as a
  // final safety check before Proceed — the picker itself already
  // blocks confirming a location outside this rectangle.
  // ────────────────────────────────────────────────────────────
  static const LatLng _zoneSouthWest = LatLng(33.7377237, 72.7183126);
  static const LatLng _zoneNorthEast = LatLng(33.8020805, 72.79845700000001);

  bool _isInZone = true;

  bool _isWithinDeliveryZone(LatLng point) {
    return point.latitude >= _zoneSouthWest.latitude &&
        point.latitude <= _zoneNorthEast.latitude &&
        point.longitude >= _zoneSouthWest.longitude &&
        point.longitude <= _zoneNorthEast.longitude;
  }

  void _checkZone() {
    final withinZone = _isWithinDeliveryZone(_pinLatLng);
    if (withinZone != _isInZone) {
      setState(() => _isInZone = withinZone);
    }
  }

  // ---- keys are scoped per logged-in user (uid), so a new account on
  // the same phone never sees a previous account's saved info.
  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  String get _kSaveFlag => 'checkout_save_info_$_uid';
  String get _kFirstName => 'checkout_first_name_$_uid';
  String get _kLastName => 'checkout_last_name_$_uid';
  String get _kPhone => 'checkout_phone_$_uid';

  static const bgColor = Colors.white;
  static const primary = Color(0xFFA70000);
  static const creamText = Colors.white;
  static const fieldBg = Color(0xFFFFFDFA);

  @override
  void initState() {
    super.initState();
    _loadSavedInfo();
    _loadSavedLocation();
  }

  Future<void> _loadSavedInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kSaveFlag) ?? false;

    if (saved) {
      setState(() {
        _saveInfoForNextTime = true;
        _firstNameCtrl.text = prefs.getString(_kFirstName) ?? '';
        _lastNameCtrl.text = prefs.getString(_kLastName) ?? '';
        _phoneCtrl.text = prefs.getString(_kPhone) ?? '';
      });
    }
  }

  Future<void> _persistInfoIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    if (_saveInfoForNextTime) {
      await prefs.setBool(_kSaveFlag, true);
      await prefs.setString(_kFirstName, _firstNameCtrl.text.trim());
      await prefs.setString(_kLastName, _lastNameCtrl.text.trim());
      await prefs.setString(_kPhone, _phoneCtrl.text.trim());
    } else {
      await prefs.setBool(_kSaveFlag, false);
      await prefs.remove(_kFirstName);
      await prefs.remove(_kLastName);
      await prefs.remove(_kPhone);
    }
  }

  // ────────────────────────────────────────────────────────────
  // 📍 DELIVERY LOCATION — now backed by Firestore instead of the old
  // in-screen Places search (which was failing). The full picker UI
  // lives in LocationPickerScreen; this screen just shows the result
  // and remembers it.
  // ────────────────────────────────────────────────────────────

  Future<void> _loadSavedLocation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('delivery_locations')
          .doc(_uid)
          .get();

      final data = doc.data();
      if (doc.exists && data != null) {
        final lat = (data['latitude'] as num?)?.toDouble();
        final lng = (data['longitude'] as num?)?.toDouble();
        final address = data['address'] as String?;

        if (lat != null &&
            lng != null &&
            address != null &&
            address.trim().isNotEmpty) {
          setState(() {
            _pinLatLng = LatLng(lat, lng);
            _addressCtrl.text = address;
            _locationLoading = false;
          });
          _checkZone();
          return;
        }
      }
    } catch (e) {
      debugPrint('Failed to load saved delivery location: $e');
    }

    // No saved location yet — open the map picker right away so the
    // customer chooses one before filling in the rest of the form.
    setState(() => _locationLoading = false);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openLocationPicker();
      });
    }
  }

  Future<void> _saveLocationToFirestore(
    String address,
    double lat,
    double lng,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('delivery_locations')
          .doc(_uid)
          .set({
            'address': address,
            'latitude': lat,
            'longitude': lng,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Failed to save delivery location: $e');
    }
  }

  Future<void> _openLocationPicker() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLatLng: _pinLatLng),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _pinLatLng = LatLng(result.latitude, result.longitude);
      _addressCtrl.text = result.address;
    });
    _checkZone();

    await _saveLocationToFirestore(
      result.address,
      result.latitude,
      result.longitude,
    );
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _proceedToDeliveryScreen() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final phoneRegExp = RegExp(r'^[0-9]{11}$');

    if (firstName.isEmpty || lastName.isEmpty) {
      _snack('Please enter your First and Last Name.');
      return;
    }
    if (phone.isEmpty || !phoneRegExp.hasMatch(phone)) {
      _snack('Phone number must be exactly 11 digits (e.g. 03001234567).');
      return;
    }
    if (address.isEmpty) {
      _snack('Please choose your delivery location on the map.');
      return;
    }
    if (!_isInZone) {
      _snack('Sorry, this branch only delivers within the Cantt area.');
      return;
    }

    await _persistInfoIfNeeded();

    final fullName = '$firstName $lastName';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryScreen(
          userName: fullName,
          userPhone: phone,
          selectedLocation: latlong.LatLng(
            _pinLatLng.latitude,
            _pinLatLng.longitude,
          ),
          addressDetails: address,
          totalAmount: widget.totalAmount,
          cartItems: widget.cartItems,
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: primary));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 2,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: creamText,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Delivery Details',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: creamText,
            fontSize: 19,
            letterSpacing: 0.5,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLocationCard(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildFormSection(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildProceedButton(),
    );
  }

  Widget _buildLocationCard() {
    final hasAddress = _addressCtrl.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fieldBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivery Location',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _locationLoading
                        ? 'Loading your saved location...'
                        : (hasAddress
                              ? _addressCtrl.text.trim()
                              : 'No location selected yet'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  if (!_locationLoading && !_isInZone) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'This location is outside our delivery zone.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _openLocationPicker,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                hasAddress ? 'Change' : 'Choose',
                style: const TextStyle(
                  color: primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery Address & Contact',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Address is set from the map above — you can fine-tune it here if needed.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),

        _buildTextField(
          _addressCtrl,
          'Address (Manually Editable)',
          Icons.home_work_rounded,
          maxLines: 2,
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _firstNameCtrl,
                'First Name',
                Icons.person,
                capitalizeWords: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _lastNameCtrl,
                'Last Name',
                Icons.person_outline,
                capitalizeWords: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        _buildTextField(
          _phoneCtrl,
          'Phone Number (03001234567)',
          Icons.phone_android,
          keyboardType: TextInputType.phone,
          maxLength: 11,
        ),
        const SizedBox(height: 8),

        InkWell(
          onTap: () =>
              setState(() => _saveInfoForNextTime = !_saveInfoForNextTime),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: _saveInfoForNextTime,
                  activeColor: primary,
                  onChanged: (val) =>
                      setState(() => _saveInfoForNextTime = val ?? false),
                ),
                const Expanded(
                  child: Text(
                    'Save info for next time',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool readOnly = false,
    int maxLines = 1,
    bool capitalizeWords = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        readOnly: readOnly,
        maxLines: maxLines,
        // Auto-capitalizes the first letter of each word as the user
        // types (e.g. "ali khan" -> "Ali Khan"). textCapitalization only
        // switches the on-screen keyboard's shift state; the formatter
        // is what actually enforces it in the text itself, including
        // pasted text or a hardware keyboard.
        textCapitalization: capitalizeWords
            ? TextCapitalization.words
            : TextCapitalization.none,
        inputFormatters: capitalizeWords ? [CapitalizeWordsFormatter()] : null,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          counterText: "",
          prefixIcon: Icon(icon, color: primary, size: 22),
          filled: true,
          fillColor: readOnly ? Colors.grey.shade200 : fieldBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black26, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black26, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.black87, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildProceedButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.transparent,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _proceedToDeliveryScreen,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Proceed to Order',
            style: TextStyle(
              color: creamText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}