import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';

class CSVMappingScreen extends StatefulWidget {
  final String fileName;
  final List<String> csvHeaders; // ← real headers passed in

  const CSVMappingScreen({
    super.key,
    required this.fileName,
    required this.csvHeaders,
  });

  @override
  State<CSVMappingScreen> createState() => _CSVMappingScreenState();
}

class _CSVMappingScreenState extends State<CSVMappingScreen> {
  final _formKey = GlobalKey<FormState>();

  String? productNameColumn;
  String? quantityColumn;
  String? priceColumn;
  String? dateColumn;

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
          'Map CSV Columns',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── File info ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
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
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.csvHeaders.length} columns detected',
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

              const SizedBox(height: 24),

              const Text(
                'Match your CSV columns to required fields',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Select which column in your CSV matches each field.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),

              const SizedBox(height: 24),

              Expanded(
                child: ListView(
                  children: [
                    _buildDropdownField(
                      label: 'Product Name',
                      icon: Icons.label_outline,
                      value: productNameColumn,
                      onChanged: (val) =>
                          setState(() => productNameColumn = val),
                    ),
                    _buildDropdownField(
                      label: 'Quantity Sold',
                      icon: Icons.numbers,
                      value: quantityColumn,
                      onChanged: (val) => setState(() => quantityColumn = val),
                    ),
                    _buildDropdownField(
                      label: 'Selling Price',
                      icon: Icons.attach_money,
                      value: priceColumn,
                      onChanged: (val) => setState(() => priceColumn = val),
                    ),
                    _buildDropdownField(
                      label: 'Date',
                      icon: Icons.calendar_today_outlined,
                      value: dateColumn,
                      onChanged: (val) => setState(() => dateColumn = val),
                    ),
                  ],
                ),
              ),

              // ── Confirm button ─────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _validateAndSubmit,
                  child: const Text(
                    'Confirm & Import',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: AppColors.card,
        style: const TextStyle(color: AppColors.textPrimary),
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: AppColors.textSecondary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
          prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
          ),
        ),
        // ← Real column names from the CSV
        items: widget.csvHeaders
            .map(
              (header) => DropdownMenuItem(
                value: header,
                child: Text(
                  header,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? 'Please select a column' : null,
      ),
    );
  }

  void _validateAndSubmit() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV successfully mapped!'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }
}
