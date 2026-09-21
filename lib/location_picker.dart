import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Result handed back to whoever pushed [LocationPickerScreen].
class PickedLocation {
  final String address;
  final double latitude;
  final double longitude;

  const PickedLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

/// Full-screen "choose delivery location" map — free stack, no Google
/// billing required: OpenStreetMap tiles for the map itself, and
/// Nominatim (OSM's free geocoding service) for search + reverse
/// geocoding. Uses the common "fixed center pin, drag the map under it"
/// pattern instead of a draggable marker, since plain OSM tiles have no
/// equivalent of Google's draggable Marker.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLatLng;

  const LocationPickerScreen({super.key, this.initialLatLng});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const primary = Color(0xFFA70000);

  final MapController _mapController = MapController();
  late LatLng _pinLatLng;

  bool _gpsLoading = false;
  bool _isSearching = false;
  bool _resolvingAddress = false;
  String _resolvedAddress = '';

  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _predictions = [];
  Timer? _searchDebounce;
  Timer? _moveDebounce;

  // ────────────────────────────────────────────────────────────
  // 🗺️ DELIVERY ZONE BOUNDARY (Cantt area) — RECTANGLE CORNERS
  // ────────────────────────────────────────────────────────────
  static const LatLng _zoneSouthWest = LatLng(33.7377237, 72.7183126);
  static const LatLng _zoneNorthEast = LatLng(33.8020805, 72.79845700000001);
  bool _isInZone = true;

  // ⚠️ Nominatim's usage policy requires a real identifying User-Agent
  // (app name + a real contact) — replace this before shipping, or
  // requests may get rate-limited/blocked. For anything beyond light
  // traffic, consider self-hosting Nominatim or using a paid-but-cheap
  // provider (LocationIQ / MapTiler both have generous free tiers) as a
  // more reliable long-term option.
  static const String _nominatimUserAgent =
      'com.example.animation (support@yourapp.com)';

  @override
  void initState() {
    super.initState();
    _pinLatLng = widget.initialLatLng ?? const LatLng(33.6844, 73.0479);
    _checkZone();

    if (widget.initialLatLng == null) {
      // No previous location to start from — auto-detect the customer's
      // GPS position so the map opens somewhere useful.
      _handleGpsSelection(isAutoDetect: true);
    } else {
      _updateAddressFromCoordinates(_pinLatLng.latitude, _pinLatLng.longitude);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _moveDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

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

  // Free reverse geocoding via OpenStreetMap's Nominatim — no API key,
  // no billing.
  Future<void> _updateAddressFromCoordinates(
    double lat,
    double lng, {
    String? userSearchQuery,
  }) async {
    setState(() => _resolvingAddress = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );

      final res = await http.get(
        url,
        headers: {'User-Agent': _nominatimUserAgent},
      );
      final data = jsonDecode(res.body);

      final String? displayName = (data is Map)
          ? data['display_name'] as String?
          : null;

      final resolved = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : (userSearchQuery ??
                (_searchCtrl.text.trim().isNotEmpty
                    ? _searchCtrl.text.trim()
                    : 'Selected Location'));

      setState(() {
        _resolvedAddress = resolved;
        _searchCtrl.text = resolved;
        _resolvingAddress = false;
      });
    } catch (_) {
      final fallback =
          userSearchQuery ??
          (_searchCtrl.text.trim().isNotEmpty
              ? _searchCtrl.text.trim()
              : 'Selected Location');
      setState(() {
        _resolvedAddress = fallback;
        _resolvingAddress = false;
      });
    }
  }

  // Fires while the user drags the map (the pin itself stays fixed at
  // screen center — see build()). Debounced so we only hit Nominatim
  // once movement actually settles, respecting its 1-request/second
  // usage policy.
  void _onMapPositionChanged(MapCamera camera, bool hasGesture) {
    _pinLatLng = camera.center;
    if (!hasGesture) return;

    if (_moveDebounce?.isActive ?? false) _moveDebounce!.cancel();
    _moveDebounce = Timer(const Duration(milliseconds: 700), () {
      _checkZone();
      _updateAddressFromCoordinates(_pinLatLng.latitude, _pinLatLng.longitude);
    });
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchPredictions(query.trim());
    });
  }

  // Free forward-search via Nominatim, biased to the delivery zone with
  // a bounding box (viewbox + bounded=1) so results outside the Cantt
  // area are excluded outright.
  //
  // 👈 TEMP DEBUG: prints the exact URL, status code and raw body so we
  // can see whether Nominatim is rejecting the request (bad status code
  // / blocked User-Agent) or simply returning zero results for that
  // query inside this small bounding box. Remove these debugPrint lines
  // once search is confirmed working.
  Future<void> _fetchPredictions(String input) async {
    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&q=${Uri.encodeComponent(input)}'
        '&limit=8'
        '&countrycodes=pk'
        '&viewbox=${_zoneSouthWest.longitude},${_zoneNorthEast.latitude},'
        '${_zoneNorthEast.longitude},${_zoneSouthWest.latitude}',
        // 👈 REMOVED &bounded=1 — that made viewbox a hard filter, so
        // any place OSM didn't have mapped with fine detail inside this
        // small rectangle returned zero results even when it genuinely
        // exists nearby. Without "bounded", viewbox is just a ranking
        // bias (prefers nearby matches first) instead of an exclusion
        // rule. Out-of-zone picks are still blocked later at confirm
        // time via _isInZone, so this stays safe.
      );

      debugPrint('Nominatim search URL: $url');

      final res = await http.get(
        url,
        headers: {'User-Agent': _nominatimUserAgent},
      );

      debugPrint('Nominatim search status: ${res.statusCode}');
      debugPrint('Nominatim search body: ${res.body}');

      final data = jsonDecode(res.body);

      if (data is List) {
        final results = data
            .map<Map<String, dynamic>>(
              (p) => {
                'description': (p['display_name'] ?? '') as String,
                'lat': double.tryParse('${p['lat']}') ?? 0.0,
                'lon': double.tryParse('${p['lon']}') ?? 0.0,
              },
            )
            .where((p) => (p['description'] as String).isNotEmpty)
            .toList();

        debugPrint('Nominatim parsed ${results.length} prediction(s)');

        setState(() {
          _predictions = results;
          _isSearching = false;
        });
      } else {
        debugPrint('Nominatim response was not a List — got: $data');
        setState(() {
          _predictions = [];
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Nominatim search threw an exception: $e');
      setState(() {
        _predictions = [];
        _isSearching = false;
      });
    }
  }

  void _selectPrediction(Map<String, dynamic> prediction) {
    FocusScope.of(context).unfocus();
    final description = prediction['description'] as String;
    final target = LatLng(
      prediction['lat'] as double,
      prediction['lon'] as double,
    );

    setState(() {
      _predictions = [];
      _pinLatLng = target;
      _resolvedAddress = description;
      _searchCtrl.text = description;
    });

    _checkZone();
    _mapController.move(target, 16.0);
  }

  Future<void> _handleSearchSubmit(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    FocusScope.of(context).unfocus();

    if (_predictions.isNotEmpty) {
      _selectPrediction(_predictions.first);
      return;
    }

    setState(() => _isSearching = true);
    await _fetchPredictions(trimmed);

    if (_predictions.isNotEmpty) {
      _selectPrediction(_predictions.first);
    } else {
      setState(() => _isSearching = false);
      _snack(
        'Could not find that location. Please try a slightly different search.',
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

      if (pos.accuracy > 30) {
        _snack(
          'GPS signal is weak here — please check the pin is on the '
          'right spot and drag the map if needed.',
        );
      }

      _mapController.move(newLatLng, 17.0);
    } catch (_) {
      setState(() => _gpsLoading = false);
      if (!isAutoDetect) {
        _snack('Failed to get GPS location.');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: primary));
  }

  void _confirmLocation() {
    if (!_isInZone) {
      _snack(
        'Sorry, this branch only delivers within the Cantt area. '
        'Please choose a location inside it.',
      );
      return;
    }

    final address = _resolvedAddress.trim().isNotEmpty
        ? _resolvedAddress.trim()
        : 'Selected Location';

    Navigator.pop(
      context,
      PickedLocation(
        address: address,
        latitude: _pinLatLng.latitude,
        longitude: _pinLatLng.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 2,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Choose Delivery Location',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pinLatLng,
              initialZoom: 15.0,
              onPositionChanged: _onMapPositionChanged,
            ),
            children: [
              TileLayer(
                // Free OpenStreetMap tile server — no key, no billing.
                // Fine for light/personal traffic; for higher production
                // volume, OSM's usage policy asks you to self-host tiles
                // or use a provider like MapTiler/Stadia's free tier.
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.animation',
              ),
            ],
          ),

          // Fixed center pin — the user drags the MAP underneath it
          // (there's no Google-style draggable marker on plain OSM
          // tiles), so whatever sits under this icon is the picked spot.
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_pin, color: primary, size: 46),
              ),
            ),
          ),

          // Search bar
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
                if (_predictions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 220),
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
                            item['description'] as String,
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

          // GPS button
          Positioned(
            bottom: 110,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'picker_gps_btn',
              backgroundColor: primary,
              onPressed: _gpsLoading ? null : () => _handleGpsSelection(),
              child: _gpsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.my_location_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),

          // Out-of-zone banner
          if (!_isInZone)
            Positioned(
              bottom: 110,
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

          // Bottom confirm sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: primary, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _resolvingAddress
                                ? 'Resolving address...'
                                : (_resolvedAddress.isEmpty
                                      ? 'Selected Location'
                                      : _resolvedAddress),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _confirmLocation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Confirm This Location',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
