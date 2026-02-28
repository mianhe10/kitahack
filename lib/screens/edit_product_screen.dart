import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/gemini_service.dart';

class EditProductScreen extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> product;

  const EditProductScreen({
    super.key,
    required this.docId,
    required this.product,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _costController;
  late TextEditingController _stockAdjustController;
  late TextEditingController _lowStockThresholdController;

  static const int _defaultLowStockThreshold = 10;

  late int _currentStock;
  int _stockDelta = 0;
  bool _isSaving = false;
  bool _isRunningAI = false;

  // Track local AI ready state so UI updates instantly after run
  late bool _isAiReady;
  late String _aiAdvice;
  late double _recPrice;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name'] ?? '');
    _priceController = TextEditingController(
      text: (widget.product['price'] ?? 0.0).toStringAsFixed(2),
    );
    _costController = TextEditingController(
      text: (widget.product['cost'] ?? 0.0).toStringAsFixed(2),
    );
    _stockAdjustController = TextEditingController();
    _currentStock = (widget.product['stock'] ?? 0) as int;
    _lowStockThresholdController = TextEditingController(
      text: (widget.product['lowStockThreshold'] ?? _defaultLowStockThreshold)
          .toString(),
    );
    _isAiReady = widget.product['isAiReady'] ?? false;
    _aiAdvice = widget.product['aiAdvice'] ?? '';
    _recPrice = (widget.product['recPrice'] ?? widget.product['price'] ?? 0)
        .toDouble();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockAdjustController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  CollectionReference get _productsCol {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('products');
  }

  int get _previewStock => _currentStock + _stockDelta;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await _productsCol.doc(widget.docId).update({
        'name': _nameController.text.trim(),
        'price': double.tryParse(_priceController.text.trim()) ?? 0.0,
        'cost': double.tryParse(_costController.text.trim()) ?? 0.0,
        'stock': _previewStock,
        'lowStockThreshold':
            int.tryParse(_lowStockThresholdController.text.trim()) ??
            _defaultLowStockThreshold,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackBar('Product updated!', isError: false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _runAIAnalysis() async {
    setState(() => _isRunningAI = true);
    try {
      final result = await GeminiService.analyseSingleProduct(
        id: widget.docId,
        name: _nameController.text.trim(),
        price: double.tryParse(_priceController.text.trim()) ?? 0.0,
        stock: _previewStock,
        unitsSold: widget.product['unitsSold'] ?? 0,
      );

      await _productsCol.doc(widget.docId).update(result.toFirestoreMap());

      if (mounted) {
        setState(() {
          _isAiReady = true;
          _aiAdvice = result.aiAdvice;
          _recPrice = result.recommendedPrice;
        });
        _showSnackBar('AI analysis complete!', isError: false);
      }
    } catch (e) {
      if (mounted) _showSnackBar('AI failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isRunningAI = false);
    }
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Product?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'This will permanently remove "${_nameController.text.trim()}" from your inventory.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _productsCol.doc(widget.docId).delete();
      if (mounted) Navigator.pop(context);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
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
          'Edit Product',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Colors.redAccent,
            ),
            tooltip: 'Delete product',
            onPressed: _deleteProduct,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── AI insight banner (only when AI has run) ──
              if (_isAiReady && _aiAdvice.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Recommended: RM ${_recPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _aiAdvice,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── "Not analysed" placeholder (before AI runs) ──
              if (!_isAiReady) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty_rounded,
                        color: AppColors.textSecondary.withValues(alpha: 0.6),
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'AI price recommendation not available yet.\nRun the analysis below to get pricing insights.',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.7,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── Section: Product Info ──
              _sectionLabel('Product Info'),
              const SizedBox(height: 12),
              _buildField(
                controller: _nameController,
                label: 'Product Name',
                icon: Icons.inventory_2_outlined,
              ),
              _buildField(
                controller: _priceController,
                label: 'Selling Price (RM)',
                icon: Icons.sell_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
              ),
              _buildField(
                controller: _costController,
                label: 'Cost Price (RM)',
                icon: Icons.price_change_outlined,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                isRequired: false,
              ),

              const SizedBox(height: 8),

              // ── Section: Stock Management ──
              _sectionLabel('Stock Management'),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stockStat(
                          'Current',
                          _currentStock,
                          AppColors.textSecondary,
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                        _stockStat(
                          'After Save',
                          _previewStock,
                          _previewStock <= 0
                              ? Colors.redAccent
                              : Colors.greenAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        const Text(
                          'Quick Adjust:',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _quickBtn(-10, Colors.redAccent),
                        _quickBtn(-1, Colors.redAccent),
                        _quickBtn(1, Colors.greenAccent),
                        _quickBtn(10, Colors.greenAccent),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stockAdjustController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter amount...',
                              hintStyle: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: AppColors.primary.withValues(
                                alpha: 0.06,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _actionBtn(
                          label: '+ Add',
                          color: Colors.greenAccent,
                          onTap: () {
                            final val =
                                int.tryParse(
                                  _stockAdjustController.text.trim(),
                                ) ??
                                0;
                            if (val > 0) {
                              setState(() => _stockDelta += val);
                              _stockAdjustController.clear();
                            }
                          },
                        ),
                        const SizedBox(width: 6),
                        _actionBtn(
                          label: '- Remove',
                          color: Colors.redAccent,
                          onTap: () {
                            final val =
                                int.tryParse(
                                  _stockAdjustController.text.trim(),
                                ) ??
                                0;
                            if (val > 0) {
                              setState(() => _stockDelta -= val);
                              _stockAdjustController.clear();
                            }
                          },
                        ),
                      ],
                    ),

                    if (_stockDelta != 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            _stockDelta > 0
                                ? Icons.add_circle_outline
                                : Icons.remove_circle_outline,
                            size: 13,
                            color: _stockDelta > 0
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_stockDelta > 0 ? '+' : ''}$_stockDelta units pending save',
                            style: TextStyle(
                              fontSize: 11,
                              color: _stockDelta > 0
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _stockDelta = 0),
                            child: const Text(
                              'Reset',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 14),

                    // ── Low stock threshold ──
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Low Stock Alert Threshold',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Warn when stock falls below this number',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 70,
                          child: TextField(
                            controller: _lowStockThresholdController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.orangeAccent.withValues(
                                alpha: 0.08,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.orangeAccent.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: Colors.orangeAccent.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Colors.orangeAccent,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              hintText: '10',
                              hintStyle: TextStyle(
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Run AI Price Analysis button ──────────────
              _sectionLabel('AI Price Analysis'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAiReady
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.primary,
                    foregroundColor: _isAiReady
                        ? AppColors.primary
                        : Colors.black,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: _isAiReady
                          ? BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.4),
                            )
                          : BorderSide.none,
                    ),
                  ),
                  onPressed: _isRunningAI ? null : _runAIAnalysis,
                  icon: _isRunningAI
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _isAiReady
                                ? AppColors.primary
                                : Colors.black,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _isRunningAI
                        ? 'Analysing...'
                        : _isAiReady
                        ? 'Re-run AI Price Analysis'
                        : 'Run AI Price Analysis',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Save button ──────────────────────────────
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────

  Widget _sectionLabel(String label) => Text(
    label,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.bold,
    ),
  );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    bool isRequired = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        validator: (value) {
          if (!isRequired) return null;
          if (value == null || value.isEmpty) return 'Required';
          return null;
        },
      ),
    );
  }

  Widget _stockStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  Widget _quickBtn(int delta, Color color) {
    return GestureDetector(
      onTap: () => setState(() => _stockDelta += delta),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          '${delta > 0 ? '+' : ''}$delta',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
