import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  double _currentPrice = 25.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Adjust Product Price",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "See how changing your price affects demand and margins.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              "RM ${_currentPrice.toStringAsFixed(2)}",
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Slider(
            value: _currentPrice,
            min: 10.0,
            max: 50.0,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.card,
            onChanged: (value) => setState(() => _currentPrice = value),
          ),
          const SizedBox(height: 40),
          _buildPredictionCard(),
        ],
      ),
    );
  }

  Widget _buildPredictionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            "AI PREDICTED IMPACT",
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _rowInfo("Estimated Demand", "+12%"),
          const Divider(color: Colors.white10),
          _rowInfo("Projected Revenue", "RM 4,200"),
          const Divider(color: Colors.white10),
          _rowInfo("Profit Margin", "18.5%"),
        ],
      ),
    );
  }

  Widget _rowInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
