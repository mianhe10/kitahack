import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../widgets/csv_parser.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CsvPreviewScreen extends StatefulWidget {
  final String fileName;
  final Uint8List fileBytes;

  const CsvPreviewScreen({
    super.key,
    required this.fileName,
    required this.fileBytes,
  });

  @override
  State<CsvPreviewScreen> createState() => _CsvPreviewScreenState();
}

class _CsvPreviewScreenState extends State<CsvPreviewScreen> {
  late List<ParsedProduct> _products;
  late CsvPlatform _platform;
  late Map<String, _AggregatedProduct> _aggregated;

  // docId → existing stock (null = new product)
  final Map<String, int?> _existingStock = {};
  // name → initial stock controller (only for NEW products)
  final Map<String, TextEditingController> _stockControllers = {};

  bool _isSaving = false;
  bool _isChecking = true; // checking Firestore for existing products

  @override
  void initState() {
    super.initState();
    _parse();
    _checkExistingProducts();
  }

  @override
  void dispose() {
    for (final ctrl in _stockControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _parse() {
    _products = CsvParser.parse(widget.fileBytes);

    final content = String.fromCharCodes(widget.fileBytes);
    final firstLine = content.split('\n').first;
    final headers = firstLine.split(',');
    _platform = CsvParser.detectPlatform(headers);

    _aggregated = {};
    for (final p in _products) {
      if (_aggregated.containsKey(p.name)) {
        _aggregated[p.name]!.totalQty += p.quantity;
        _aggregated[p.name]!.orderCount++;
      } else {
        _aggregated[p.name] = _AggregatedProduct(
          name: p.name,
          price: p.price,
          totalQty: p.quantity,
          orderCount: 1,
        );
      }
    }
  }

  // ── Check Firestore for each product ─────────────────────
  Future<void> _checkExistingProducts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products');

    for (final name in _aggregated.keys) {
      final result = await col.where('name', isEqualTo: name).limit(1).get();

      if (result.docs.isNotEmpty) {
        // Exists → store current stock
        _existingStock[name] = (result.docs.first['stock'] ?? 0) as int;
        _aggregated[name]!.docId = result.docs.first.id;
      } else {
        // New product → create a controller for initial stock input
        _existingStock[name] = null;
        _stockControllers[name] = TextEditingController();
      }
    }

    if (mounted) setState(() => _isChecking = false);
  }

  // ── Import ────────────────────────────────────────────────
  Future<void> _importToFirestore() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // Validate new products have stock filled
    for (final name in _aggregated.keys) {
      if (_existingStock[name] == null) {
        final val = _stockControllers[name]?.text.trim() ?? '';
        if (val.isEmpty || int.tryParse(val) == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" needs an initial stock before importing'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    // ── Build all write operations in memory first ────────────
    // No Firestore calls here — just prepare data
    final List<Map<String, dynamic>> updates = [];
    final List<Map<String, dynamic>> creates = [];

    int lowStockCount = 0;

    for (final entry in _aggregated.values) {
      final isExisting = _existingStock[entry.name] != null;

      if (isExisting) {
        final currentStock = _existingStock[entry.name]!;
        final newStock = currentStock - entry.totalQty;
        if (newStock <= 0) lowStockCount++;

        updates.add({
          'docId': entry.docId,
          'stock': newStock,
          'price': entry.price,
        });
      } else {
        final initialStock =
            int.tryParse(_stockControllers[entry.name]!.text.trim()) ?? 0;
        final newStock = initialStock - entry.totalQty;
        if (newStock <= 0) lowStockCount++;

        creates.add({
          'name': entry.name,
          'price': entry.price,
          'cost': 0.0,
          'stock': newStock,
          'recPrice': entry.price,
          'source': _platformLabel,
        });
      }
    }

    // ── Navigate away immediately ─────────────────────────────
    // Do writes after navigation so UI never freezes
    if (mounted) {
      final msg = StringBuffer('✓ ');
      if (updates.isNotEmpty) msg.write('${updates.length} updated');
      if (creates.isNotEmpty) {
        if (updates.isNotEmpty) msg.write(', ');
        msg.write('${creates.length} added');
      }

      // Show snackbar on the PARENT screen using root messenger
      final rootMessenger = ScaffoldMessenger.of(context);

      Navigator.popUntil(context, (route) => route.isFirst);

      rootMessenger.showSnackBar(
        SnackBar(
          content: Text(msg.toString()),
          backgroundColor: lowStockCount > 0
              ? Colors.orangeAccent
              : AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    // ── Write to Firestore in background ─────────────────────
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('products');
      final batch = FirebaseFirestore.instance.batch();
      final Map<String, int> salesByDay = {
        'Mon': 0,
        'Tue': 0,
        'Wed': 0,
        'Thu': 0,
        'Fri': 0,
        'Sat': 0,
        'Sun': 0,
      };
      const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (final p in _products) {
        if (p.date.isNotEmpty) {
          try {
            final dt = DateTime.tryParse(p.date.replaceAll('/', '-'));
            if (dt != null) {
              salesByDay[dayNames[dt.weekday - 1]] =
                  (salesByDay[dayNames[dt.weekday - 1]] ?? 0) + p.quantity;
            }
          } catch (_) {}
        }
      }

      for (final u in updates) {
        batch.update(col.doc(u['docId'] as String), {
          'stock': u['stock'],
          'price': u['price'],
          'lastImport': FieldValue.serverTimestamp(),
          'lastImportSource': _platformLabel,
        });
      }

      for (final c in creates) {
        batch.set(col.doc(), {
          ...c,
          'createdAt': FieldValue.serverTimestamp(),
          'lastImport': FieldValue.serverTimestamp(),
          'lastImportSource': _platformLabel,
        });
      }

      await batch.commit();

      // Log import
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sales_log')
          .add({
            'platform': _platformLabel,
            'fileName': widget.fileName,
            'totalOrders': _products.length,
            'totalProducts': _aggregated.length,
            'importedAt': FieldValue.serverTimestamp(),
            'salesByDay': salesByDay, // ← NEW
            'products': _aggregated.values
                .map(
                  (p) => {
                    'name': p.name,
                    'qtySold': p.totalQty,
                    'price': p.price,
                  },
                )
                .toList(),
          });
    } catch (e) {
      debugPrint('Background write failed: $e');
    }
  }

  String get _platformLabel {
    switch (_platform) {
      case CsvPlatform.shopee:
        return 'Shopee';
      case CsvPlatform.tiktok:
        return 'TikTok Shop';
      default:
        return 'Other';
    }
  }

  Color get _platformColor {
    switch (_platform) {
      case CsvPlatform.shopee:
        return const Color(0xFFEE4D2D);
      case CsvPlatform.tiktok:
        return const Color(0xFF69C9D0);
      default:
        return AppColors.primary;
    }
  }

  // ── How many new products need stock input ────────────────
  int get _newProductCount =>
      _existingStock.values.where((v) => v == null).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Preview Import',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isChecking
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Checking existing products...',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // ── File info banner ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.insert_drive_file_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.fileName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_products.length} orders · ${_aggregated.length} products · $_newProductCount new',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _platformColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _platformColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _platformLabel,
                            style: TextStyle(
                              color: _platformColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── New products notice ─────────────────────
                if (_newProductCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$_newProductCount new product(s) found — enter initial stock so deductions are accurate.',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Deduct notice ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.orangeAccent,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Units sold will be deducted from stock after import.',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // ── Column labels ───────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: const [
                      Expanded(
                        child: Text(
                          'PRODUCT',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          'STOCK / SOLD',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── Product list ────────────────────────────
                Expanded(
                  child: _aggregated.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _aggregated.length,
                          itemBuilder: (context, index) {
                            final item = _aggregated.values.elementAt(index);
                            final isNew = _existingStock[item.name] == null;
                            return isNew
                                ? _buildNewProductRow(item, index)
                                : _buildExistingProductRow(item, index);
                          },
                        ),
                ),

                // ── Bottom action ───────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStat('Products', '${_aggregated.length}'),
                          _buildStat('Orders', '${_products.length}'),
                          _buildStat(
                            'Units Sold',
                            '${_aggregated.values.fold<int>(0, (s, p) => s + p.totalQty)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSaving || _aggregated.isEmpty
                              ? null
                              : _importToFirestore,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(Icons.cloud_upload_outlined),
                          label: Text(
                            _isSaving
                                ? 'Importing...'
                                : 'Import ${_aggregated.length} Products',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
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
  }

  // ── Existing product row ──────────────────────────────────
  Widget _buildExistingProductRow(_AggregatedProduct item, int index) {
    final currentStock = _existingStock[item.name] ?? 0;
    final afterStock = currentStock - item.totalQty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Index
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'RM ${item.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Stock flow: current → after
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    '$currentStock',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '$afterStock',
                    style: TextStyle(
                      color: afterStock <= 0
                          ? Colors.redAccent
                          : Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '-${item.totalQty} sold',
                style: const TextStyle(color: Colors.redAccent, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── New product row with stock input ─────────────────────
  Widget _buildNewProductRow(_AggregatedProduct item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Index with "NEW" tint
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'RM ${item.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Initial stock input
          Row(
            children: [
              const Expanded(
                flex: 2,
                child: Text(
                  'How many units do you have in stock?',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                height: 40,
                child: TextField(
                  controller: _stockControllers[item.name],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.primary.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),

          // Live preview of stock after deduction
          if ((_stockControllers[item.name]?.text ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Builder(
                builder: (context) {
                  final initial =
                      int.tryParse(_stockControllers[item.name]!.text.trim()) ??
                      0;
                  final afterStock = initial - item.totalQty;
                  return Row(
                    children: [
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'After import: $afterStock in stock',
                        style: TextStyle(
                          fontSize: 11,
                          color: afterStock <= 0
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (afterStock <= 0)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text(
                            '⚠️ Out of stock',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 48,
            color: AppColors.textSecondary,
          ),
          SizedBox(height: 12),
          Text(
            'No valid products found',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'Check that your CSV matches Shopee or TikTok format',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AggregatedProduct {
  final String name;
  final double price;
  int totalQty;
  int orderCount;
  String? docId; // set after Firestore check

  _AggregatedProduct({
    required this.name,
    required this.price,
    required this.totalQty,
    required this.orderCount,
    this.docId,
  });
}
