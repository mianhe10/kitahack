import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_colors.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  Future<void> _pickCSVFile(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && context.mounted) {
        String fileName = result.files.single.name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected: $fileName. Processing with AI...')),
        );
      }
    } catch (e) {
      debugPrint("File picking error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchBar(),
          const SizedBox(height: 20),
          _buildSyncCard(context),
          const SizedBox(height: 30),
          _buildInventoryHeader(),
          const SizedBox(height: 16),
          _buildInventoryItem(
            "Premium White Watch",
            129.0,
            135.0,
            "12 units",
            true,
          ),
          _buildInventoryItem(
            "Studio Headphones Pro",
            199.5,
            195.0,
            "8 units",
            true,
          ),
          _buildInventoryItem(
            "Red Sport Runners",
            85.0,
            85.0,
            "Out of Stock",
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text(
                "Sync Sales Data",
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Added the description text
          Text(
            "Upload your latest sales CSV to update inventory levels instantly.",
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => _pickCSVFile(context), // Trigger the picker
            icon: const Icon(Icons.upload_file),
            label: const Text(
              "Upload CSV File",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryItem(
    String title,
    double price,
    double recPrice,
    String stock,
    bool isAiReady,
  ) {
    final bool isUp = recPrice > price;
    final bool isDown = recPrice < price;
    final Color recColor = isUp
        ? Colors.greenAccent
        : (isDown ? Colors.redAccent : AppColors.textSecondary);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.image_outlined, color: Colors.white24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "\$${price.toStringAsFixed(2)}",
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                  ),
                ),
                // THE REC PART
                Row(
                  children: [
                    Icon(
                      isUp
                          ? Icons.trending_up
                          : (isDown
                                ? Icons.trending_down
                                : Icons.horizontal_rule),
                      size: 14,
                      color: recColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Rec: \$${recPrice.toStringAsFixed(2)}",
                      style: TextStyle(color: recColor, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isAiReady)
                const Text(
                  "AI READY",
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                stock,
                style: TextStyle(
                  color: stock == "Out of Stock"
                      ? Colors.redAccent
                      : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search products...',
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildInventoryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          "Product Inventory",
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "42 Items",
          style: TextStyle(
            color: AppColors.primary.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
