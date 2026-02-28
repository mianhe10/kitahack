import 'dart:typed_data';

enum CsvPlatform { shopee, tiktok, unknown }

class ParsedProduct {
  final String name;
  final double price;
  final int quantity;
  final String date;
  final String variation;

  ParsedProduct({
    required this.name,
    required this.price,
    required this.quantity,
    required this.date,
    required this.variation,
  });
}

class CsvParser {
  /// Auto-detect platform from headers
  static CsvPlatform detectPlatform(List<String> headers) {
    final h = headers.map((e) => e.toLowerCase().trim()).toList();

    if (h.contains('deal price') || h.contains('order creation date')) {
      return CsvPlatform.shopee;
    }
    if (h.contains('sku id') || h.any((e) => e.contains('unit price'))) {
      return CsvPlatform.tiktok;
    }
    return CsvPlatform.unknown;
  }

  /// Parse raw CSV bytes into a list of ParsedProduct
  /// Skips cancelled orders automatically
  static List<ParsedProduct> parse(Uint8List bytes) {
    final content = String.fromCharCodes(bytes);
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.length < 2) return [];

    final headers = _splitCsvLine(lines[0]);
    final platform = detectPlatform(headers);
    final results = <ParsedProduct>[];

    for (int i = 1; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.length < headers.length) continue;

      Map<String, String> row = {};
      for (int j = 0; j < headers.length; j++) {
        row[headers[j].trim()] = cols[j].trim();
      }

      // Skip cancelled
      final status = (row['Order Status'] ?? '').toLowerCase();
      if (status == 'cancelled' || status == 'canceled') continue;

      ParsedProduct? product;

      if (platform == CsvPlatform.shopee) {
        product = _parseShopeeRow(row);
      } else if (platform == CsvPlatform.tiktok) {
        product = _parseTikTokRow(row);
      } else {
        product = _parseGenericRow(row, headers);
      }

      if (product != null) results.add(product);
    }

    return results;
  }

  // ── Shopee ────────────────────────────────────────────────
  static ParsedProduct? _parseShopeeRow(Map<String, String> row) {
    final name = row['Product Name'] ?? '';
    final price = double.tryParse(row['Deal Price'] ?? '') ?? 0.0;
    final qty = int.tryParse(row['Quantity'] ?? '') ?? 0;
    final date = row['Order Creation Date'] ?? '';
    final variation = row['Variation Name'] ?? '';

    if (name.isEmpty || qty == 0) return null;
    return ParsedProduct(
      name: name,
      price: price,
      quantity: qty,
      date: date,
      variation: variation,
    );
  }

  // ── TikTok ────────────────────────────────────────────────
  static ParsedProduct? _parseTikTokRow(Map<String, String> row) {
    final name = row['Product Name'] ?? '';

    // TikTok header has parentheses: "Unit Price (RM)"
    final priceRaw = row.entries
        .firstWhere(
          (e) => e.key.toLowerCase().contains('unit price'),
          orElse: () => const MapEntry('', '0'),
        )
        .value;
    final price = double.tryParse(priceRaw) ?? 0.0;
    final qty = int.tryParse(row['Quantity'] ?? '') ?? 0;
    final date = row['Order Date'] ?? '';
    final variation = row['Variation'] ?? '';

    if (name.isEmpty || qty == 0) return null;
    return ParsedProduct(
      name: name,
      price: price,
      quantity: qty,
      date: date,
      variation: variation,
    );
  }

  // ── Generic fallback ──────────────────────────────────────
  static ParsedProduct? _parseGenericRow(
    Map<String, String> row,
    List<String> headers,
  ) {
    // Try to find best-match columns
    String name = '';
    double price = 0;
    int qty = 0;
    String date = '';

    for (final h in headers) {
      final lh = h.toLowerCase();
      final val = row[h] ?? '';
      if (name.isEmpty && lh.contains('product')) name = val;
      if (price == 0 && lh.contains('price')) price = double.tryParse(val) ?? 0;
      if (qty == 0 && lh.contains('qty') || lh.contains('quantity')) {
        qty = int.tryParse(val) ?? 0;
      }
      if (date.isEmpty && lh.contains('date')) date = val;
    }

    if (name.isEmpty) return null;
    return ParsedProduct(
      name: name,
      price: price,
      quantity: qty,
      date: date,
      variation: '',
    );
  }

  /// Handles quoted CSV fields properly
  static List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString());
    return result;
  }
}
