import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'cart_provider.dart';
import 'delivery_type.dart';

// NOTE: `latlong2`'s LatLng is kept only because DeliveryScreen (and other
// downstream screens not shown here) expect `selectedLocation` in that
// type. All actual map rendering, search, and geocoding now goes through
// google_maps_flutter / Google's HTTP APIs — see _toGmaps/_fromGmaps below.

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

class _PlaceSuggestion {
  final String description;
  final String placeId;

  _PlaceSuggestion({required this.description, required this.placeId});
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
  // Replace with your real key, ideally loaded from --dart-define rather
  // than hardcoded here.
  //
  // IMPORTANT: this key is used for raw REST calls (Places Autocomplete,
  // Place Details, Geocoding) below via http.get — NOT through the native
  // Maps SDK. If this key has an "Android apps" or "iOS apps" application
  // restriction in Google Cloud Console, these REST calls will silently
  // get REQUEST_DENIED: that restriction only works for requests made by
  // the native SDK (which attaches special headers), not for a plain
  // http.get from Dart. Either use a separate key with no app restriction
  // (or restrict it by API instead) for these calls, or keep this one
  // restriction-free, and make sure Places API + Geocoding API are both
  // enabled for it — see _decodeGoogleResponse below, which now logs the
  // real reason whenever Google rejects a request.
  static const String _googleApiKey = 'AIzaSyDDTpx9ZaDEsDzGIOnrsWLQL3vHKz7DZU4';

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();

  // Search bar that sits on top of the map. Fully separate from
  // _addressCtrl — this is the only place suggestions/loading show up.
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<_PlaceSuggestion> _suggestions = [];
  bool _searchingSuggestions = false;
  Timer? _debounce;
  String _sessionToken = '';

  gmaps.GoogleMapController? _mapController;

  LatLng _pinLatLng = const LatLng(33.6844, 73.0479); // Default: Islamabad

  gmaps.LatLng _toGmaps(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);
  LatLng _fromGmaps(gmaps.LatLng p) => LatLng(p.latitude, p.longitude);
  bool _saveInfoForNextTime = false;
  bool _locationLoading = true;
  bool _fetchingCurrentLocation = false;
  bool _isInZone = true;

  static const LatLng _zoneSouthWest = LatLng(33.7377237, 72.7183126);
  static const LatLng _zoneNorthEast = LatLng(33.8020805, 72.79845700000001);

  static const bgColor = Colors.white;
  static const primary = Color(0xFFA70000);
  static const creamText = Colors.white;
  static const fieldBg = Color(0xFFFFFDFA);

  bool _isWithinDeliveryZone(LatLng point) {
    return point.latitude >= _zoneSouthWest.latitude &&
        point.latitude <= _zoneNorthEast.latitude &&
        point.longitude >= _zoneSouthWest.longitude &&
        point.longitude <= _zoneNorthEast.longitude;
  }

  // Center + radius of the delivery zone, used to hard-restrict place
  // search (autocomplete) results to only the Cantt area instead of just
  // "biasing" toward it. Computed once from the existing zone bounds.
  static final LatLng _zoneCenter = LatLng(
    (_zoneSouthWest.latitude + _zoneNorthEast.latitude) / 2,
    (_zoneSouthWest.longitude + _zoneNorthEast.longitude) / 2,
  );

  static final double _zoneRadiusMeters = _distanceMeters(
    _zoneCenter,
    _zoneNorthEast,
  );

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  void _checkZone() {
    final withinZone = _isWithinDeliveryZone(_pinLatLng);
    if (withinZone != _isInZone) {
      setState(() => _isInZone = withinZone);
    }
  }

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid ?? 'guest_user_test';

  String get _kSaveFlag => 'checkout_save_info_$_uid';
  String get _kFirstName => 'checkout_first_name_$_uid';
  String get _kLastName => 'checkout_last_name_$_uid';
  String get _kPhone => 'checkout_phone_$_uid';
  String get _kAddress => 'checkout_address_$_uid';
  String get _kLat => 'checkout_lat_$_uid';
  String get _kLng => 'checkout_lng_$_uid';

  @override
  void initState() {
    super.initState();
    _newSessionToken();
    _loadSavedInfo();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _addressFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _newSessionToken() {
    _sessionToken = DateTime.now().microsecondsSinceEpoch.toString();
  }

  // Every Google Maps REST response is HTTP 200 even when the request was
  // rejected — the actual outcome is in the "status" field. Both reported
  // bugs (no suggestions, no address on tap) came from that status never
  // being checked, so a REQUEST_DENIED/INVALID_REQUEST looked identical to
  // "no results." This surfaces it instead of swallowing it.
  Map<String, dynamic> _decodeGoogleResponse(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
      debugPrint(
        'Google Maps API error ($status): '
        '${data['error_message'] ?? 'no error_message in response'}. '
        'Check that Places API and Geocoding API are both enabled for '
        '_googleApiKey, and that the key has no Android/iOS app '
        'restriction (see the comment on _googleApiKey above).',
      );
    }
    return data;
  }

  // Delivery location is no longer persisted to its own Firestore
  // collection. It only ever gets written to Firestore once, as part of
  // the order document itself (see FirestoreService.saveOrder). For the
  // "remember this for next time" convenience we reuse the same
  // SharedPreferences mechanism as the name/phone fields.
  Future<void> _loadSavedInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kSaveFlag) ?? false;

    if (saved) {
      final lat = prefs.getDouble(_kLat);
      final lng = prefs.getDouble(_kLng);
      final address = prefs.getString(_kAddress);

      setState(() {
        _saveInfoForNextTime = true;
        _firstNameCtrl.text = prefs.getString(_kFirstName) ?? '';
        _lastNameCtrl.text = prefs.getString(_kLastName) ?? '';
        _phoneCtrl.text = prefs.getString(_kPhone) ?? '';

        if (lat != null &&
            lng != null &&
            address != null &&
            address.trim().isNotEmpty) {
          _pinLatLng = LatLng(lat, lng);
          _setAddressSilently(address);
        }
      });
      _checkZone();
    }

    setState(() => _locationLoading = false);
  }

  Future<void> _persistInfoIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    if (_saveInfoForNextTime) {
      await prefs.setBool(_kSaveFlag, true);
      await prefs.setString(_kFirstName, _firstNameCtrl.text.trim());
      await prefs.setString(_kLastName, _lastNameCtrl.text.trim());
      await prefs.setString(_kPhone, _phoneCtrl.text.trim());
      await prefs.setString(_kAddress, _addressCtrl.text.trim());
      await prefs.setDouble(_kLat, _pinLatLng.latitude);
      await prefs.setDouble(_kLng, _pinLatLng.longitude);
    } else {
      await prefs.setBool(_kSaveFlag, false);
      await prefs.remove(_kFirstName);
      await prefs.remove(_kLastName);
      await prefs.remove(_kPhone);
      await prefs.remove(_kAddress);
      await prefs.remove(_kLat);
      await prefs.remove(_kLng);
    }
  }

  void _setAddressSilently(String address) {
    if (!mounted) return;
    setState(() => _addressCtrl.text = address);
  }

  void _onSearchChanged() {
    _debounce?.cancel();

    final query = _searchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query);
    });
  }

  // Two parallel autocomplete calls: `establishment` surfaces named
  // places (shops, restaurants, landmarks) which usually resolve to a
  // precise pin, while `geocode` still covers plain street addresses
  // that `establishment` alone would drop. Results are merged and
  // de-duplicated by place_id, establishments listed first so the more
  // precise matches show up before generic road/area results.
  Future<void> _fetchSuggestions(String query) async {
    setState(() => _searchingSuggestions = true);
    try {
      final baseParams = {
        'input': query,
        'key': _googleApiKey,
        'sessiontoken': _sessionToken,
        'location': '${_zoneCenter.latitude},${_zoneCenter.longitude}',
        'radius': _zoneRadiusMeters.toStringAsFixed(0),
        // Without this, location+radius are only a *bias* — results
        // outside the Cantt zone still show up. strictbounds forces
        // Google to only return results inside that circle.
        'strictbounds': 'true',
      };

      final establishmentUri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {...baseParams, 'types': 'establishment'},
      );
      final addressUri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {...baseParams, 'types': 'geocode'},
      );

      final responses = await Future.wait([
        http.get(establishmentUri),
        http.get(addressUri),
      ]);

      final establishmentData = _decodeGoogleResponse(responses[0]);
      final addressData = _decodeGoogleResponse(responses[1]);

      final establishmentPredictions =
          (establishmentData['predictions'] as List?) ?? [];
      final addressPredictions = (addressData['predictions'] as List?) ?? [];

      final seenIds = <String>{};
      final merged = <_PlaceSuggestion>[];
      for (final p in [...establishmentPredictions, ...addressPredictions]) {
        final id = p['place_id'] as String;
        if (seenIds.add(id)) {
          merged.add(
            _PlaceSuggestion(
              description: p['description'] as String,
              placeId: id,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() => _suggestions = merged.take(8).toList());
    } catch (e) {
      debugPrint('Failed to fetch address suggestions: $e');
    } finally {
      if (mounted) setState(() => _searchingSuggestions = false);
    }
  }

  // Google's Geocoding API often returns a Plus Code ("QWC+M73...") as the
  // very first result for places without precise street-level data, which
  // is what was showing up in the Address field. This picks the first
  // result that ISN'T a plus code, falling back to the plus code only if
  // that's genuinely all Google has for that spot.
  String? _bestFormattedAddress(List results) {
    if (results.isEmpty) return null;
    for (final r in results) {
      final types = (r['types'] as List?)?.cast<String>() ?? const [];
      if (!types.contains('plus_code')) {
        final addr = r['formatted_address'] as String?;
        if (addr != null && addr.trim().isNotEmpty) return addr;
      }
    }
    return results.first['formatted_address'] as String?;
  }

  // Triggered when the user submits the search bar (presses enter/search)
  // without tapping one of the autocomplete suggestions — a plain
  // forward-geocode of whatever they typed.
  Future<void> _searchAndMoveTo(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _searchingSuggestions = true);
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': query,
        'key': _googleApiKey,
        // Geocoding API can only "bias" toward this box, it can't hard
        // restrict like autocomplete's strictbounds can — so we still
        // check the result against the zone below.
        'bounds':
            '${_zoneSouthWest.latitude},${_zoneSouthWest.longitude}|'
            '${_zoneNorthEast.latitude},${_zoneNorthEast.longitude}',
      });

      final response = await http.get(uri);
      final data = _decodeGoogleResponse(response);
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty || !mounted) {
        final status = data['status'] as String?;
        if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
          _snack('Search failed — please try again in a moment.');
        }
        return;
      }

      final location = results.first['geometry']['location'] as Map;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final address = _bestFormattedAddress(results) ?? query;
      final point = LatLng(lat, lng);

      if (!_isWithinDeliveryZone(point)) {
        _snack('That address is outside our delivery zone (Cantt area).');
        return;
      }

      _movePin(point, address: address);
      _searchCtrl.clear();
      _searchFocus.unfocus();
    } catch (e) {
      debugPrint('Failed to geocode typed address: $e');
    } finally {
      if (mounted) setState(() => _searchingSuggestions = false);
    }
  }

  // Builds the address to fill into the Address field after a suggestion
  // is tapped. Place Details' `formatted_address` sometimes drops the
  // place's own name (e.g. a shop/landmark name), which is what made the
  // filled-in address look shorter/incomplete than the suggestion the
  // user actually picked. We prepend the place `name` when it's missing
  // from the formatted address, and fall back to the original dropdown
  // text if Place Details still returns something shorter than that.
  Future<void> _selectSuggestion(_PlaceSuggestion suggestion) async {
    setState(() => _suggestions = []);
    FocusScope.of(context).unfocus();

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': suggestion.placeId,
          'key': _googleApiKey,
          'sessiontoken': _sessionToken,
          // added 'name' so we can prepend the place name when
          // formatted_address leaves it out
          'fields': 'geometry,formatted_address,address_components,types,name',
        },
      );

      final response = await http.get(uri);
      final data = _decodeGoogleResponse(response);
      final result = data['result'] as Map<String, dynamic>?;
      final location =
          result?['geometry']?['location'] as Map<String, dynamic>?;
      if (location == null) return;

      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final types = (result?['types'] as List?)?.cast<String>() ?? const [];
      final rawAddress = result?['formatted_address'] as String?;
      final placeName = result?['name'] as String?;

      String address;
      if (rawAddress != null && !types.contains('plus_code')) {
        final alreadyHasName =
            placeName != null &&
            rawAddress.toLowerCase().contains(placeName.toLowerCase());
        address = (placeName != null && !alreadyHasName)
            ? '$placeName, $rawAddress'
            : rawAddress;
      } else {
        address = suggestion.description;
      }

      // Safety net: never end up with less text than what the dropdown
      // already showed and the user tapped on.
      if (suggestion.description.length > address.length) {
        address = suggestion.description;
      }

      _movePin(LatLng(lat, lng), address: address);
      _newSessionToken();
      _searchCtrl.clear();
    } catch (e) {
      debugPrint('Failed to fetch place details: $e');
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${point.latitude},${point.longitude}',
        'key': _googleApiKey,
      });

      final response = await http.get(uri);
      final data = _decodeGoogleResponse(response);
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty) {
        final status = data['status'] as String?;
        if (status != null && status != 'OK' && status != 'ZERO_RESULTS') {
          _snack('Could not look up the address for that point.');
        }
        return;
      }

      final address = _bestFormattedAddress(results);
      if (address != null) _setAddressSilently(address);
    } catch (e) {
      debugPrint('Failed to reverse geocode location: $e');
    }
  }

  void _movePin(LatLng point, {String? address}) {
    setState(() {
      _pinLatLng = point;
      _suggestions = [];
    });
    if (address != null) _setAddressSilently(address);
    _mapController?.animateCamera(
      gmaps.CameraUpdate.newLatLng(_toGmaps(point)),
    );
    _checkZone();
  }

  void _onMapTap(gmaps.LatLng gPoint) {
    final point = _fromGmaps(gPoint);
    setState(() => _pinLatLng = point);
    _checkZone();
    _reverseGeocode(point);
  }

  // "Use my current location" — always asks first, in plain language,
  // before triggering the OS permission prompt (and again points the user
  // to Settings if they've permanently denied it before).
  Future<void> _useCurrentLocation() async {
    final wantsToShare = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use your current location?'),
        content: const Text(
          'We need access to your device location to set your delivery '
          'address automatically. You can still adjust it on the map '
          'afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (wantsToShare != true || !mounted) return;

    setState(() => _fetchingCurrentLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('Please turn on Location Services to use this.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _snack('Location permission was denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _snack('Location permission is disabled. Enable it from Settings.');
        await Geolocator.openAppSettings();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final point = LatLng(position.latitude, position.longitude);
      _movePin(point);
      await _reverseGeocode(point);
    } catch (e) {
      debugPrint('Failed to fetch current location: $e');
      _snack('Could not fetch your current location.');
    } finally {
      if (mounted) setState(() => _fetchingCurrentLocation = false);
    }
  }

  void _proceedToDeliveryScreen() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final phoneDigits = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final phoneRegExp = RegExp(r'^[0-9]{10}$');

    if (firstName.isEmpty || lastName.isEmpty) {
      _snack('Please enter your First and Last Name.');
      return;
    }
    if (phoneDigits.isEmpty || !phoneRegExp.hasMatch(phoneDigits)) {
      _snack('Phone number must be exactly 10 digits (e.g. 3001234567).');
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
    final fullPhone = '+92$phoneDigits';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryScreen(
          userName: fullName,
          userPhone: fullPhone,
          selectedLocation: LatLng(_pinLatLng.latitude, _pinLatLng.longitude),
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
      // The map is a sibling of the scroll view, not a child inside it —
      // if it were nested inside the SingleChildScrollView below, the
      // outer scroll would keep stealing the pan/pinch gestures meant for
      // the map, which is why zooming wasn't working before.
      body: Column(
        children: [
          _buildMap(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_locationLoading && !_isInZone) _buildZoneWarning(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildFormSection(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildProceedButton(),
    );
  }

  Widget _buildMap() {
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          gmaps.GoogleMap(
            initialCameraPosition: gmaps.CameraPosition(
              target: _toGmaps(_pinLatLng),
              zoom: 15,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _onMapTap,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            zoomGesturesEnabled: true,
            mapToolbarEnabled: false,
            markers: {
              gmaps.Marker(
                markerId: const gmaps.MarkerId('selected_pin'),
                position: _toGmaps(_pinLatLng),
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  gmaps.BitmapDescriptor.hueRed,
                ),
              ),
            },
          ),

          // Search bar + its own suggestions list — completely separate
          // from the Address field below.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                _buildMapSearchBar(),
                if (_suggestions.isNotEmpty) _buildSuggestionsList(),
              ],
            ),
          ),

          // "Use my current location" button.
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'locate_me',
              backgroundColor: Colors.white,
              foregroundColor: primary,
              onPressed: _fetchingCurrentLocation ? null : _useCurrentLocation,
              child: _fetchingCurrentLocation
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primary,
                      ),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          if (_locationLoading)
            Container(
              color: Colors.white70,
              child: const Center(
                child: CircularProgressIndicator(color: primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        onSubmitted: _searchAndMoveTo,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search for a location',
          hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: primary),
          suffixIcon: _searchingSuggestions
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primary,
                    ),
                  ),
                )
              : (_searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _suggestions = []);
                        },
                      )
                    : null),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.location_on_outlined, color: primary),
            title: Text(
              suggestion.description,
              style: const TextStyle(fontSize: 13.5),
            ),
            onTap: () => _selectSuggestion(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildZoneWarning() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: const Text(
        'This location is outside our delivery zone.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.red,
          fontWeight: FontWeight.w600,
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
          'Search on the map, tap a location, or use your current location '
          'to set your delivery address.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),

        _buildAddressField(),
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
          'Phone Number (+923001234567)',
          Icons.phone_android,
          keyboardType: TextInputType.phone,
          maxLength: 10,

          prefixText: '+92 ',
          extraFormatters: [FilteringTextInputFormatter.digitsOnly],
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

  Widget _buildAddressField() {
    return _buildTextField(
      _addressCtrl,
      'Address',
      Icons.home_work_rounded,
      // Was 2 — a merged place-name + formatted-address string routinely
      // runs longer than 2 lines and was getting visually clipped even
      // though the full text was already saved in the controller.
      maxLines: 4,
      focusNode: _addressFocus,
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
    FocusNode? focusNode,
    Widget? suffix,
    String? prefixText,
    List<TextInputFormatter>? extraFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLength: maxLength,
        readOnly: readOnly,
        maxLines: maxLines,
        textCapitalization: capitalizeWords
            ? TextCapitalization.words
            : TextCapitalization.none,
        inputFormatters: capitalizeWords
            ? [CapitalizeWordsFormatter()]
            : extraFormatters,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          counterText: "",
          prefixIcon: Icon(icon, color: primary, size: 22),
          prefixText: prefixText,
          prefixStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          suffixIcon: suffix,
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
