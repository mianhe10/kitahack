import 'package:flutter/material.dart';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_colors.dart';

class SimulatorScreen extends StatefulWidget {
  const SimulatorScreen({super.key});

  @override
  State<SimulatorScreen> createState() => _SimulatorScreenState();
}

class _SimulatorScreenState extends State<SimulatorScreen> {
  // State variables for the simulation
  double _cost = 18.0;
  double _currentPrice = 45.0;
  double _newPrice = 52.0;
  int _currentVolume = 100;

  // Simulation Logic (The "Engine")
  Map<String, dynamic> _calculateResults() {
    const double elasticity = -1.5;
    double priceChangePct = (_newPrice - _currentPrice) / _currentPrice;
    double volumeChangePct = priceChangePct * elasticity;

    int predictedVolume = (_currentVolume * (1 + volumeChangePct)).round();
    double currentProfit = (_currentPrice - _cost) * _currentVolume;
    double predictedProfit = (_newPrice - _cost) * predictedVolume;
    double profitLift = predictedProfit - currentProfit;
    double profitLiftPct = currentProfit != 0 ? (profitLift / currentProfit) * 100 : 0.0;

    // Generate Chart Curve Data
    List<FlSpot> profitSpots = [];
    double startPrice = max(10.0, _currentPrice - 20.0);
    for (double p = startPrice; p <= _currentPrice + 30; p += 2) {
      double pPct = (p - _currentPrice) / _currentPrice;
      int v = (_currentVolume * (1 + pPct * elasticity)).round();
      double prof = (p - _cost) * v;
      profitSpots.add(FlSpot(p, max(0, prof)));
    }

    return {
      'profitLift': profitLift,
      'profitLiftPct': profitLiftPct,
      'predictedVolume': predictedVolume,
      'volumeChange': predictedVolume - _currentVolume,
      'profitSpots': profitSpots,
    };
  }

  @override
  Widget build(BuildContext context) {
    final results = _calculateResults();
    final bool isPositive = results['profitLift'] >= 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Profit Simulator",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.textPrimary)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),

            // Stats Row
            Row(
              children: [
                Expanded(child: _buildStatCard("Profit Lift", "RM ${results['profitLift'].toStringAsFixed(2)}", "${results['profitLiftPct'].toStringAsFixed(1)}%", isPositive)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard("Volume Impact", "${results['predictedVolume']}", "${results['volumeChange']} orders", results['volumeChange'] >= 0)),
              ],
            ),

            const SizedBox(height: 24),
            _buildChartSection(results['profitSpots']),

            const SizedBox(height: 24),
            _buildControlsCard(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Strategy Tester",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Text("Simulate pricing for Malaysian MSMEs",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.zap, size: 14, color: AppColors.primary),
              SizedBox(width: 4),
              Text("AI MODE", style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 10)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String subValue, bool positive) {
    Color accentColor = positive ? AppColors.primary : const Color(0xFFFF8A65);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: accentColor)),
          Text(subValue,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildChartSection(List<FlSpot> spots) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: 320,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.trendingUp, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text("Profit Optimization Curve",
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => AppColors.card,
                    // Fixed: renamed parameter and type
                    tooltipBorderRadius: BorderRadius.circular(8),
                    getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                      return touchedBarSpots.map((barSpot) {
                        return LineTooltipItem(
                          'Price: RM ${barSpot.x.toStringAsFixed(2)}\n',
                          const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          children: [
                            TextSpan(
                              text: 'Profit: RM ${barSpot.y.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        'RM${value.toInt()}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 20,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'RM${value.toInt()}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                        ),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    VerticalLine(
                      x: _currentPrice,
                      color: AppColors.textSecondary.withOpacity(0.5),
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    ),
                    VerticalLine(
                      x: _newPrice,
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 2,
                      dashArray: [5, 5],
                    ),
                  ],
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.primary.withOpacity(0.25),
                          AppColors.primary.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.calculator, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text("Simulation Controls",
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          _sliderInput("Product Cost", _cost, 1, 100, (v) => setState(() => _cost = v)),
          _sliderInput("Base Price", _currentPrice, 5, 200, (v) => setState(() => _currentPrice = v)),
          _sliderInput("Target Price", _newPrice, 5, 200, (v) => setState(() => _newPrice = v),
              color: const Color(0xFF00E5FF)),
        ],
      ),
    );
  }

  Widget _sliderInput(String label, double value, double min, double max, Function(double) onChanged, {Color color = AppColors.primary}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
              Text("RM ${value.toInt()}", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbColor: color,
              activeTrackColor: color,
              inactiveTrackColor: Colors.white10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayColor: color.withOpacity(0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}