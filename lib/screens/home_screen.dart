import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/ai_recommendation_card.dart';
import '../widgets/demand_forecast_chart.dart';

class HomeScreen extends StatelessWidget {
  final String username;

  const HomeScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting text
          Text(
            "Welcome back, $username!",
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          const _BannerCard(),
          const SizedBox(height: 20),
          const AIRecommendationCard(),
          const SizedBox(height: 24),
          const Text(
            "Demand Forecast",
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const DemandForecastCard(),
        ],
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0E3A4F), Color(0xFF082030)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.show_chart, size: 40, color: Colors.white54),
      ),
    );
  }
}
