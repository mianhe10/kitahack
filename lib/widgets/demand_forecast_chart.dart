import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class DemandForecastCard extends StatelessWidget {
  const DemandForecastCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Demand Forecast",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar("Mon", 0.3),
              _buildBar("Tue", 0.4),
              _buildBar("Wed", 0.6),
              _buildBar("Thu", 0.5),
              _buildBar("Fri", 0.9, isPeak: true),
              _buildBar("Sat", 0.7),
              _buildBar("Sun", 0.45),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar(String day, double heightFactor, {bool isPeak = false}) {
    return Column(
      children: [
        if (isPeak)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            // FIX: Changed .bottom(4) to .only(bottom: 4)
            margin: const EdgeInsets.only(bottom: 4), // Changed from .bottom(4)
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              "Peak",
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        Container(
          height: 100 * heightFactor,
          width: 14,
          decoration: BoxDecoration(
            // FIX: Removed 'const' and used 'withValues' instead of deprecated 'withOpacity'
            color: isPeak
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          day,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
