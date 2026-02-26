import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class HeaderConfirmationScreen extends StatefulWidget {
  final Map<String, String> aiSuggestedMapping;
  final List<String> allCsvHeaders;
  final String filePath;

  const HeaderConfirmationScreen({
    super.key,
    required this.aiSuggestedMapping,
    required this.allCsvHeaders,
    required this.filePath,
  });

  @override
  State<HeaderConfirmationScreen> createState() => _HeaderConfirmationScreenState();
}

class _HeaderConfirmationScreenState extends State<HeaderConfirmationScreen> {
  late Map<String, String> confirmedMapping;
  final List<String> _requiredKeys = ['prod_id', 'price', 'qty', 'units_sold', 'date'];

  @override
  void initState() {
    super.initState();
    confirmedMapping = {};
    
    for (var key in _requiredKeys) {
      final suggestedValue = widget.aiSuggestedMapping[key];
      if (suggestedValue != null && widget.allCsvHeaders.contains(suggestedValue)) {
        confirmedMapping[key] = suggestedValue;
      } else {
        confirmedMapping[key] = widget.allCsvHeaders.isNotEmpty ? widget.allCsvHeaders.first : '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Verify CSV Columns", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.card,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Boss, we analyzed your file. Did we get the columns right?",
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: confirmedMapping.keys.map((key) {
                  return _buildMappingTile(key);
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingTile(String internalKey) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                internalKey.toUpperCase().replaceAll('_', ' '),
                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text("Data Source:", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          DropdownButton<String>(
            value: confirmedMapping[internalKey],
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.textPrimary),
            underline: Container(height: 1, color: AppColors.primary),
            items: widget.allCsvHeaders.toSet().toList().map((String header) {
              return DropdownMenuItem<String>(
                value: header,
                child: Text(header),
              );
            }).toList(),
            onChanged: (newValue) {
              setState(() {
                confirmedMapping[internalKey] = newValue!;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () {
          Navigator.pop(context, confirmedMapping);
        },
        child: const Text("Confirm & Start AI Analysis", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}