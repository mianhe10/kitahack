class FullDataProcessor {
  static List<Map<String, dynamic>> process(
    List<List<dynamic>> rawCsvRows, 
    Map<String, String> mapping
  ) {
    if (rawCsvRows.isEmpty || rawCsvRows.length == 1) return [];

    final headers = rawCsvRows[0].map((e) => e.toString().trim()).toList();
    
    int getIndex(String key) {
      final mappedHeader = mapping[key];
      if (mappedHeader == null) return -1;
      return headers.indexOf(mappedHeader);
    }

    final idIdx = getIndex('prod_id');
    final priceIdx = getIndex('price');
    final qtyIdx = getIndex('qty');
    final soldIdx = getIndex('units_sold'); // NEW: Added units sold
    final dateIdx = getIndex('date');

    final List<Map<String, dynamic>> processedData = [];

    for (int i = 1; i < rawCsvRows.length; i++) {
      final row = rawCsvRows[i];
      
      if (row.isEmpty || row.join('').trim().isEmpty) continue;

      dynamic getValue(int index) {
        if (index != -1 && index < row.length) {
          return row[index];
        }
        return null; 
      }

      processedData.add({
        'prod_id': getValue(idIdx)?.toString() ?? 'Unknown',
        'price': _cleanPrice(getValue(priceIdx)),
        'qty': int.tryParse(getValue(qtyIdx)?.toString() ?? '0') ?? 0,
        'units_sold': int.tryParse(getValue(soldIdx)?.toString() ?? '0') ?? 0, // NEW: Extracted units sold
        'date': getValue(dateIdx)?.toString() ?? '',
      });
    }

    return processedData;
  }

  static double _cleanPrice(dynamic input) {
    if (input == null) return 0.0;
    String p = input.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(p) ?? 0.0;
  }
}