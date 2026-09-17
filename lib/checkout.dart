import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'cart_provider.dart';
import 'delivery_type.dart';

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
  GoogleMapController? _mapController;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  LatLng _pinLatLng = const LatLng(33.6844, 73.0479); // Default: Islamabad
  bool _gpsLoading = false;
  bool _isSearching = false;

  List<Map<String, String>> _predictions = [];
  Timer? _debounce;

  bool _saveInfoForNextTime = false;

  // ────────────────────────────────────────────────────────────
  // 🗺️ DELIVERY ZONE BOUNDARY (Cantt area) — RECTANGLE CORNERS
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

  // 🔑 Google Places API key
  static const String _placesApiKey = 'AIzaSyDDTpx9ZaDEsDzGIOnrsWLQL3vHKz7DZU4';

  // ---- CHANGED: keys are now scoped per logged-in user (uid), so a new
  // account on the same phone never sees a previous account's saved info.
  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  String get _kSaveFlag => 'checkout_save_info_$_uid';
  String get _kFirstName => 'checkout_first_name_$_uid';
  String get _kLastName => 'checkout_last_name_$_uid';
  String get _kPhone => 'checkout_phone_$_uid';
  String get _kAddress => 'checkout_address_$_uid';

  static const bgColor = Colors.white;
  static const primary = Color(0xFFA62600);
  static const creamText = Color(0xFFFEF9E7);
  static const fieldBg = Color(0xFFFFFDFA);

  @override
  void initState() {
    super.initState();
    _loadSavedInfo();
    // Auto-detect the customer's real location on open instead of leaving
    // the pin on the Islamabad fallback until they manually tap GPS.
    _handleGpsSelection(isAutoDetect: true);
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
        _addressCtrl.text = prefs.getString(_kAddress) ?? '';
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
      await prefs.setString(_kAddress, _addressCtrl.text.trim());
    } else {
      await prefs.setBool(_kSaveFlag, false);
      await prefs.remove(_kFirstName);
      await prefs.remove(_kLastName);
      await prefs.remove(_kPhone);
      await prefs.remove(_kAddress);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _updateAddressFromCoordinates(
    double lat,
    double lng, {
    String? userSearchQuery,
  }) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng'
        '&key=$_placesApiKey',
      );

      final res = await http.get(url);
      final data = jsonDecode(res.body);

      String? bestAddress;

      if (data['status'] == 'OK') {
        final results = data['results'] as List;

        // Skip plus_code type results and addresses that match plus_code patterns
        for (final r in results) {
          final formatted = r['formatted_address'] as String? ?? '';
          final types = List<String>.from(r['types'] ?? []);

          final isPlusCode =
              types.contains('plus_code') ||
              RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}').hasMatch(formatted);

          if (isPlusCode) continue;

          bestAddress = formatted;
          break;
        }

        // Fallback to locality/area level address components if no street address is found
        if (bestAddress == null) {
          const preferredTypes = [
            'sublocality_level_1',
            'sublocality',
            'locality',
            'administrative_area_level_2',
            'administrative_area_level_1',
          ];

          for (final r in results) {
            final components = (r['address_components'] as List?) ?? [];
            final parts = <String>[];

            for (final preferred in preferredTypes) {
              for (final c in components) {
                final cTypes = List<String>.from(c['types'] ?? []);
                if (cTypes.contains(preferred)) {
                  final name = c['long_name'] as String?;
                  if (name != null && !parts.contains(name)) parts.add(name);
                  break;
                }
              }
            }

            if (parts.isNotEmpty) {
              bestAddress = parts.join(', ');
              break;
            }
          }
        }
      }

      final String resolvedAddress =
          bestAddress ??
          (userSearchQuery ??
              (_searchCtrl.text.trim().isNotEmpty
                  ? _searchCtrl.text.trim()
                  : 'Selected Location'));

      setState(() {
        // Keep the address field and the search field showing the exact
        // same location so the user never has to update both separately.
        _addressCtrl.text = resolvedAddress;
        _searchCtrl.text = resolvedAddress;
      });
    } catch (_) {
      final fallback = userSearchQuery ?? _searchCtrl.text.trim();
      setState(() {
        _addressCtrl.text = fallback;
        _searchCtrl.text = fallback;
      });
    }
  }

  void _onMapTapped(LatLng position) {
    setState(() {
      _pinLatLng = position;
      _predictions.clear();
    });
    _checkZone();
    _updateAddressFromCoordinates(position.latitude, position.longitude);
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchPredictions(query.trim());
    });
  }

  // Uses the newer Places Autocomplete API so the search is restricted to
  // an exact rectangle (the Cantt zone) instead of the legacy API's
  // circular strictbounds, which could still let outside-zone places in.
  Future<void> _fetchPredictions(String input) async {
    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://places.googleapis.com/v1/places:autocomplete',
      );

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _placesApiKey,
        },
        body: jsonEncode({
          'input': input,
          'includedRegionCodes': ['pk'],
          'locationRestriction': {
            'rectangle': {
              'low': {
                'latitude': _zoneSouthWest.latitude,
                'longitude': _zoneSouthWest.longitude,
              },
              'high': {
                'latitude': _zoneNorthEast.latitude,
                'longitude': _zoneNorthEast.longitude,
              },
            },
          },
        }),
      );

      final data = jsonDecode(res.body);

      // TEMP DEBUG — remove once search is working. Prints the raw
      // response so we can see exactly what Google is rejecting.
      debugPrint('Autocomplete status: ${res.statusCode}');
      debugPrint('Autocomplete body: ${res.body}');

      if (res.statusCode == 200 && data['suggestions'] != null) {
        final results = (data['suggestions'] as List)
            .map<Map<String, String>?>((s) {
              final prediction = s['placePrediction'];
              if (prediction == null) return null;
              return {
                'description': (prediction['text']?['text'] ?? '') as String,
                'place_id': (prediction['placeId'] ?? '') as String,
              };
            })
            .whereType<Map<String, String>>()
            .where((p) => p['place_id']!.isNotEmpty)
            .where((p) => _mentionsWah(p['description']!))
            .toList();

        setState(() {
          _predictions = results;
          _isSearching = false;
        });
      } else {
        setState(() {
          _predictions = [];
          _isSearching = false;
        });
      }
    } catch (_) {
      setState(() {
        _predictions = [];
        _isSearching = false;
      });
    }
  }

  // Belt-and-suspenders filter on top of locationRestriction — some
  // well-known place names can still slip past the rectangle bound, so
  // this drops any prediction whose text doesn't actually mention Wah.
  // Uses a word boundary so it won't false-match things like "Wahdat".
  bool _mentionsWah(String description) {
    return RegExp(r'\bwah\b', caseSensitive: false).hasMatch(description);
  }

  Future<void> _selectPrediction(Map<String, String> prediction) async {
    FocusScope.of(context).unfocus();
    final selectedDescription = prediction['description'] ?? '';

    setState(() {
      _predictions = [];
      _searchCtrl.text = selectedDescription;
      _isSearching = true;
    });

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${prediction['place_id']}'
        '&fields=geometry,formatted_address'
        '&key=$_placesApiKey',
      );

      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (data['status'] == 'OK') {
        final loc = data['result']['geometry']['location'];
        final target = LatLng(loc['lat'], loc['lng']);

        // Prefer the full, proper address from Place Details
        // (formatted_address) over the short autocomplete description,
        // so the field shows a complete address rather than just a
        // place/area name. Fall back to the description only if Google
        // didn't return a formatted address at all.
        final String? formattedAddress =
            data['result']['formatted_address'] as String?;
        final String finalAddress =
            (formattedAddress != null && formattedAddress.trim().isNotEmpty)
            ? formattedAddress
            : (selectedDescription.isNotEmpty
                  ? selectedDescription
                  : 'Selected Location');

        setState(() {
          _pinLatLng = target;
          // Keep both fields showing the exact same resolved location.
          _addressCtrl.text = finalAddress;
          _searchCtrl.text = finalAddress;
          _isSearching = false;
        });

        _checkZone();

        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.0));
      } else {
        setState(() => _isSearching = false);
        _snack('Could not fetch that location. Please try again.');
      }
    } catch (_) {
      setState(() => _isSearching = false);
      _snack(
        'Could not fetch that location. Please check your internet connection.',
      );
    }
  }

  // Handles the case where the user types an address and hits
  // search/enter instead of tapping a suggestion from the dropdown.
  // If suggestions are already showing, the top one is used (same
  // outcome as tapping it). Otherwise we forward-geocode whatever text
  // they typed so the map still moves to match the search field.
  Future<void> _handleSearchSubmit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    FocusScope.of(context).unfocus();

    if (_predictions.isNotEmpty) {
      await _selectPrediction(_predictions.first);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(trimmed)}'
        '&region=pk'
        '&key=$_placesApiKey',
      );

      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
        final result = data['results'][0];
        final loc = result['geometry']['location'];
        final target = LatLng(loc['lat'], loc['lng']);
        final String fullAddress =
            (result['formatted_address'] as String?) ?? trimmed;

        setState(() {
          _pinLatLng = target;
          _addressCtrl.text = fullAddress;
          _searchCtrl.text = fullAddress;
          _isSearching = false;
        });

        _checkZone();
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.0));
      } else {
        setState(() => _isSearching = false);
        _snack(
          'Could not find that location. Please try selecting from the suggestions.',
        );
      }
    } catch (_) {
      setState(() => _isSearching = false);
      _snack(
        'Could not fetch that location. Please check your internet connection.',
      );
    }
  }

  Future<void> _handleGpsSelection({bool isAutoDetect = false}) async {
    setState(() => _gpsLoading = true);

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        // On the silent auto-detect we just fall back to the default pin
        // instead of interrupting the user with a snackbar right away.
        if (!isAutoDetect) {
          _snack('Location permission denied. Please allow it from settings.');
        }
        setState(() => _gpsLoading = false);
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!isAutoDetect) {
          _snack('Please enable GPS/location services.');
        }
        setState(() => _gpsLoading = false);
        return;
      }

      // 👈 FIX: 'high' can still return a fix that's 50-100m off,
      // especially indoors/inside large buildings like a college campus
      // (GPS signals bounce off walls, sometimes landing on the nearest
      // road instead of the actual building). 'best' asks the device to
      // try harder for precision before returning a result.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final newLatLng = LatLng(pos.latitude, pos.longitude);
      await _updateAddressFromCoordinates(pos.latitude, pos.longitude);

      setState(() {
        _pinLatLng = newLatLng;
        _gpsLoading = false;
      });

      _checkZone();

      // 👈 NEW: pos.accuracy is the GPS fix's margin of error in meters.
      // When it's poor (common indoors/inside campuses), nudge the
      // customer to check the pin themselves — it's already draggable
      // and tappable, they just need a reason to double-check it instead
      // of trusting a GPS fix that silently landed on the wrong building.
      if (pos.accuracy > 30) {
        _snack(
          'GPS signal is weak here — please check the pin is on the '
          'right spot and drag it if needed.',
        );
      }

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(newLatLng, 17.0),
      );
    } catch (_) {
      setState(() => _gpsLoading = false);
      if (!isAutoDetect) {
        _snack('Failed to get GPS location.');
      }
    }
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
      _snack('Please enter or confirm your complete delivery address.');
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
            _buildMapSection(),
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

  Widget _buildMapSection() {
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pinLatLng,
              zoom: 15.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              // In case GPS already resolved before the map finished
              // loading, make sure the camera reflects the current pin
              // instead of staying on the initial default.
              controller.animateCamera(
                CameraUpdate.newLatLngZoom(_pinLatLng, 15.0),
              );
            },
            onTap: _onMapTapped,
            markers: {
              Marker(
                markerId: const MarkerId('selected_delivery_location'),
                position: _pinLatLng,
                draggable: true,
                onDragEnd: (newPosition) => _onMapTapped(newPosition),
                infoWindow: const InfoWindow(title: 'Delivery Location'),
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Search Bar
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  elevation: 4,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            textInputAction: TextInputAction.search,
                            onChanged: _onSearchChanged,
                            onSubmitted: _handleSearchSubmit,
                            style: const TextStyle(fontSize: 13.5),
                            decoration: InputDecoration(
                              hintText: 'Search street, area, or sector...',
                              border: InputBorder.none,
                              hintStyle: const TextStyle(fontSize: 13),
                              isDense: true,
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _predictions.clear());
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        if (_isSearching)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // ---- CHANGED: predictions dropdown now matches the
                // search field's white background (was fieldBg cream) ----
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _predictions.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _predictions[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.location_on_rounded,
                            color: primary,
                            size: 18,
                          ),
                          title: Text(
                            item['description'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => _selectPrediction(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // "Use My Location" GPS button
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'gps_btn',
              backgroundColor: primary,
              onPressed: _gpsLoading ? null : _handleGpsSelection,
              child: _gpsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: creamText,
                      ),
                    )
                  : const Icon(
                      Icons.my_location_rounded,
                      color: creamText,
                      size: 20,
                    ),
            ),
          ),

          // Out-of-zone banner
          if (!_isInZone)
            Positioned(
              bottom: 12,
              left: 12,
              right: 70,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'We only deliver within the Cantt area.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
          'Address auto-fills from map/GPS — you can edit it if needed.',
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
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _lastNameCtrl,
                'Last Name',
                Icons.person_outline,
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
