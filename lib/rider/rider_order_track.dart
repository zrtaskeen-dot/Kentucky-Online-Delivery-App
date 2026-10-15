

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'rider_logic.dart';


const String _directionsApiKey = String.fromEnvironment('DIRECTIONS_API_KEY');



const List<Color> _kCustomerColors = [
  Color(0xFFD32F2F), 
  Color(0xFF2E7D32), 
  Color(0xFF6A1B9A), 
  Color(0xFFEF6C00), 
  Color(0xFF00838F), 
  Color(0xFF5D4037), 
];

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

class _OnTheWayCustomer {
  final String orderId;
  final String name;
  final String address;
  final LatLng? position; 
  final Color color;
  const _OnTheWayCustomer({
    required this.orderId,
    required this.name,
    required this.address,
    required this.position,
    required this.color,
  });
}

class _RouteInfo {
  final List<LatLng> points;
  final String durationText; 
  final String distanceText; 
  final LatLng fetchedFrom; 
  final DateTime fetchedAt;
  const _RouteInfo({
    required this.points,
    required this.durationText,
    required this.distanceText,
    required this.fetchedFrom,
    required this.fetchedAt,
  });
}

class RiderDeliveriesMapScreen extends StatefulWidget {
  final String riderId;
  final RiderController riderController;

  const RiderDeliveriesMapScreen({
    super.key,
    required this.riderId,
    required this.riderController,
  });

  @override
  State<RiderDeliveriesMapScreen> createState() =>
      _RiderDeliveriesMapScreenState();
}

class _RiderDeliveriesMapScreenState extends State<RiderDeliveriesMapScreen> {
  static const primary = Color(0xFFA70000);

  
  static const double _minMetersBeforeRefetch = 50;
  static const Duration _minRefetchGap = Duration(seconds: 20);

  GoogleMapController? _mapController;
  BitmapDescriptor? _riderDotIcon;

  
  final Map<String, BitmapDescriptor> _pins = {};
  final Set<String> _pinsBeingBuilt = {};

 
  final Map<String, _RouteInfo> _routes = {};
  final Set<String> _fetching = {};
  final Map<String, DateTime> _lastAttemptAt = {};

  
  LatLng? _fallbackRiderLatLng;

  
  List<_OnTheWayCustomer> _latestCustomers = const [];
  LatLng? _latestRider;
  String _lastFitKey = '';

  late final Stream<QuerySnapshot> _ordersStream = FirebaseFirestore.instance
      .collection('orders')
      .where('riderId', isEqualTo: widget.riderId)
      .where('orderStatus', isEqualTo: 'On the Way')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _buildRiderDot();
    _loadFallbackLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _buildRiderDot() async {
    final icon = await _buildRiderDotBitmap();
    if (mounted && icon != null) setState(() => _riderDotIcon = icon);
  }

 
  BitmapDescriptor? _pinFor(List<String> lines, Color color) {
    final key = '${color.toARGB32()}|${lines.join('|')}';
    final cached = _pins[key];
    if (cached != null) return cached;

    if (!_pinsBeingBuilt.contains(key)) {
      _pinsBeingBuilt.add(key);
      _buildNamedPinBitmap(lines, color).then((icon) {
        _pinsBeingBuilt.remove(key);
        if (mounted && icon != null) setState(() => _pins[key] = icon);
      });
    }
    return null;
  }

 
  Future<void> _loadFallbackLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          isFreshFix(last, maxAge: const Duration(minutes: 5))) {
        if (mounted) {
          setState(
            () => _fallbackRiderLatLng = LatLng(last.latitude, last.longitude),
          );
        }
        return;
      }
      final now = await Geolocator.getCurrentPosition(
        // ignore: deprecated_member_use
        desiredAccuracy: LocationAccuracy.high,
        // ignore: deprecated_member_use
        timeLimit: const Duration(seconds: 8),
      );
      if (mounted && isReliableRiderFix(now, maxAccuracyMeters: 100)) {
        setState(
          () => _fallbackRiderLatLng = LatLng(now.latitude, now.longitude),
        );
      }
    } catch (_) {
     
    }
  }

  List<_OnTheWayCustomer> _parseCustomers(QuerySnapshot snap) {
    
    final docs = snap.docs.toList()..sort((a, b) => a.id.compareTo(b.id));
    final list = <_OnTheWayCustomer>[];
    for (int i = 0; i < docs.length; i++) {
      final d = docs[i];
      final data = d.data() as Map<String, dynamic>;
      final lat = _toDouble(data['latitude']);
      final lng = _toDouble(data['longitude']);
      final hasCoords = lat != null && lng != null && !(lat == 0 && lng == 0);
      list.add(
        _OnTheWayCustomer(
          orderId: d.id,
          name: (data['customerName'])
              .toString(),
          address: (data['deliveryAddress'])
              .toString(),
          position: hasCoords ? LatLng(lat, lng) : null,
          color: _kCustomerColors[i % _kCustomerColors.length],
        ),
      );
    }
    return list;
  }

 
  void _refreshRoutes(List<_OnTheWayCustomer> customers, LatLng rider) {
    if (!mounted) return;
    final now = DateTime.now();
    for (final c in customers) {
      final dest = c.position;
      if (dest == null || _fetching.contains(c.orderId)) continue;

      final lastAttempt = _lastAttemptAt[c.orderId];
      if (lastAttempt != null && now.difference(lastAttempt) < _minRefetchGap) {
        continue;
      }

      final existing = _routes[c.orderId];
      if (existing != null) {
        final moved = Geolocator.distanceBetween(
          existing.fetchedFrom.latitude,
          existing.fetchedFrom.longitude,
          rider.latitude,
          rider.longitude,
        );
        if (moved < _minMetersBeforeRefetch) continue;
      }

      _lastAttemptAt[c.orderId] = now;
      _fetchRoute(c.orderId, dest, rider);
    }
  }

  Future<void> _fetchRoute(String orderId, LatLng dest, LatLng rider) async {
    _fetching.add(orderId);
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${rider.latitude},${rider.longitude}'
        '&destination=${dest.latitude},${dest.longitude}'
        '&key=$_directionsApiKey',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        debugPrint('Directions API error: HTTP ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 'OK') {
        debugPrint('Directions API status: ${data['status']}');
        return;
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final duration = (leg['duration'] as Map<String, dynamic>?)?['text'];
      final distance = (leg['distance'] as Map<String, dynamic>?)?['text'];
      final points = _decodePolylinePoints(
        route['overview_polyline']['points'] as String,
      );

      if (!mounted) return;
      setState(() {
        _routes[orderId] = _RouteInfo(
          points: points,
          durationText: (duration ?? '').toString(),
          distanceText: (distance ?? '').toString(),
          fetchedFrom: rider,
          fetchedAt: DateTime.now(),
        );
      });
    } catch (e) {
      debugPrint('Error fetching route for $orderId: $e');
    } finally {
      _fetching.remove(orderId);
    }
  }

  void _fitAll() {
    final controller = _mapController;
    if (controller == null) return;

    final points = <LatLng>[
      for (final c in _latestCustomers)
        if (c.position != null) c.position!,
      if (_latestRider != null) _latestRider!,
    ];
    if (points.isEmpty) return;

    if (points.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(points.first, 15));
      return;
    }

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100,
      ),
    );
  }

 
  Widget _buildCustomerList(List<_OnTheWayCustomer> customers) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          itemCount: customers.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = customers[i];
            final route = _routes[c.orderId];
            final String trailing;
            if (c.position == null) {
              trailing = 'No map location';
            } else if (route != null && route.durationText.isNotEmpty) {
              trailing = '${route.durationText} · ${route.distanceText}';
            } else {
              trailing = 'Calculating…';
            }

            return InkWell(
              onTap: c.position == null
                  ? null
                  : () => _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(c.position!, 16),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: c.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                          if (c.address.isNotEmpty)
                            Text(
                              c.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trailing,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: c.position == null ? Colors.grey : c.color,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Delivery Map',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ordersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load your orders.'));
          }

          final customers = snapshot.hasData
              ? _parseCustomers(snapshot.data!)
              : <_OnTheWayCustomer>[];

          
          _routes.removeWhere(
            (id, _) => !customers.any((c) => c.orderId == id),
          );

          return ValueListenableBuilder<Position?>(
            valueListenable: widget.riderController.riderPosition,
            builder: (context, pos, _) {
              final LatLng? rider = pos != null
                  ? LatLng(pos.latitude, pos.longitude)
                  : _fallbackRiderLatLng;

              _latestCustomers = customers;
              _latestRider = rider;

              if (rider != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _refreshRoutes(customers, rider),
                );
              }

              
              final ids = customers.map((c) => c.orderId).toList()..sort();
              final fitKey = '${ids.join(',')}|${rider != null}';
              if (fitKey != _lastFitKey && _mapController != null) {
                _lastFitKey = fitKey;
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
              }

              // Customers at the SAME place share one pin 
              
              final groups = <String, List<_OnTheWayCustomer>>{};
              for (final c in customers) {
                final p = c.position;
                if (p == null) continue;
                final key =
                    '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
                groups.putIfAbsent(key, () => []).add(c);
              }

              final markers = <Marker>{};
              groups.forEach((key, list) {
                final lines = list.map((c) {
                  final eta = _routes[c.orderId]?.durationText ?? '';
                  return eta.isEmpty ? c.name : '${c.name} • $eta';
                }).toList();

                markers.add(
                  Marker(
                    markerId: MarkerId('group_$key'),
                    position: list.first.position!,
                    icon:
                        _pinFor(lines, list.first.color) ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueRed,
                        ),
                    
                    anchor: const Offset(0.5, 1.0),
                    infoWindow: InfoWindow(
                      title: list.map((c) => c.name).join(', '),
                      snippet: list.first.address,
                    ),
                  ),
                );
              });

              if (rider != null) {
                markers.add(
                  Marker(
                    markerId: const MarkerId('rider'),
                    position: rider,
                    icon:
                        _riderDotIcon ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                    anchor: const Offset(0.5, 0.5),
                    infoWindow: const InfoWindow(title: 'You'),
                  ),
                );
              }

              final polylines = <Polyline>{
                for (final c in customers)
                  if (_routes[c.orderId] != null)
                    Polyline(
                      polylineId: PolylineId('route_${c.orderId}'),
                      points: _routes[c.orderId]!.points,
                      color: c.color,
                      width: 5,
                    ),
              };

              LatLng initialTarget = const LatLng(33.6844, 73.0479);
              for (final c in customers) {
                if (c.position != null) {
                  initialTarget = c.position!;
                  break;
                }
              }
              if (customers.every((c) => c.position == null) && rider != null) {
                initialTarget = rider;
              }

              
              final double listPadding = customers.isEmpty
                  ? 0
                  : (customers.length * 62.0 + 20).clamp(0, 190).toDouble();

              final String chipText = !snapshot.hasData
                  ? 'Loading orders…'
                  : customers.isEmpty
                  ? 'No orders are marked "On the Way" right now.'
                  : 'On the Way: ${customers.length} '
                        '${customers.length == 1 ? 'order' : 'orders'}';

              return Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: 13,
                    ),
                    padding: EdgeInsets.only(bottom: listPadding),
                    onMapCreated: (controller) {
                      _mapController = controller;
                      _lastFitKey = '${ids.join(',')}|${rider != null}';
                      _fitAll();
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    markers: markers,
                    polylines: polylines,
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 64,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 6),
                          ],
                        ),
                        child: Text(
                          chipText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter_deliveries_map',
                      backgroundColor: Colors.white,
                      onPressed: _fitAll,
                      child: const Icon(
                        Icons.center_focus_strong_rounded,
                        color: primary,
                      ),
                    ),
                  ),
                  if (customers.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildCustomerList(customers),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}


List<LatLng> _decodePolylinePoints(String encoded) {
  final List<LatLng> points = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}


Future<BitmapDescriptor?> _buildRiderDotBitmap() async {
  try {
    const double size = 60;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size / 2,
      Paint()..color = Colors.blue.withValues(alpha: 0.25),
    );
    canvas.drawCircle(center, size / 3.2, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 4, Paint()..color = Colors.blue);

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    // ignore: deprecated_member_use
    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  } catch (e) {
    debugPrint('Could not draw rider dot: $e');
    return null;
  }
}


Future<BitmapDescriptor?> _buildNamedPinBitmap(
  List<String> lines,
  Color color,
) async {
  try {
    final double dpr =
        ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final double fontSize = 13 * dpr;
    final double padH = 9 * dpr;
    final double padV = 5 * dpr;
    final double gap = 2 * dpr;
    final double pinR = 8 * dpr; 
    final double tail = 9 * dpr; 
    final double maxTextW = 190 * dpr;

    final paragraph =
        (ui.ParagraphBuilder(
                ui.ParagraphStyle(
                  textAlign: TextAlign.center,
                  maxLines: lines.length,
                  ellipsis: '…',
                ),
              )
              ..pushStyle(
                ui.TextStyle(
                  color: const Color(0xFF222222),
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              )
              ..addText(lines.join('\n')))
            .build();
    paragraph.layout(ui.ParagraphConstraints(width: maxTextW));
    
    final double textW = paragraph.longestLine.ceilToDouble() + 1;
    paragraph.layout(ui.ParagraphConstraints(width: textW));

    final double labelW = textW + padH * 2;
    final double labelH = paragraph.height + padV * 2;
    final double pinH = pinR * 2 + tail;
    final double w = labelW;
    final double h = labelH + gap + pinH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, labelH),
      Radius.circular(lines.length > 1 ? 14 * dpr : labelH / 2),
    );
    canvas.drawRRect(bubble, Paint()..color = Colors.white);
    canvas.drawRRect(
      bubble,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * dpr,
    );
    canvas.drawParagraph(paragraph, Offset(padH, padV));

    
    final double cx = w / 2;
    final double headCy = labelH + gap + pinR;
    final pinPaint = Paint()..color = color;
    canvas.drawCircle(Offset(cx, headCy), pinR, pinPaint);
    canvas.drawPath(
      Path()
        ..moveTo(cx - pinR * 0.75, headCy + pinR * 0.55)
        ..lineTo(cx, h)
        ..lineTo(cx + pinR * 0.75, headCy + pinR * 0.55)
        ..close(),
      pinPaint,
    );
    canvas.drawCircle(
      Offset(cx, headCy),
      pinR * 0.38,
      Paint()..color = Colors.white,
    );

    final image = await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    // ignore: deprecated_member_use
    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
  } catch (e) {
    debugPrint('Could not draw customer pin: $e');
    return null;
  }
}


const String kUndeliveredOther = 'Other reason';

const List<String> kUndeliveredReasons = [
  'The customer refused to receive the order',
  'The customer is not available to receive the order',
  'The delivery address cannot be located',
  'The customer is not answering the phone',
  kUndeliveredOther,
];

class UndeliveredChoice {
  final String reason;
  final String note;
  const UndeliveredChoice(this.reason, this.note);
}


Future<bool?> showUndeliveredFlow(
  BuildContext context, {
  required RiderController rc,
  required String orderId,
}) async {
  final choice = await showModalBottomSheet<UndeliveredChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _UndeliveredSheet(),
  );
  if (choice == null) return null;
  return rc.markUndelivered(orderId, choice.reason, note: choice.note);
}

class _UndeliveredSheet extends StatefulWidget {
  const _UndeliveredSheet();

  @override
  State<_UndeliveredSheet> createState() => _UndeliveredSheetState();
}

class _UndeliveredSheetState extends State<_UndeliveredSheet> {
  static const Color _maroon = Color(0xFFA70000);
  static const Color _selectedBg = Color(0x14A70000); 

  String? _selected;
  final TextEditingController _note = TextEditingController();

  bool get _isOther => _selected == kUndeliveredOther;
  bool get _canConfirm =>
      _selected != null && (!_isOther || _note.text.trim().isNotEmpty);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Widget _reasonTile(String reason) {
    final bool selected = _selected == reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selected = reason),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _selectedBg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _maroon : Colors.grey.shade300,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? _maroon : Colors.grey.shade500,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.black87,
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
    return Padding(
    
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
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
              const SizedBox(height: 16),
              const Text(
                'Why was the order not delivered?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select one reason. The manager will see it.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in kUndeliveredReasons) _reasonTile(r),
                      if (_isOther) ...[
                        const SizedBox(height: 2),
                        TextField(
                          controller: _note,
                          maxLength: 150,
                          maxLines: 2,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Write the reason',
                            filled: true,
                            fillColor: const Color(0xFFFFFDFA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _maroon,
                                width: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: BorderSide(color: Colors.grey.shade400),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _canConfirm
                          ? () => Navigator.pop(
                              context,
                              UndeliveredChoice(
                                _selected!,
                                _isOther ? _note.text.trim() : '',
                              ),
                            )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _maroon,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _maroon.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'CONFIRM UNDELIVERED',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}