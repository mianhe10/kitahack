// lib/screens/inventory_screen.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../theme/app_colors.dart';
import '../model/product_model.dart';
import '../services/data_ingestion_service.dart';
import 'header_confirmation_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DataIngestionService _dataService = DataIngestionService(
    apiKey: "AIzaSyB61_B9JGHO18eNW9v-kgzr4OQh7rf61Zw",
  );

  bool _isProcessing = false;

  List<Product> _products = [
    Product(id: "1", title: "Premium White Watch", currentPrice: 129.0, recommendedPrice: 129.0, stock: 12, unitsSold: 5, aiAdvice: "", isAiReady: false),
    Product(id: "2", title: "Studio Headphones Pro", currentPrice: 199.5, recommendedPrice: 199.5, stock: 8, unitsSold: 2, aiAdvice: "", isAiReady: false),
  ];

  Future<void> _pickCSVFile(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: true,
      );

      if (result != null && context.mounted) {
        setState(() => _isProcessing = true);

        Uint8List fileBytes = result.files.single.bytes!;
        final csvString = utf8.decode(fileBytes);
        final fields = const CsvToListConverter(eol: '\n').convert(csvString.replaceAll('\r\n', '\n'));

        if (fields.length <= 1) throw Exception("CSV is empty or has no data rows");

        final List<String> headers = fields[0].map((e) => e.toString().trim()).toList();
        final savedMapping = await _dataService.findExistingTemplate(headers);

        if (!context.mounted) return;

        if (savedMapping != null) {
          _showSnackBar(context, "Welcome back! Using your saved format.");
          _startFullDataAnalysis(savedMapping, fields, headers);
        } else {
          final data = await _dataService.sniffCsv(fileBytes);
          final aiMapping = await _dataService.getAiSuggestedMapping(
            headers: data['headers'],
            sample: data['sample'],
          );
          if (!context.mounted) return;
          _navigateToConfirmation(context, aiMapping, headers, fields);
        }
      }
    } catch (e) {
      _showSnackBar(context, "Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _startFullDataAnalysis(Map<String, String> mapping, List<List<dynamic>> fields, List<String> headers) async {
    try {
      setState(() => _isProcessing = true);

      List<Product> newProducts = [];
      debugPrint("--- STARTING CSV PARSE ---");
      debugPrint("Headers: $headers");
      debugPrint("AI Mapping used: $mapping");

      for (int i = 1; i < fields.length; i++) {
        final row = fields[i];
        if (row.isEmpty || row.join('').trim().isEmpty) continue; 

        String getValue(String internalKey) {
          final targetHeader = mapping[internalKey];
          if (targetHeader == null) return '0';
          
          final index = headers.indexWhere((h) => 
              h.trim().toLowerCase() == targetHeader.trim().toLowerCase());
              
          if (index == -1 || index >= row.length) return '0';
          return row[index].toString().trim();
        }

        final title = getValue('prod_id');
        final finalTitle = (title == '0' || title.isEmpty) ? "Unnamed Product (Row $i)" : title;

        double cleanDouble(String val) {
          String cleaned = val.replaceAll(RegExp(r'[^0-9.]'), '');
          return double.tryParse(cleaned) ?? 0.0;
        }

        int cleanInt(String val) {
          String cleaned = val.replaceAll(RegExp(r'[^0-9]'), '');
          return int.tryParse(cleaned) ?? 0;
        }

        newProducts.add(Product(
          id: finalTitle,
          title: finalTitle, 
          currentPrice: cleanDouble(getValue('price')),
          recommendedPrice: cleanDouble(getValue('price')),
          stock: cleanInt(getValue('qty')),
          unitsSold: cleanInt(getValue('units_sold')),
          isAiReady: false,
          aiAdvice: "",
        ));
      }

      debugPrint("Successfully extracted ${newProducts.length} items from CSV.");

      setState(() => _products = newProducts);

      if (_products.isEmpty) {
        _showSnackBar(context, "Failed to extract items. Check debug console.");
        return;
      }

      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: 'AIzaSyB61_B9JGHO18eNW9v-kgzr4OQh7rf61Zw',
      );

      const int batchSize = 5;

      for (int i = 0; i < _products.length; i += batchSize) {
        if (!mounted) return;

        final end = (i + batchSize < _products.length) ? i + batchSize : _products.length;
        final batch = _products.sublist(i, end);

        final batchJson = batch.map((p) => {
          "id": p.id,
          "name": p.title,
          "price": p.currentPrice,
          "stock": p.stock,
          "sold": p.unitsSold
        }).toList();

        final prompt = '''You are an expert e-commerce pricing algorithm for Malaysia.
        Analyze these products:
        ${jsonEncode(batchJson)}

        For EACH product:
        Task 1: Estimate the current average market price on platforms like Shopee/TikTok Malaysia.
        Task 2: Calculate the optimal recommended price to maximize profit. Factor in stock.

        Output ONLY a valid JSON array of objects in this EXACT format, with no markdown:
        [
          {
            "id": "item_id_here",
            "estimated_market_price": 100.00,
            "recommended_price": 95.00,
            "ai_advice": "Short 1-sentence advice in Manglish"
          }
        ]''';

        final response = await model.generateContent([Content.text(prompt)]);
        if (!mounted) return;

        String text = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '[]';

        try {
          final List<dynamic> parsedJson = jsonDecode(text);
          setState(() {
            for (var result in parsedJson) {
              final targetIndex = _products.indexWhere((p) => p.id == result['id'].toString());
              if (targetIndex != -1) {
                _products[targetIndex] = Product(
                  id: _products[targetIndex].id,
                  title: _products[targetIndex].title,
                  currentPrice: _products[targetIndex].currentPrice,
                  stock: _products[targetIndex].stock,
                  unitsSold: _products[targetIndex].unitsSold,
                  estimatedMarketPrice: (result['estimated_market_price'] as num).toDouble(),
                  recommendedPrice: (result['recommended_price'] as num).toDouble(),
                  aiAdvice: result['ai_advice'].toString(),
                  isAiReady: true,
                );
              }
            }
          });
        } catch (e) {
          debugPrint("JSON Parse Error for batch $i: $e");
        }
      }

      if (mounted) _showSnackBar(context, "AI Market Research Complete!");
    } catch (e) {
      if (mounted) _showSnackBar(context, "Error processing data: $e");
      debugPrint("FATAL ERROR: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _navigateToConfirmation(BuildContext context, Map<String, String> aiMapping, List<String> headers, List<List<dynamic>> fields) async {
    final confirmedMapping = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (context) => HeaderConfirmationScreen(
          aiSuggestedMapping: aiMapping,
          allCsvHeaders: headers,
          filePath: "web_upload.csv",
        ),
      ),
    );

    if (confirmedMapping != null && context.mounted) {
      await _dataService.saveTemplate(headers, confirmedMapping);
      _showSnackBar(context, "Mapping confirmed! Starting AI analysis...");
      _startFullDataAnalysis(confirmedMapping, fields, headers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
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
              ..._products.map((product) => _buildInventoryItem(product)).toList(),
            ],
          ),
        ),
        if (_isProcessing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildInventoryItem(Product product) {
    // Utilizing the getters directly from your Product model
    final Color recColor = product.isUp 
        ? Colors.greenAccent 
        : (product.isDown ? Colors.redAccent : Colors.grey);
        
    final IconData trendIcon = product.isUp 
        ? Icons.trending_up 
        : (product.isDown ? Icons.trending_down : Icons.horizontal_rule);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13201D), 
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            height: 65, width: 65,
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.watch, color: Colors.black38, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text("RM ${product.currentPrice.toStringAsFixed(2)}",
                  style: const TextStyle(color: Color(0xFF00B4D8), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (product.isAiReady)
                  Row(
                    children: [
                      Icon(trendIcon, size: 16, color: recColor),
                      const SizedBox(width: 4),
                      Text("Rec: RM ${product.recommendedPrice.toStringAsFixed(2)}",
                        style: TextStyle(color: recColor, fontSize: 13)),
                    ],
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (product.isAiReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00303D), 
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text("AI READY",
                    style: TextStyle(color: Color(0xFF00B4D8), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                )
              else 
                const SizedBox(height: 24), 
                
              const SizedBox(height: 18),
              Text("Stock: ${product.stock} units",
                style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13)),
            ],
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
          const Row(
            children: [
              Icon(Icons.sync, color: AppColors.primary),
              SizedBox(width: 12),
              Text("Sync Sales Data",
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text("Upload latest CSV to update inventory and get AI pricing.",
            style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _pickCSVFile(context),
            icon: const Icon(Icons.upload_file),
            label: const Text("Upload CSV File", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search products...",
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.card.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildInventoryHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Product Inventory",
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        Text("${_products.length} products",
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      ],
    );
  }
}