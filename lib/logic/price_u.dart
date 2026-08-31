// ── DOMAIN LAYER ─────────────────────────────────────────────
// Pure business-logic helpers: no Firestore calls, no UI widgets.
// Only data transformation. Used by both the data layer (repository)
// and the presentation layer (screens) so price/quantity reading is
// consistent everywhere.

double readPriceValue(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  if (raw is Map && raw.isNotEmpty) {
    return readPriceValue(raw.values.first);
  }
  return double.tryParse(raw.toString()) ?? 0;
}

double readItemPrice(Map<String, dynamic> item) {
  final raw = item['price'] ??
      item['itemPrice'] ??
      item['unitPrice'] ??
      item['amount'] ??
      item['cost'];
  return readPriceValue(raw);
}

double readItemQuantity(Map<String, dynamic> item) {
  final raw = item['quantity'] ?? item['qty'] ?? 1;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString()) ?? 1;
}

// Order-level total: prefers an explicit total field on the order doc,
// falls back to summing item price × quantity if none is present or
// it's 0.
double computeOrderTotal(Map<String, dynamic> orderData, List<Map<String, dynamic>> items) {
  final raw = orderData['totalAmount'] ??
      orderData['total_bill'] ??
      orderData['totalPrice'] ??
      orderData['total'] ??
      orderData['grandTotal'] ??
      orderData['finalAmount'] ??
      orderData['orderTotal'] ??
      orderData['amount'];
  final t = readPriceValue(raw);
  if (t > 0) return t;

  double sum = 0;
  for (final item in items) {
    sum += readItemPrice(item) * readItemQuantity(item);
  }
  return sum;
}

// Normalizes the raw `items`/`cartItems` list from a Firestore order doc
// into a clean List<Map<String, dynamic>>.
List<Map<String, dynamic>> readOrderItems(Map<String, dynamic> orderData) {
  final raw = orderData['items'] ?? orderData['cartItems'] ?? [];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}