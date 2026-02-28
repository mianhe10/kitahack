import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kitahack/screens/csv_mapping_screen.dart';
import '../theme/app_colors.dart';
import '../constants/app_constants.dart';
import '../services/data_ingestion_service.dart';
import '../services/gemini_service.dart';
import 'header_confirmation_screen.dart';
import 'manual_product_screen.dart';
import 'csv_preview_screen.dart';
import 'edit_product_screen.dart';
import '../widgets/csv_parser.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DataIngestionService _dataService = DataIngestionService(
    apiKey: AppConstants.geminiApiKey,
  );

  final _firestore = FirebaseFirestore.instance;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  bool _isProcessing = false;
  bool _isDeleting = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};
  final Set<String> _runningAiIds = {};

  String _sortBy = 'name';
  bool _sortAsc = true;
  String _filterBy = 'all';

  bool _isBulkAiRunning = false;
  bool _bulkAiCancelled = false;
  int _bulkAiProgress = 0;
  int _bulkAiTotal = 0;

  bool _isApplyingPrices = false;

  CollectionReference get _productsCol =>
      _firestore.collection('users').doc(_uid).collection('products');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  String _timeAgo(dynamic timestamp) {
    if (timestamp == null) return '';
    if (timestamp is! Timestamp) return '';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  void _exitSelectMode() => setState(() {
    _isSelectMode = false;
    _selectedIds.clear();
  });

  void _selectAll(List<QueryDocumentSnapshot> docs) =>
      setState(() => _selectedIds.addAll(docs.map((d) => d.id)));

  void _showSnackBar(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

  // ─────────────────────────────────────────────────────────
  // DELETE SELECTED
  // ─────────────────────────────────────────────────────────

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Products?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will permanently delete $count selected product${count > 1 ? 's' : ''}. This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete $count'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _isDeleting = true);
    try {
      final batch = _firestore.batch();
      for (final id in _selectedIds) batch.delete(_productsCol.doc(id));
      await batch.commit();
      if (mounted) {
        _exitSelectMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count product${count > 1 ? 's' : ''} deleted'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Error deleting: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // PER-CARD AI
  // ─────────────────────────────────────────────────────────

  Future<void> _runAiForProduct(
    String docId,
    Map<String, dynamic> product,
  ) async {
    if (_runningAiIds.contains(docId)) return;
    setState(() => _runningAiIds.add(docId));
    try {
      final result = await GeminiService.analyseSingleProduct(
        id: docId,
        name: product['name'] ?? '',
        price: (product['price'] ?? 0).toDouble(),
        stock: (product['stock'] ?? 0) as int,
        unitsSold: product['unitsSold'] ?? 0,
      );
      await _productsCol.doc(docId).update(result.toFirestoreMap());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (product['isAiReady'] ?? false)
                  ? 'Price re-analysed for "${product['name']}"!'
                  : 'AI analysis done for "${product['name']}"!',
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI failed: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _runningAiIds.remove(docId));
    }
  }

  // ─────────────────────────────────────────────────────────
  // BULK AI
  // ─────────────────────────────────────────────────────────

  Future<void> _runAiForAllProducts({bool reanalyseAll = false}) async {
    final snapshot = await _productsCol.get();
    final targets = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return reanalyseAll ? true : !(data['isAiReady'] ?? false);
    }).toList();

    if (targets.isEmpty) {
      _showSnackBar(context, 'No products found!');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          reanalyseAll
              ? 'Re-analyse All Products?'
              : 'Run AI for All Products?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          reanalyseAll
              ? 'This will re-analyse all ${targets.length} products with fresh market data.'
              : 'This will analyse ${targets.length} unanalysed product${targets.length > 1 ? 's' : ''} in batches.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              reanalyseAll ? 'Re-analyse All' : 'Run All',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isBulkAiRunning = true;
      _bulkAiCancelled = false;
      _bulkAiProgress = 0;
      _bulkAiTotal = targets.length;
    });

    const int batchSize = 5;
    try {
      for (int i = 0; i < targets.length; i += batchSize) {
        if (_bulkAiCancelled || !mounted) break;
        final end = (i + batchSize < targets.length)
            ? i + batchSize
            : targets.length;
        final chunk = targets.sublist(i, end);
        final batchInput = chunk.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'price': (data['price'] ?? 0).toDouble(),
            'stock': (data['stock'] ?? 0) as int,
            'sold': data['unitsSold'] ?? 0,
          };
        }).toList();

        try {
          final results = await GeminiService.analyseBatch(batchInput);
          if (!mounted || _bulkAiCancelled) break;
          final writeBatch = _firestore.batch();
          for (final result in results) {
            writeBatch.update(
              _productsCol.doc(result.id),
              result.toFirestoreMap(),
            );
          }
          await writeBatch.commit();
        } catch (e) {
          debugPrint('Bulk AI batch error at index $i: $e');
        }

        if (mounted)
          setState(
            () => _bulkAiProgress = (i + batchSize).clamp(0, _bulkAiTotal),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBulkAiRunning = false;
          _bulkAiCancelled = false;
          _bulkAiProgress = 0;
          _bulkAiTotal = 0;
        });
        _showSnackBar(
          context,
          _bulkAiCancelled
              ? 'AI analysis cancelled.'
              : reanalyseAll
              ? 'Re-analysis complete for all products!'
              : 'AI analysis complete for all products!',
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // BULK APPLY PRICES
  // ─────────────────────────────────────────────────────────

  Future<void> _showApplyPricesSheet() async {
    final snapshot = await _productsCol.get();
    final candidates = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (!(data['isAiReady'] ?? false)) return false;
      final double price = (data['price'] ?? 0).toDouble();
      final double recPrice = (data['recPrice'] ?? price).toDouble();
      return recPrice != price;
    }).toList();

    if (candidates.isEmpty) {
      if (mounted)
        _showSnackBar(context, 'All prices are already at recommended values!');
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ApplyPricesSheet(
        candidates: candidates,
        onApply: (docsToApply) async {
          Navigator.pop(ctx);
          await _applyRecommendedPrices(docsToApply);
        },
      ),
    );
  }

  Future<void> _applyRecommendedPrices(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isApplyingPrices = true);
    try {
      final batch = _firestore.batch();
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final double recPrice = (data['recPrice'] ?? data['price'] ?? 0)
            .toDouble();
        batch.update(_productsCol.doc(doc.id), {
          'price': recPrice,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${docs.length} price${docs.length > 1 ? 's' : ''} updated!',
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Error applying prices: $e');
    } finally {
      if (mounted) setState(() => _isApplyingPrices = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // FILE PICKER
  // ─────────────────────────────────────────────────────────

  Future<void> _pickCSVFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result != null && mounted) {
        final file = result.files.single;
        if (file.bytes == null) return;
        final content = String.fromCharCodes(file.bytes!);
        final firstLine = content.split('\n').first.trim();
        final headers = firstLine
            .split(',')
            .map((h) => h.replaceAll('"', '').trim())
            .where((h) => h.isNotEmpty)
            .toList();

        final platform = CsvParser.detectPlatform(headers);
        if (platform != CsvPlatform.unknown) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CsvPreviewScreen(fileName: file.name, fileBytes: file.bytes!),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  CSVMappingScreen(fileName: file.name, csvHeaders: headers),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('File picking error: $e');
    }
  }

  Future<void> _startFullDataAnalysis(
    Map<String, String> mapping,
    List<List<dynamic>> fields,
    List<String> headers,
  ) async {
    try {
      setState(() => _isProcessing = true);
      List<Map<String, dynamic>> parsedProducts = [];

      for (int i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.isEmpty || row.join('').trim().isEmpty) continue;

        String getValue(String internalKey) {
          final targetHeader = mapping[internalKey];
          if (targetHeader == null) return '0';
          final index = headers.indexWhere(
            (h) => h.trim().toLowerCase() == targetHeader.trim().toLowerCase(),
          );
          if (index == -1 || index >= row.length) return '0';
          return row[index].toString().trim();
        }

        double cleanDouble(String val) =>
            double.tryParse(val.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
        int cleanInt(String val) =>
            int.tryParse(val.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

        final title = getValue('prod_id');
        final finalTitle = (title == '0' || title.isEmpty)
            ? 'Unnamed Product (Row $i)'
            : title;

        parsedProducts.add({
          'id': finalTitle,
          'name': finalTitle,
          'price': cleanDouble(getValue('price')),
          'recPrice': cleanDouble(getValue('price')),
          'stock': cleanInt(getValue('qty')),
          'unitsSold': cleanInt(getValue('units_sold')),
          'isAiReady': false,
          'aiAdvice': '',
        });
      }

      if (parsedProducts.isEmpty) {
        if (mounted) _showSnackBar(context, 'No items found. Check your CSV.');
        return;
      }

      final batch = _firestore.batch();
      for (final p in parsedProducts) {
        batch.set(
          _productsCol.doc(p['id'] as String),
          p,
          SetOptions(merge: true),
        );
      }
      await batch.commit();

      if (mounted)
        _showSnackBar(
          context,
          "Import complete! Tap 'Run AI' on any product to analyse.",
        );
    } catch (e) {
      if (mounted) _showSnackBar(context, 'Error processing data: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _navigateToConfirmation(
    BuildContext context,
    Map<String, String> aiMapping,
    List<String> headers,
    List<List<dynamic>> fields,
  ) async {
    final confirmedMapping = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => HeaderConfirmationScreen(
          aiSuggestedMapping: aiMapping,
          allCsvHeaders: headers,
          filePath: 'web_upload.csv',
        ),
      ),
    );
    if (confirmedMapping != null && context.mounted) {
      await _dataService.saveTemplate(headers, confirmedMapping);
      _showSnackBar(context, 'Mapping confirmed! Importing products...');
      _startFullDataAnalysis(confirmedMapping, fields, headers);
    }
  }

  // ─────────────────────────────────────────────────────────
  // MAIN BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectMode) {
          _exitSelectMode();
          return false;
        }
        return true;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: AppColors.background,

        body: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── STICKY: search + filter ──
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    height: _isSelectMode ? 64 : 124,
                    child: Container(
                      color: AppColors.background,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isSelectMode
                              ? _buildSelectModeHeader()
                              : _buildSearchBar(),
                          if (!_isSelectMode) ...[
                            const SizedBox(height: 8),
                            _buildSortFilterBar(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Data Source card ──
                if (!_isSelectMode)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _buildDataSourceCard(),
                    ),
                  ),

                // ── Inventory header + banners ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _buildInventoryHeader(),
                  ),
                ),

                // ── Product list ──
                _buildProductSliverList(),

                // ── Bottom padding ──
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),

            // ── Processing overlay ──
            if (_isProcessing || _isDeleting || _isApplyingPrices)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: AppColors.primary),
                      const SizedBox(height: 16),
                      Text(
                        _isDeleting
                            ? 'Deleting...'
                            : _isApplyingPrices
                            ? 'Applying prices...'
                            : 'Processing...',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Bulk AI overlay ──
            if (_isBulkAiRunning)
              Container(
                color: Colors.black.withValues(alpha: 0.75),
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                          size: 36,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Running AI Analysis',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Analysing ${_bulkAiProgress.clamp(0, _bulkAiTotal)} / $_bulkAiTotal products...',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _bulkAiTotal > 0
                                ? _bulkAiProgress / _bulkAiTotal
                                : 0,
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.primary,
                            ),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                          onPressed: () =>
                              setState(() => _bulkAiCancelled = true),
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 16,
                          ),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _isSelectMode && _selectedIds.isNotEmpty
            ? _buildDeleteBar()
            : null,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SELECT MODE HEADER
  // ─────────────────────────────────────────────────────────

  Widget _buildSelectModeHeader() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            onPressed: _exitSelectMode,
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_selectedIds.length} selected',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: _productsCol.snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final allSelected =
                  docs.isNotEmpty &&
                  docs.every((d) => _selectedIds.contains(d.id));
              return TextButton(
                onPressed: () => allSelected
                    ? setState(() => _selectedIds.clear())
                    : _selectAll(docs),
                child: Text(
                  allSelected ? 'Deselect All' : 'Select All',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DELETE BOTTOM BAR
  // ─────────────────────────────────────────────────────────

  Widget _buildDeleteBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _deleteSelected,
        icon: const Icon(Icons.delete_outline_rounded),
        label: Text(
          'Delete ${_selectedIds.length} Product${_selectedIds.length > 1 ? 's' : ''}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DATA SOURCE CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildDataSourceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Data Source',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Import sales data or manually manage your inventory.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _pickCSVFile,
            icon: const Icon(Icons.upload_file),
            label: const Text(
              'Upload Sales CSV',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManualProductScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add Product Manually'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // PRODUCT SLIVER LIST
  // ─────────────────────────────────────────────────────────

  Widget _buildProductSliverList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _productsCol.snapshots(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        }

        // Empty collection → show empty state WITHOUT filling remaining space
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(child: _buildEmptyState());
        }

        List<QueryDocumentSnapshot> docs = snapshot.data!.docs;

        // Search
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final name = ((doc.data() as Map<String, dynamic>)['name'] ?? '')
                .toString()
                .toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();
        }

        // Filter
        if (_filterBy == 'lowStock') {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final int threshold = (data['lowStockThreshold'] ?? 10) as int;
            final int stock = (data['stock'] ?? 0) as int;
            return stock > 0 && stock < threshold;
          }).toList();
        } else if (_filterBy == 'aiReady') {
          docs = docs
              .where(
                (doc) =>
                    (doc.data() as Map<String, dynamic>)['isAiReady'] == true,
              )
              .toList();
        } else if (_filterBy == 'notAnalysed') {
          docs = docs
              .where(
                (doc) =>
                    !((doc.data() as Map<String, dynamic>)['isAiReady'] ??
                        false),
              )
              .toList();
        }

        // Sort
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          int cmp;
          switch (_sortBy) {
            case 'price':
              cmp = ((aData['price'] ?? 0) as num).compareTo(
                (bData['price'] ?? 0) as num,
              );
              break;
            case 'stock':
              cmp = ((aData['stock'] ?? 0) as num).compareTo(
                (bData['stock'] ?? 0) as num,
              );
              break;
            case 'aiReady':
              cmp = (bData['isAiReady'] == true ? 1 : 0).compareTo(
                aData['isAiReady'] == true ? 1 : 0,
              );
              break;
            default:
              cmp = (aData['name'] ?? '').toString().compareTo(
                (bData['name'] ?? '').toString(),
              );
          }
          return _sortAsc ? cmp : -cmp;
        });

        // Empty after filter
        if (docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list_off_rounded,
                      size: 40,
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'No products match "$_searchQuery"'
                          : 'No products match this filter',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final doc = docs[index];
              return _buildInventoryItem(
                doc.id,
                doc.data() as Map<String, dynamic>,
              );
            }, childCount: docs.length),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // INVENTORY CARD  (SafeArea removed — was causing per-card padding issues)
  // ─────────────────────────────────────────────────────────

  Widget _buildInventoryItem(String docId, Map<String, dynamic> product) {
    final double price = (product['price'] ?? 0).toDouble();
    final double recPrice = (product['recPrice'] ?? price).toDouble();
    final int stock = (product['stock'] ?? 0) as int;
    final String title = product['name'] ?? 'Unnamed';
    final bool isAiReady = product['isAiReady'] ?? false;
    final String aiAdvice = product['aiAdvice'] ?? '';
    final bool isSelected = _selectedIds.contains(docId);
    final bool isRunningAi = _runningAiIds.contains(docId);
    final int lowStockThreshold = (product['lowStockThreshold'] ?? 10) as int;
    final bool isLowStock = stock > 0 && stock < lowStockThreshold;
    final String updatedAgo = _timeAgo(product['updatedAt']);

    final bool isUp = isAiReady && recPrice > price;
    final bool isDown = isAiReady && recPrice < price;
    final Color trendColor = isUp
        ? Colors.greenAccent
        : isDown
        ? Colors.redAccent
        : AppColors.textSecondary;
    final IconData trendIcon = isUp
        ? Icons.trending_up
        : isDown
        ? Icons.trending_down
        : Icons.remove;

    return GestureDetector(
      onLongPress: () {
        if (!_isSelectMode) {
          setState(() {
            _isSelectMode = true;
            _selectedIds.add(docId);
          });
        }
      },
      onTap: () {
        if (_isSelectMode) {
          setState(() {
            if (_selectedIds.contains(docId)) {
              _selectedIds.remove(docId);
              if (_selectedIds.isEmpty) _isSelectMode = false;
            } else {
              _selectedIds.add(docId);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EditProductScreen(docId: docId, product: product),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.redAccent.withValues(alpha: 0.15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.6),
                  width: 1.5,
                )
              : isLowStock
              ? Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.4),
                  width: 1,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // ── Icon or checkbox ──
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isSelectMode
                        ? Container(
                            key: const ValueKey('checkbox'),
                            height: 55,
                            width: 55,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: isSelected
                                  ? Colors.redAccent.withValues(alpha: 0.2)
                                  : Colors.white10,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.redAccent
                                    : AppColors.textSecondary.withValues(
                                        alpha: 0.3,
                                      ),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              isSelected
                                  ? Icons.check_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: isSelected
                                  ? Colors.redAccent
                                  : AppColors.textSecondary,
                              size: 22,
                            ),
                          )
                        : Container(
                            key: const ValueKey('icon'),
                            height: 55,
                            width: 55,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white10,
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),

                  // ── Name + price + rec ──
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'RM ${price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isAiReady)
                          Row(
                            children: [
                              Icon(trendIcon, size: 14, color: trendColor),
                              const SizedBox(width: 4),
                              Text(
                                'Rec: RM ${recPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: trendColor,
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Icon(
                                Icons.hourglass_empty_rounded,
                                size: 13,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Rec: Not analysed yet',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.6,
                                  ),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        if (updatedAgo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 11,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Updated $updatedAgo',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Right column: badges ──
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!_isSelectMode) ...[
                        const Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (isAiReady)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'AI READY',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: stock == 0
                              ? Colors.red.withValues(alpha: 0.15)
                              : isLowStock
                              ? Colors.orangeAccent.withValues(alpha: 0.15)
                              : Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLowStock) ...[
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 11,
                                color: Colors.orangeAccent,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              stock == 0
                                  ? 'Out of stock'
                                  : isLowStock
                                  ? 'Low: $stock left'
                                  : '$stock in stock',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: stock == 0
                                    ? Colors.redAccent
                                    : isLowStock
                                    ? Colors.orangeAccent
                                    : Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // ── AI advice banner ──
              if (isAiReady && !_isSelectMode) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          aiAdvice.isNotEmpty
                              ? aiAdvice
                              : 'Tap 🔄 to get AI pricing advice for this product.',
                          style: TextStyle(
                            color: aiAdvice.isNotEmpty
                                ? AppColors.textSecondary
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.6,
                                  ),
                            fontSize: 11,
                            fontStyle: aiAdvice.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: isRunningAi
                            ? null
                            : () => _runAiForProduct(docId, product),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: isRunningAi
                              ? const SizedBox(
                                  height: 11,
                                  width: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh_rounded,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Run AI button ──
              if (!isAiReady && !_isSelectMode) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    onPressed: isRunningAi
                        ? null
                        : () => _runAiForProduct(docId, product),
                    icon: isRunningAi
                        ? const SizedBox(
                            height: 13,
                            width: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 14),
                    label: Text(
                      isRunningAi ? 'Analysing...' : 'Run AI Price Analysis',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // INVENTORY HEADER
  // ─────────────────────────────────────────────────────────

  Widget _buildInventoryHeader() {
    return StreamBuilder<QuerySnapshot>(
      stream: _productsCol.snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final count = docs.length;
        final unanalysedCount = docs
            .where(
              (doc) =>
                  !((doc.data() as Map<String, dynamic>)['isAiReady'] ?? false),
            )
            .length;
        final hasPriceDiffs = docs.any((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (!(data['isAiReady'] ?? false)) return false;
          return (data['recPrice'] ?? data['price'] ?? 0).toDouble() !=
              (data['price'] ?? 0).toDouble();
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Product Inventory',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '$count Items',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    if (!_isSelectMode && count > 0) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() => _isSelectMode = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.checklist_rounded,
                                size: 13,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Select',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            // Apply Prices banner
            if (!_isSelectMode && hasPriceDiffs && !_isBulkAiRunning) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _showApplyPricesSheet,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.greenAccent.withValues(alpha: 0.15),
                        Colors.greenAccent.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.price_check_rounded,
                          color: Colors.greenAccent,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Apply Recommended Prices',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Review & apply AI price suggestions in bulk',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.greenAccent,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Run AI for all banner
            if (!_isSelectMode && unanalysedCount > 0 && !_isBulkAiRunning) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _runAiForAllProducts,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$unanalysedCount product${unanalysedCount > 1 ? 's' : ''} not yet analysed',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Tap to run AI price analysis for all',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.primary,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Re-analyse all banner
            if (!_isSelectMode &&
                count > 0 &&
                unanalysedCount == 0 &&
                !_isBulkAiRunning) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _runAiForAllProducts(reanalyseAll: true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.refresh_rounded,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Re-analyse all products',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Refresh pricing with latest market data',
                              style: TextStyle(
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.7,
                                ),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // SORT & FILTER BAR
  // ─────────────────────────────────────────────────────────

  Widget _buildSortFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip(label: 'All', value: 'all', icon: Icons.apps_rounded),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Low Stock',
            value: 'lowStock',
            icon: Icons.warning_amber_rounded,
            activeColor: Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'AI Ready',
            value: 'aiReady',
            icon: Icons.auto_awesome,
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Not Analysed',
            value: 'notAnalysed',
            icon: Icons.hourglass_empty_rounded,
            activeColor: AppColors.textSecondary,
          ),
          const SizedBox(width: 16),
          Container(height: 20, width: 1, color: Colors.white12),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sort_rounded,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _sortLabel(),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _sortAsc
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel() {
    switch (_sortBy) {
      case 'price':
        return 'Price';
      case 'stock':
        return 'Stock';
      case 'aiReady':
        return 'AI Ready';
      default:
        return 'Name';
    }
  }

  Widget _filterChip({
    required String label,
    required String value,
    required IconData icon,
    Color? activeColor,
  }) {
    final isActive = _filterBy == value;
    final color = activeColor ?? AppColors.primary;
    return GestureDetector(
      onTap: () => setState(() => _filterBy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? color.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.5) : Colors.white12,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 13,
              color: isActive ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort By',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              ...[
                ('name', 'Name', Icons.sort_by_alpha_rounded),
                ('price', 'Price', Icons.sell_outlined),
                ('stock', 'Stock Level', Icons.inventory_2_outlined),
                ('aiReady', 'AI Ready First', Icons.auto_awesome),
              ].map((item) {
                final isSelected = _sortBy == item.$1;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.$3,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  title: Text(
                    item.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  trailing: isSelected
                      ? GestureDetector(
                          onTap: () {
                            setState(() => _sortAsc = !_sortAsc);
                            setSheetState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _sortAsc
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      if (_sortBy == item.$1) {
                        _sortAsc = !_sortAsc;
                      } else {
                        _sortBy = item.$1;
                        _sortAsc = true;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SEARCH BAR
  // ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white),
      onChanged: (val) => setState(() => _searchQuery = val),
      decoration: InputDecoration(
        hintText: 'Search products...',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(
                  Icons.clear,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No products yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Start by adding your products manually or uploading a sales CSV.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 28),
          _buildSetupStep(
            '1',
            'Add products manually with stock count',
            Icons.add_box_outlined,
          ),
          const SizedBox(height: 10),
          _buildSetupStep(
            '2',
            'Upload Shopee or TikTok sales CSV',
            Icons.upload_file_outlined,
          ),
          const SizedBox(height: 10),
          _buildSetupStep(
            '3',
            'Tap "Run AI Price Analysis" on any product to get pricing insights',
            Icons.auto_awesome_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep(String step, String label, IconData icon) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, color: AppColors.textSecondary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STICKY HEADER DELEGATE
// ─────────────────────────────────────────────────────────────────────────────

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  const _StickyHeaderDelegate({required this.child, required this.height});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);

  @override
  double get maxExtent => height;
  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _StickyHeaderDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

// ─────────────────────────────────────────────────────────────────────────────
// APPLY PRICES BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ApplyPricesSheet extends StatefulWidget {
  final List<QueryDocumentSnapshot> candidates;
  final Future<void> Function(List<QueryDocumentSnapshot>) onApply;
  const _ApplyPricesSheet({required this.candidates, required this.onApply});

  @override
  State<_ApplyPricesSheet> createState() => _ApplyPricesSheetState();
}

class _ApplyPricesSheetState extends State<_ApplyPricesSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.candidates
        .where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['recPrice'] ?? data['price'] ?? 0).toDouble() >
              (data['price'] ?? 0).toDouble();
        })
        .map((d) => d.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final increases = widget.candidates.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['recPrice'] ?? data['price'] ?? 0).toDouble() >
          (data['price'] ?? 0).toDouble();
    }).length;
    final decreases = widget.candidates.length - increases;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.price_check_rounded,
                      color: Colors.greenAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Apply Recommended Prices',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryChip(
                      '↑ $increases increase${increases != 1 ? 's' : ''}',
                      Colors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    _summaryChip(
                      '↓ $decreases decrease${decreases != 1 ? 's' : ''}',
                      Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _quickSelectBtn(
                        'Select All',
                        () => setState(
                          () => _selected = widget.candidates
                              .map((d) => d.id)
                              .toSet(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _quickSelectBtn(
                        'Only Increases',
                        () => setState(() {
                          _selected = widget.candidates
                              .where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return (data['recPrice'] ?? data['price'] ?? 0)
                                        .toDouble() >
                                    (data['price'] ?? 0).toDouble();
                              })
                              .map((d) => d.id)
                              .toSet();
                        }),
                      ),
                      const SizedBox(width: 8),
                      _quickSelectBtn(
                        'Deselect All',
                        () => setState(() => _selected.clear()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: Colors.white10),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: widget.candidates.length,
              itemBuilder: (ctx, i) {
                final doc = widget.candidates[i];
                final data = doc.data() as Map<String, dynamic>;
                final double price = (data['price'] ?? 0).toDouble();
                final double recPrice = (data['recPrice'] ?? price).toDouble();
                final double diff = recPrice - price;
                final bool isIncrease = diff > 0;
                final bool isChecked = _selected.contains(doc.id);

                return GestureDetector(
                  onTap: () => setState(() {
                    if (isChecked)
                      _selected.remove(doc.id);
                    else
                      _selected.add(doc.id);
                  }),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isChecked
                          ? (isIncrease
                                ? Colors.greenAccent.withValues(alpha: 0.08)
                                : Colors.redAccent.withValues(alpha: 0.08))
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isChecked
                            ? (isIncrease
                                  ? Colors.greenAccent.withValues(alpha: 0.4)
                                  : Colors.redAccent.withValues(alpha: 0.4))
                            : Colors.white12,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isChecked
                                ? (isIncrease
                                      ? Colors.greenAccent
                                      : Colors.redAccent)
                                : Colors.transparent,
                            border: Border.all(
                              color: isChecked
                                  ? Colors.transparent
                                  : Colors.white30,
                              width: 1.5,
                            ),
                          ),
                          child: isChecked
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.black,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            data['name'] ?? 'Unnamed',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'RM ${price.toStringAsFixed(2)} → RM ${recPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${isIncrease ? '+' : ''}RM ${diff.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: isIncrease
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected.isEmpty
                    ? Colors.white10
                    : AppColors.primary,
                foregroundColor: _selected.isEmpty
                    ? AppColors.textSecondary
                    : Colors.black,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final toApply = widget.candidates
                          .where((d) => _selected.contains(d.id))
                          .toList();
                      widget.onApply(toApply);
                    },
              child: Text(
                _selected.isEmpty
                    ? 'Select products to apply'
                    : 'Apply ${_selected.length} Price${_selected.length > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );

  Widget _quickSelectBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      ),
    ),
  );
}
