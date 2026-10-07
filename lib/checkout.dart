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
import 'package:cloud_firestore/cloud_firestore.dart';
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
  static const String _googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _addressFocus = FocusNode();

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  List<_PlaceSuggestion> _suggestions = [];
  bool _searchingSuggestions = false;
  Timer? _debounce;
  String _sessionToken = '';

  Timer? _addressDebounce;
  bool _updatingAddressProgrammatically = false;

  gmaps.GoogleMapController? _mapController;

  LatLng _pinLatLng = const LatLng(33.6844, 73.0479); // Default: Islamabad

  gmaps.LatLng _toGmaps(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);
  LatLng _fromGmaps(gmaps.LatLng p) => LatLng(p.latitude, p.longitude);
  bool _saveInfoForNextTime = false;
  bool _locationLoading = true;
  bool _fetchingCurrentLocation = false;
  bool _isInZone = true;

  bool _zoneUnverified = false; // true jab Google se distance nahi mili
  int _zoneCheckSeq = 0; // purane (stale) check ka result ignore karne ke liye
  final Map<String, double> _roadDistCache = {};

  // Radius ke upar itne extra metres allow hain (GPS jitter absorb karne ke
  // liye). 0 = bilkul strict.
  static const double _zoneToleranceM = 0;

  // Delivery zone — sirf SELECTED BRANCH ka apna (restaurant_info/{branchId}).
  // Priority:
  //   1. deliveryBounds {south, north, west, east}  (admin ne set kiya)
  //   2. branchLat / branchLng + deliveryRadiusKm    (circle)
  //   3. branch ka 'address' yahin geocode karke circle
  // Kuch bhi na mile to zone "not configured" hai aur address qabool nahi
  // hota. Kisi aur branch ka (jaise Wah ka) zone kabhi fallback nahi banta.
  //
  // Circle ka radius ab ROAD (driving) distance hai, straight-line nahi.
  static const double _defaultRadiusKm = 5;
  LatLng? _zoneSouthWest;
  LatLng? _zoneNorthEast;
  LatLng? _zoneCircleCenter;
  double? _zoneCircleRadiusM;
  bool _zoneReady = false; // branch zone load karne ki koshish mukammal
  bool _zoneConfigured = false;
  String _branchLabel = '';

  static const bgColor = Colors.white;
  static const primary = Color(0xFFA70000);
  static const creamText = Colors.white;
  static const fieldBg = Color(0xFFFFFDFA);

  // Returns true (in zone), false (outside), or null (road distance could
  // not be verified — e.g. no internet / API error).
  Future<bool?> _evaluateZone(LatLng point) async {
    // Jab tak branch ka zone load ho raha hai, rukawat na lagao.
    if (!_zoneReady) return true;
    if (!_zoneConfigured) return false;

    final sw = _zoneSouthWest;
    final ne = _zoneNorthEast;
    if (sw != null && ne != null) {
      if (point.latitude < sw.latitude ||
          point.latitude > ne.latitude ||
          point.longitude < sw.longitude ||
          point.longitude > ne.longitude) {
        return false;
      }
    }

    final c = _zoneCircleCenter;
    final r = _zoneCircleRadiusM;
    if (c != null && r != null) {
      final limit = r + _zoneToleranceM;

      // Road kabhi straight line se chhoti nahi hoti. Agar straight line
      // hi limit se zyada hai to API call ki zaroorat nahi — seedha outside.
      if (_distanceMeters(c, point) > limit) return false;

      final road = await _roadDistanceMeters(c, point);
      if (road == null) return null;
      return road <= limit;
    }
    return true;
  }

  // Branch se customer tak driving distance (metres), Routes API
  // (computeRouteMatrix) ke zariye — legacy Distance Matrix ab naye
  // projects par enable nahi ho sakta.
  // double.infinity = koi route nahi, null = verify nahi ho saka.
  Future<double?> _roadDistanceMeters(LatLng from, LatLng to) async {
    final key =
        '${from.latitude.toStringAsFixed(5)},'
        '${from.longitude.toStringAsFixed(5)}|'
        '${to.latitude.toStringAsFixed(5)},'
        '${to.longitude.toStringAsFixed(5)}';
    final cached = _roadDistCache[key];
    if (cached != null) return cached;

    try {
      final uri = Uri.https(
        'routes.googleapis.com',
        '/distanceMatrix/v2:computeRouteMatrix',
      );

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _googleApiKey,
          'X-Goog-FieldMask':
              'originIndex,destinationIndex,distanceMeters,status,condition',
        },
        body: jsonEncode({
          'origins': [
            {
              'waypoint': {
                'location': {
                  'latLng': {
                    'latitude': from.latitude, // branch
                    'longitude': from.longitude,
                  },
                },
              },
            },
          ],
          'destinations': [
            {
              'waypoint': {
                'location': {
                  'latLng': {
                    'latitude': to.latitude, // customer
                    'longitude': to.longitude,
                  },
                },
              },
            },
          ],
          'travelMode': 'DRIVE',
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Routes API error ${response.statusCode}: ${response.body}. '
          'Check that Routes API is enabled for the key and that the key '
          'has no Android/iOS/HTTP-referrer restriction.',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      final list = decoded is List ? decoded : [decoded];
      if (list.isEmpty) return null;

      final el = list.first as Map<String, dynamic>;
      final condition = el['condition'] as String?;
      if (condition == 'ROUTE_NOT_FOUND') return double.infinity;
      if (condition != 'ROUTE_EXISTS') return null;

      final meters = (el['distanceMeters'] as num?)?.toDouble();
      if (meters == null) return null;
      _roadDistCache[key] = meters;
      return meters;
    } catch (e) {
      debugPrint('Road distance lookup failed: $e');
      return null;
    }
  }

  LatLng get _zoneCenter {
    final c = _zoneCircleCenter;
    if (c != null) return c;
    final sw = _zoneSouthWest;
    final ne = _zoneNorthEast;
    if (sw != null && ne != null) {
      return LatLng(
        (sw.latitude + ne.latitude) / 2,
        (sw.longitude + ne.longitude) / 2,
      );
    }
    return const LatLng(0, 0);
  }

  double get _zoneRadiusMeters {
    final r = _zoneCircleRadiusM;
    if (r != null) return r;
    final ne = _zoneNorthEast;
    if (ne != null) return _distanceMeters(_zoneCenter, ne);
    return 0;
  }

  // Geocoding "bounds" bias ke liye box (circle ho to uske gird ka box).
  LatLng get _biasSouthWest {
    final sw = _zoneSouthWest;
    if (sw != null) return sw;
    final c = _zoneCenter;
    final dLat = _zoneRadiusMeters / 110574.0;
    final dLng =
        _zoneRadiusMeters / (111320.0 * math.cos(c.latitude * math.pi / 180));
    return LatLng(c.latitude - dLat, c.longitude - dLng);
  }

  LatLng get _biasNorthEast {
    final ne = _zoneNorthEast;
    if (ne != null) return ne;
    final c = _zoneCenter;
    final dLat = _zoneRadiusMeters / 110574.0;
    final dLng =
        _zoneRadiusMeters / (111320.0 * math.cos(c.latitude * math.pi / 180));
    return LatLng(c.latitude + dLat, c.longitude + dLng);
  }

  String get _zoneMessage {
    if (_zoneReady && !_zoneConfigured) {
      return 'Delivery area for this branch is not set yet.';
    }
    return _branchLabel.isEmpty
        ? 'Outside our delivery area.'
        : 'Outside $_branchLabel delivery area.';
  }

  double? _toNum(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  // Selected branch ka delivery zone Firestore se (ya uske address se) banata hai.
  Future<void> _loadBranchZone() async {
    LatLng? sw, ne, center;
    double? radiusM;
    String label = '';

    try {
      if (widget.branchId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('restaurant_info')
            .doc(widget.branchId)
            .get();
        final data = doc.data() ?? {};
        label = (data['branchName'] ?? '').toString().trim();

        // 1) Admin ka box
        final b = data['deliveryBounds'];
        if (b is Map) {
          final south = _toNum(b['south']);
          final north = _toNum(b['north']);
          final west = _toNum(b['west']);
          final east = _toNum(b['east']);
          if (south != null &&
              north != null &&
              west != null &&
              east != null &&
              south < north &&
              west < east) {
            sw = LatLng(south, west);
            ne = LatLng(north, east);
          }
        }

        // 2) Branch ki location + radius (circle box se zyada sahi hai)
        final radiusKm = _toNum(data['deliveryRadiusKm']);
        final km = (radiusKm != null && radiusKm > 0)
            ? radiusKm
            : _defaultRadiusKm;
        final lat = _toNum(data['branchLat']);
        final lng = _toNum(data['branchLng']);
        if (lat != null && lng != null) {
          center = LatLng(lat, lng);
          radiusM = km * 1000;
          // Circle hi asal zone hai; admin tool ka purana saved box (jo
          // kisi purane radius se bana tha) radius badalne par rukawat na bane.
          sw = null;
          ne = null;
        } else if (sw == null) {
          // 3) Na box, na location: branch ka address yahin geocode karo
          final address = (data['address'] ?? '').toString().trim();
          if (address.isNotEmpty) {
            final uri = Uri.https(
              'maps.googleapis.com',
              '/maps/api/geocode/json',
              {'address': address, 'key': _googleApiKey},
            );
            final res = _decodeGoogleResponse(await http.get(uri));
            final results = (res['results'] as List?) ?? [];
            if (results.isNotEmpty) {
              final loc = results.first['geometry']['location'] as Map;
              center = LatLng(
                (loc['lat'] as num).toDouble(),
                (loc['lng'] as num).toDouble(),
              );
              radiusM = km * 1000;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Could not load branch delivery zone: $e');
    }

    if (!mounted) return;
    setState(() {
      _zoneSouthWest = sw;
      _zoneNorthEast = ne;
      _zoneCircleCenter = center;
      _zoneCircleRadiusM = radiusM;
      _branchLabel = label;
      _zoneConfigured = sw != null || center != null;
      _zoneReady = true;
    });
    _checkZone();
  }

  // Straight-line (haversine) distance — ab sirf pre-check aur autocomplete
  // bias ke liye use hota hai. Final zone decision road distance se hota hai.
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

  // Pin ki current position ko check karta hai. Har path (GPS, search, map
  // tap, typed address) yahi function call karta hai.
  Future<void> _checkZone() async {
    final seq = ++_zoneCheckSeq;
    final point = _pinLatLng;
    final result = await _evaluateZone(point);
    // Agar is dauran pin dobara hila ya screen band hui, to ye result purana hai.
    if (!mounted || seq != _zoneCheckSeq) return;
    setState(() {
      _zoneUnverified = result == null;
      _isInZone = result ?? false;
    });
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
    if (_googleApiKey.isEmpty) {
      debugPrint(
        'GOOGLE_API_KEY is empty. Run with '
        '--dart-define=GOOGLE_API_KEY=... (or --dart-define-from-file).',
      );
    }
    _newSessionToken();
    _loadSavedInfo();
    _loadBranchZone();
    _searchCtrl.addListener(_onSearchChanged);
    _addressCtrl.addListener(_onAddressFieldChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addressDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _addressCtrl.removeListener(_onAddressFieldChanged);
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
        'Check that Places API, Geocoding API and Routes API are '
        'all enabled for the key, and that the key has no Android/iOS app '
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
  // Phone & address used to be remembered purely via local
  // SharedPreferences (only when "Save info for next time" was checked).
  // That meant editing your phone/address on the Profile screen had no
  // effect on what showed up at checkout next time — checkout had its own
  // separate memory. Now the user's Firestore profile (users/{uid}) is
  // the source of truth for phone/address, and SharedPreferences is only
  // a fallback for users who don't have those saved on their profile yet
  // (e.g. guests, or before this change shipped).
  Future<void> _loadSavedInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kSaveFlag) ?? false;

    // Name is still remembered locally via the checkbox, unchanged.
    if (saved) {
      setState(() {
        _saveInfoForNextTime = true;
        _firstNameCtrl.text = prefs.getString(_kFirstName) ?? '';
        _lastNameCtrl.text = prefs.getString(_kLastName) ?? '';
      });
    }

    final profile = await _fetchProfileDefaults();
    final profilePhone = (profile?['phone'] as String?)?.trim();
    final profileAddress = (profile?['address'] as String?)?.trim();
    final profileLat = (profile?['lat'] as num?)?.toDouble();
    final profileLng = (profile?['lng'] as num?)?.toDouble();

    final phoneDigits = (profilePhone != null && profilePhone.isNotEmpty)
        ? _localPhoneDigits(profilePhone)
        : (saved ? (prefs.getString(_kPhone) ?? '') : '');

    final address = (profileAddress != null && profileAddress.isNotEmpty)
        ? profileAddress
        : (saved ? prefs.getString(_kAddress) : null);

    final lat = profileLat ?? (saved ? prefs.getDouble(_kLat) : null);
    final lng = profileLng ?? (saved ? prefs.getDouble(_kLng) : null);

    if (phoneDigits.isNotEmpty) {
      setState(() => _phoneCtrl.text = phoneDigits);
    }

    if (lat != null && lng != null && address != null && address.isNotEmpty) {
      setState(() => _pinLatLng = LatLng(lat, lng));
      _setAddressSilently(address);
      _checkZone();
      setState(() => _locationLoading = false);
      return;
    }

    if (address != null && address.isNotEmpty) {
      // We have a saved address but no matching coordinates for it (can
      // happen if it was typed into the Profile screen directly) — show
      // the text, but still fall through to auto-detect a pin position.
      _setAddressSilently(address);
    }

    // No usable saved coordinates — detect the user's actual current
    // location instead of leaving the pin at a fixed, unrelated default.
    await _detectDefaultLocation();
    setState(() => _locationLoading = false);
  }

  // Reads phone/address/lat/lng straight from the user's profile
  // document. Returns null for guests or if the read fails, in which case
  // callers fall back to SharedPreferences / auto-detected location.
  Future<Map<String, dynamic>?> _fetchProfileDefaults() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      return doc.data();
    } catch (e) {
      debugPrint('Failed to fetch profile defaults for checkout: $e');
      return null;
    }
  }

  // The phone field only ever holds the 10 raw digits after +92 (see
  // phoneRegExp in _proceedToDeliveryScreen), but a saved profile number
  // may be stored with "+92", a leading "0", spaces, etc. This strips
  // everything down to digits and keeps just the last 10 — the local
  // subscriber number — so it fits back into that field correctly.
  String _localPhoneDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) return digits.substring(digits.length - 10);
    return digits;
  }

  // Silent GPS fetch used only to pick a sensible *default* pin position
  // when the screen first opens with no saved address. Unlike
  // _useCurrentLocation (the map's FAB), this doesn't show our own
  // confirmation dialog first — the OS permission prompt is already the
  // consent step here. If location is unavailable or denied, the pin
  // simply stays at the fallback coordinate set above.
  Future<void> _detectDefaultLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      setState(() => _pinLatLng = point);
      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLng(_toGmaps(point)),
      );
      _checkZone();
      await _reverseGeocode(point);
    } catch (e) {
      debugPrint('Failed to auto-detect default location: $e');
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
    _updatingAddressProgrammatically = true;
    setState(() => _addressCtrl.text = address);
    _updatingAddressProgrammatically = false;
  }

  // User typing directly into the Address field (not via search bar or
  // map tap) should still move the map — debounced so we're not
  // geocoding on every keystroke.
  void _onAddressFieldChanged() {
    if (_updatingAddressProgrammatically) return;
    _addressDebounce?.cancel();

    final query = _addressCtrl.text.trim();
    if (query.isEmpty) return;

    _addressDebounce = Timer(const Duration(milliseconds: 800), () {
      _geocodeTypedAddress(query);
    });
  }

  // Moves the pin/map to match what's typed in the Address field, without
  // rewriting the field itself — the user's own wording stays as they
  // typed it. Zone checking still happens via _checkZone() either way, so
  // the warning banner appears if this lands outside the delivery area.
  Future<void> _geocodeTypedAddress(String query) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': query,
        'key': _googleApiKey,
        'bounds':
            '${_biasSouthWest.latitude},${_biasSouthWest.longitude}|'
            '${_biasNorthEast.latitude},${_biasNorthEast.longitude}',
      });

      final response = await http.get(uri);
      final data = _decodeGoogleResponse(response);
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty || !mounted) return;

      final location = results.first['geometry']['location'] as Map;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final point = LatLng(lat, lng);

      setState(() => _pinLatLng = point);
      _mapController?.animateCamera(
        gmaps.CameraUpdate.newLatLng(_toGmaps(point)),
      );
      _checkZone();
    } catch (e) {
      debugPrint('Failed to geocode typed address: $e');
    }
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
    if (_zoneReady && !_zoneConfigured) {
      _snack('Delivery area for this branch is not set yet.');
      return;
    }
    setState(() => _searchingSuggestions = true);
    try {
      final baseParams = {
        'input': query,
        'key': _googleApiKey,
        'sessiontoken': _sessionToken,
        'location': '${_zoneCenter.latitude},${_zoneCenter.longitude}',
        'radius': _zoneRadiusMeters.toStringAsFixed(0),
        // Without this, location+radius are only a *bias* — results
        // outside the zone still show up. strictbounds forces Google to
        // only return results inside that circle. (Circle straight-line
        // hai, road distance usse kabhi chhoti nahi — isliye ye safe
        // pre-filter hai; final decision road distance se hota hai.)
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
  //
  // Pehle yahan apna alag zone gate tha jo pin ko move hi nahi hone deta
  // tha, jabke GPS/map tap pin move karke sirf warning dikhate the. Ab
  // teeno ek jaisa kaam karte hain: pin move hota hai, phir shared
  // _checkZone() (road distance) banner dikhata hai.
  Future<void> _searchAndMoveTo(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _searchingSuggestions = true);
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': query,
        'key': _googleApiKey,
        // Geocoding API can only "bias" toward this box, it can't hard
        // restrict like autocomplete's strictbounds can — the result is
        // checked against the zone by _checkZone() after the pin moves.
        'bounds':
            '${_biasSouthWest.latitude},${_biasSouthWest.longitude}|'
            '${_biasNorthEast.latitude},${_biasNorthEast.longitude}',
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

  // Plain reverse-geocoding only returns road/area/city/postal-code-style
  // components — it has no concept of a shop/landmark "name" (that's why
  // GPS-detected addresses used to start with a building/plot number or
  // plus-code-like fragment instead of a name). This does a quick Places
  // "nearby search" at the pin to find the closest named place, the same
  // way _selectSuggestion() already gets a name for typed/searched
  // addresses via Place Details — so GPS-detected and searched addresses
  // look consistent.
  Future<String?> _nearestPlaceName(LatLng point) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        {
          'location': '${point.latitude},${point.longitude}',
          'rankby': 'distance',
          'key': _googleApiKey,
        },
      );

      final response = await http.get(uri);
      final data = _decodeGoogleResponse(response);
      final results = (data['results'] as List?) ?? [];
      if (results.isEmpty) return null;
      final name = results.first['name'] as String?;
      return (name != null && name.trim().isNotEmpty) ? name.trim() : null;
    } catch (e) {
      debugPrint('Failed to fetch nearby place name: $e');
      return null;
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
      if (address == null) return;

      // FIX: prepend the nearest place's name (e.g. "Aslam Market")
      // in front of the road/city/postal-code address, same as the
      // search-suggestion flow — instead of leaving whatever
      // number/code-like fragment Google's plain geocode put first.
      final placeName = await _nearestPlaceName(point);
      final alreadyHasName =
          placeName != null &&
          address.toLowerCase().contains(placeName.toLowerCase());
      final finalAddress = (placeName != null && !alreadyHasName)
          ? '$placeName, $address'
          : address;

      _setAddressSilently(finalAddress);
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Use your current location?',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: const Text(
          'We need access to your device location to set your delivery address.',
          style: TextStyle(color: Colors.black87, fontSize: 13.5, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: Colors.black54),
            child: const Text(
              'Not now',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA70000),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Allow',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
    if (!_zoneReady) {
      _snack('Checking the delivery area — please try again in a moment.');
      return;
    }

    // Order se pehle taaza road-distance check — cache ki wajah se agar pin
    // nahi hila to ye free hai, aur purane (stale) result par order nahi jata.
    final inZone = await _evaluateZone(_pinLatLng);
    if (!mounted) return;
    if (inZone == null) {
      _snack('Could not verify the delivery distance. Please try again.');
      return;
    }
    if (!inZone) {
      _snack(_zoneMessage);
      return;
    }

    await _persistInfoIfNeeded();
    if (!mounted) return;

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

  // Same success/error color scheme used on login_screen.dart and
  // delivery_type.dart, so every "something went wrong" message in the
  // app reads the same way.
  static const Color _successBorder = Color(0xFF4A7C59);
  static const Color _successBg = Color(0xFFEAF3ED);
  static const Color _successText = Color(0xFF2F5B3E);
  static const Color _errorBorder = Color(0xFFC62828);
  static const Color _errorBg = Color(0xFFFDECEA);
  static const Color _errorText = Color(0xFFB71C1C);

  void _snack(String msg, {bool isError = true}) {
    if (!mounted) return;
    final borderColor = isError ? _errorBorder : _successBorder;
    final fillColor = isError ? _errorBg : _successBg;
    final textColor = isError ? _errorText : _successText;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: textColor, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            Icons.arrow_back_rounded,
            color: creamText,
            size: 24,
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
      child: Text(
        _zoneMessage,
        style: const TextStyle(
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
      // Was 4 — still felt cramped for a merged place-name + full address
      // string, so giving it a bit more room.
      maxLines: 5,
      minLines: 3,
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
    int? minLines,
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
        minLines: minLines,
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
            vertical: 16,
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
