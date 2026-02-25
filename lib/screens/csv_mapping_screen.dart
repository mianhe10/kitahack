import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class CSVMappingScreen extends StatefulWidget {
  final String fileName;

  const CSVMappingScreen({super.key, required this.fileName});

  @override
  State<CSVMappingScreen> createState() => _CSVMappingScreenState();
}

class _CSVMappingScreenState extends State<CSVMappingScreen> {
  final _formKey = GlobalKey<FormState>();

  // These will store selected mappings
  String? productNameColumn;
  String? quantityColumn;
  String? priceColumn;
  String? dateColumn;

  // Dummy headers (Later replace with real CSV headers)
  final List<String> csvHeaders = [
    "Column 1",
    "Column 2",
    "Column 3",
    "Column 4",
    "Column 5",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Map CSV Columns"),
        backgroundColor: AppColors.background,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// File Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insert_drive_file,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.fileName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "Match your CSV columns to required fields",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "These fields are required for demand forecasting and pricing optimization.",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),

              const SizedBox(height: 24),

              /// Product Name
              _buildDropdownField(
                label: "Product Name",
                value: productNameColumn,
                onChanged: (val) => setState(() => productNameColumn = val),
              ),

              /// Quantity Sold
              _buildDropdownField(
                label: "Quantity Sold",
                value: quantityColumn,
                onChanged: (val) => setState(() => quantityColumn = val),
              ),

              /// Selling Price
              _buildDropdownField(
                label: "Selling Price",
                value: priceColumn,
                onChanged: (val) => setState(() => priceColumn = val),
              ),

              /// Date
              _buildDropdownField(
                label: "Date",
                value: dateColumn,
                onChanged: (val) => setState(() => dateColumn = val),
              ),

              const Spacer(),

              /// Confirm Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _validateAndSubmit,
                child: const Text(
                  "Confirm & Import",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: value,
        dropdownColor: AppColors.card,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        items: csvHeaders
            .map(
              (header) => DropdownMenuItem(
                value: header,
                child: Text(
                  header,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: (value) => value == null ? "Required field" : null,
      ),
    );
  }

  void _validateAndSubmit() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("CSV successfully mapped!")));

      Navigator.pop(context);
    }
  }
}
