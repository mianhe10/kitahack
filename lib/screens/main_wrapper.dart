import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'home_screen.dart';
import 'inventory_screen.dart';
import 'simulator_screen.dart';
import '../widgets/app_drawer.dart';

class MainWrapper extends StatefulWidget {
  final String username;
  const MainWrapper({super.key, this.username = "User"});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 1;

  // ── Welcome overlay ──────────────────────────────────────────
  bool _showWelcome = true;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);

    _fadeCtrl.forward();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      _fadeCtrl.reverse().then((_) {
        if (mounted) setState(() => _showWelcome = false);
      });
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Navigate to Products tab (index 2) ───────────────────────
  void _navigateToProducts() {
    setState(() => _selectedIndex = 2);
  }

  void _navigateToSimulator() {
    setState(() => _selectedIndex = 0); // Simulator is index 0
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const SimulatorScreen(),
      HomeScreen(
        username: widget.username,
        onNavigateToProducts: _navigateToProducts, // ← wired here
        onNavigateToSimulator: _navigateToSimulator,
      ),
      const InventoryScreen(),
    ];

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          drawer: const AppDrawer(),
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            title: Text(
              _selectedIndex == 0
                  ? 'Price & Profit Simulator'
                  : _selectedIndex == 1
                  ? 'Pricing Intel'
                  : 'Inventory & Sales',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
            ),
            child: BottomNavigationBar(
              backgroundColor: AppColors.background,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textSecondary,
              currentIndex: _selectedIndex,
              type: BottomNavigationBarType.fixed,
              onTap: (index) => setState(() => _selectedIndex = index),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.tune),
                  label: 'Simulator',
                ),
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.inventory_2_outlined),
                  label: 'Products',
                ),
              ],
            ),
          ),
        ),

        // ── Welcome overlay ─────────────────────────────────────
        if (_showWelcome)
          FadeTransition(
            opacity: _fadeAnim,
            child: Container(
              color: AppColors.background.withValues(alpha: 0.92),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.analytics,
                        size: 64,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'Welcome to',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                        letterSpacing: 1.2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'KitaHack',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hello, ${widget.username} 👋',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
