import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../services/gemini_service.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  final VoidCallback? onNavigateToProducts;
  final VoidCallback? onNavigateToSimulator;

  const HomeScreen({
    super.key,
    this.username = '',
    this.onNavigateToProducts,
    this.onNavigateToSimulator,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String _businessName = '';
  String _industry = 'Retail';
  String _region = 'Kuala Lumpur';

  // Inventory state
  List<Map<String, dynamic>> _products = [];
  bool _hasInventory = false;
  bool _inventoryLoading = true;

  // Stats
  int _totalProducts = 0;
  int _aiReadyCount = 0;
  int _lowStockCount = 0;

  // Onboarding checklist
  bool _hasAiReady = false;
  bool _hasCsvImport = false;

  // AI results
  AiDailyBriefing? _briefing;
  AiDemandExplanation? _demandExplanation;
  bool _loadingBriefing = true;
  bool _loadingDemand = true;

  // Last updated timestamp
  DateTime? _lastUpdated;

  // Greeting timer
  Timer? _greetingTimer;

  // Shimmer animation
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  Map<String, double> _weeklyDemand = {
    'Mon': 0.0,
    'Tue': 0.0,
    'Wed': 0.0,
    'Thu': 0.0,
    'Fri': 0.0,
    'Sat': 0.0,
    'Sun': 0.0,
  };

  bool get _hasCsvDemandData => _weeklyDemand.values.any((v) => v > 0);

  // ─────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmerAnim = Tween<double>(
      begin: -1.5,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));
    _greetingTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadDataThenAI();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _greetingTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────

  String _greeting(String name) {
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final displayName = name.trim();
    if (displayName.length < 2) return '$timeGreeting!';
    return '$timeGreeting, $displayName!';
  }

  String _lastUpdatedLabel() {
    if (_lastUpdated == null) return '';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 60) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    return 'Updated ${diff.inHours}h ago';
  }

  void _goToProducts() {
    if (widget.onNavigateToProducts != null) {
      widget.onNavigateToProducts!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Tap the Products tab to get started'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _goToSimulator() {
    widget.onNavigateToSimulator?.call();
  }

  // ─────────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────────

  Future<void> _loadDataThenAI() async {
    await _loadUserData();
    await Future.wait([
      _loadBriefing(),
      if (_hasInventory) _loadDemandExplanation() else _skipDemand(),
    ]);
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  Future<void> _skipDemand() async {
    if (mounted) setState(() => _loadingDemand = false);
  }

  Future<void> _loadUserData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!doc.exists || !mounted) return;

      final data = doc.data()!;
      final profile = data['businessProfile'] as Map<String, dynamic>?;

      final prodSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('products')
          .get();

      final logsSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('sales_log')
          .get();

      final Map<String, double> aggregated = {
        'Mon': 0,
        'Tue': 0,
        'Wed': 0,
        'Thu': 0,
        'Fri': 0,
        'Sat': 0,
        'Sun': 0,
      };

      for (final log in logsSnap.docs) {
        final d = log.data();
        final salesByDay = d['salesByDay'] as Map<String, dynamic>?;
        if (salesByDay != null) {
          salesByDay.forEach((day, qty) {
            if (aggregated.containsKey(day)) {
              aggregated[day] = aggregated[day]! + (qty as num).toDouble();
            }
          });
        }
      }

      final maxVal = aggregated.values.reduce((a, b) => a > b ? a : b);
      final normalized = maxVal > 0
          ? aggregated.map((k, v) => MapEntry(k, v / maxVal))
          : aggregated;

      final hasAiReady = prodSnap.docs.any(
        (d) => (d.data()['isAiReady'] ?? false) == true,
      );
      final hasCsvImport = logsSnap.docs.isNotEmpty;
      final aiReadyCount = prodSnap.docs
          .where((d) => (d.data()['isAiReady'] ?? false) == true)
          .length;
      final lowStockCount = prodSnap.docs.where((d) {
        final pd = d.data();
        final int stock = (pd['stock'] ?? 0) as int;
        final int threshold = (pd['lowStockThreshold'] ?? 10) as int;
        return stock > 0 && stock < threshold;
      }).length;

      if (mounted) {
        setState(() {
          _businessName = profile?['businessName'] ?? widget.username;
          _industry = profile?['industry'] ?? 'Retail';
          _region = profile?['region'] ?? 'Kuala Lumpur';
          _products = prodSnap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
          _hasInventory = prodSnap.docs.isNotEmpty;
          _hasAiReady = hasAiReady;
          _hasCsvImport = hasCsvImport;
          _inventoryLoading = false;
          _totalProducts = prodSnap.docs.length;
          _aiReadyCount = aiReadyCount;
          _lowStockCount = lowStockCount;
          if (maxVal > 0) _weeklyDemand = normalized;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen _loadUserData: $e');
      if (mounted) setState(() => _inventoryLoading = false);
    }
  }

  Future<void> _loadBriefing() async {
    if (!_hasInventory) {
      if (mounted) setState(() => _loadingBriefing = false);
      return;
    }
    try {
      final r = await GeminiService.generateDailyBriefing(
        businessName: _businessName.isEmpty ? 'My Business' : _businessName,
        industry: _industry,
        region: _region,
        topProducts: _products.take(3).toList(),
      );
      if (mounted) setState(() => _briefing = r);
    } catch (e) {
      debugPrint('Briefing: $e');
    } finally {
      if (mounted) setState(() => _loadingBriefing = false);
    }
  }

  Future<void> _loadDemandExplanation() async {
    try {
      final r = await GeminiService.explainDemandForecast(
        industry: _industry,
        region: _region,
        weeklyDemand: _weeklyDemand,
      );
      if (mounted) setState(() => _demandExplanation = r);
    } catch (e) {
      debugPrint('DemandExplanation: $e');
    } finally {
      if (mounted) setState(() => _loadingDemand = false);
    }
  }

  Future<void> _refresh() async {
    GeminiService.clearCache();
    setState(() {
      _loadingBriefing = true;
      _loadingDemand = true;
      _briefing = null;
      _demandExplanation = null;
      _inventoryLoading = true;
      _hasInventory = false;
      _hasAiReady = false;
      _hasCsvImport = false;
      _lastUpdated = null;
      _totalProducts = 0;
      _aiReadyCount = 0;
      _lowStockCount = 0;
    });
    await _loadDataThenAI();
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Greeting ──────────────────────────────────
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snap) {
                final rawName = snap.hasData && snap.data!.exists
                    ? (snap.data!.data() as Map<String, dynamic>)['username']
                              ?.toString() ??
                          widget.username
                    : widget.username;
                return Text(
                  _greeting(rawName),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // ── No inventory → onboarding card ────────────
            if (!_inventoryLoading && !_hasInventory) ...[
              _buildOnboardingCard(),
              const SizedBox(height: 24),
            ],

            // ── Has inventory ─────────────────────────────
            if (!_inventoryLoading && _hasInventory) ...[
              _buildStatsRow(),
              const SizedBox(height: 16),

              if (!_hasAiReady || !_hasCsvImport) ...[
                _buildOnboardingChecklist(),
                const SizedBox(height: 16),
              ],

              _buildBriefingCard(),
              const SizedBox(height: 16),

              const Text(
                'Demand Forecast',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildDemandForecastCard(),
              const SizedBox(height: 24),
            ],

            // ── Loading skeletons ─────────────────────────
            if (_inventoryLoading) ...[
              _buildSkeletonCard(height: 72),
              const SizedBox(height: 16),
              _buildSkeletonCard(height: 140),
              const SizedBox(height: 16),
              _buildSkeletonCard(height: 220),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // STATS ROW
  // ─────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
          label: 'Products',
          value: '$_totalProducts',
          icon: Icons.inventory_2_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'AI Ready',
          value: '$_aiReadyCount',
          icon: Icons.auto_awesome,
          color: Colors.greenAccent,
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'Low Stock',
          value: '$_lowStockCount',
          icon: Icons.warning_amber_rounded,
          color: _lowStockCount > 0
              ? Colors.orangeAccent
              : AppColors.textSecondary,
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // ONBOARDING CARD (no inventory)
  // ─────────────────────────────────────────────────────────

  Widget _buildOnboardingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0E3A4F), Color(0xFF082030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.rocket_launch_outlined,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'GET STARTED',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Set up your AI pricing in 3 steps',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Once you add products, your personalised briefing, demand forecast, and AI pricing insights will appear here.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _onboardingStep(
            number: '1',
            icon: Icons.add_box_outlined,
            title: 'Add your first product',
            subtitle: 'Manually or via Shopee / TikTok CSV',
            done: false,
          ),
          const SizedBox(height: 12),
          _onboardingStep(
            number: '2',
            icon: Icons.auto_awesome_outlined,
            title: 'Run AI price analysis',
            subtitle: 'Get recommended prices & market insights',
            done: false,
          ),
          const SizedBox(height: 12),
          _onboardingStep(
            number: '3',
            icon: Icons.upload_file_outlined,
            title: 'Upload a sales CSV',
            subtitle: 'Unlock demand forecasting from real data',
            done: false,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _goToProducts,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.45)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt, color: AppColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Go to Products to get started',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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

  Widget _onboardingStep({
    required String number,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.primary.withOpacity(0.2)
                : Colors.white.withOpacity(0.06),
            border: Border.all(
              color: done
                  ? AppColors.primary
                  : AppColors.primary.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: done
                ? Icon(Icons.check_rounded, color: AppColors.primary, size: 15)
                : Text(
                    number,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: done ? AppColors.textSecondary : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppColors.textSecondary.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // ONBOARDING CHECKLIST (has products, steps incomplete)
  // ─────────────────────────────────────────────────────────

  Widget _buildOnboardingChecklist() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.checklist_rounded, color: AppColors.primary, size: 15),
              const SizedBox(width: 8),
              Text(
                'SETUP PROGRESS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${[_hasInventory, _hasAiReady, _hasCsvImport].where((v) => v).length} / 3',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:
                  [
                    _hasInventory,
                    _hasAiReady,
                    _hasCsvImport,
                  ].where((v) => v).length /
                  3,
              backgroundColor: AppColors.primary.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 14),
          _checklistRow(
            icon: Icons.add_box_outlined,
            label: 'Add your first product',
            done: _hasInventory,
          ),
          const SizedBox(height: 10),
          _checklistRow(
            icon: Icons.auto_awesome_outlined,
            label: 'Run AI analysis on a product',
            done: _hasAiReady,
          ),
          const SizedBox(height: 10),
          _checklistRow(
            icon: Icons.upload_file_outlined,
            label: 'Upload a sales CSV',
            done: _hasCsvImport,
          ),
        ],
      ),
    );
  }

  Widget _checklistRow({
    required IconData icon,
    required String label,
    required bool done,
  }) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppColors.primary.withOpacity(0.2)
                : Colors.transparent,
            border: Border.all(
              color: done ? AppColors.primary : Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: done
              ? Icon(Icons.check_rounded, color: AppColors.primary, size: 13)
              : null,
        ),
        const SizedBox(width: 12),
        Icon(
          icon,
          size: 15,
          color: done
              ? AppColors.primary
              : AppColors.textSecondary.withOpacity(0.5),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: done ? AppColors.textSecondary : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: done ? FontWeight.normal : FontWeight.w500,
            decoration: done ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  // BRIEFING CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildBriefingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF0E3A4F), Color(0xFF082030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: _loadingBriefing
          ? _shimmer(80)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label + timestamp
                Row(
                  children: [
                    Icon(
                      Icons.wb_sunny_outlined,
                      color: AppColors.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "TODAY'S BRIEFING",
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    if (_lastUpdated != null)
                      Text(
                        _lastUpdatedLabel(),
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.5),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _briefing?.headline ?? '',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _briefing?.summary ?? '',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (_briefing?.actionDetail.isNotEmpty == true) ...[
                  const SizedBox(height: 14),
                  // Tappable → navigates to Simulator tab
                  GestureDetector(
                    onTap: _goToSimulator,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.bolt, color: AppColors.primary, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _briefing!.actionDetail,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: AppColors.primary.withOpacity(0.6),
                            size: 11,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // DEMAND FORECAST CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildDemandForecastCard() {
    // No CSV data yet — show empty state instead of flat bars
    if (!_hasCsvDemandData) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 36,
              color: AppColors.textSecondary.withOpacity(0.35),
            ),
            const SizedBox(height: 12),
            const Text(
              'No sales data yet',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload a Shopee or TikTok sales CSV to see your real weekly demand forecast.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.7),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _goToProducts,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bolt, color: AppColors.primary, size: 15),
                    const SizedBox(width: 8),
                    Text(
                      'Upload a Sales CSV',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

    // Has CSV data — show chart
    final peakDay =
        _demandExplanation?.peakDay ??
        _weeklyDemand.entries.reduce((a, b) => a.value > b.value ? a : b).key;

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
          Row(
            children: [
              const Text(
                'Demand Forecast',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart, color: AppColors.primary, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE DATA',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: _weeklyDemand.entries
                .map((e) => _buildBar(e.key, e.value, isPeak: e.key == peakDay))
                .toList(),
          ),
          if (!_loadingDemand && _demandExplanation != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: AppColors.primary,
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'WHY ${peakDay.toUpperCase()} IS PEAK',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _demandExplanation!.explanation,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        color: AppColors.primary,
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _demandExplanation!.pricingTip,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (_loadingDemand) ...[
            const SizedBox(height: 16),
            _shimmer(80),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────

  Widget _buildBar(String day, double factor, {bool isPeak = false}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isPeak)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Peak',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          height: factor < 0.05 ? 4 : 100 * factor,
          width: 14,
          decoration: BoxDecoration(
            color: isPeak
                ? AppColors.primary
                : factor < 0.05
                ? Colors.white12
                : AppColors.primary.withOpacity(0.4),
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

  Widget _shimmer(double height) {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, _) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              colors: [
                Colors.white.withOpacity(0.04),
                Colors.white.withOpacity(0.04),
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.04),
                Colors.white.withOpacity(0.04),
              ],
              transform: _SlidingGradientTransform(_shimmerAnim.value),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard({required double height}) {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              colors: [
                AppColors.card,
                AppColors.card,
                Colors.white.withOpacity(0.06),
                AppColors.card,
                AppColors.card,
              ],
              transform: _SlidingGradientTransform(_shimmerAnim.value),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slides the shimmer highlight across the widget bounds
// ─────────────────────────────────────────────────────────────────────────────

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}
