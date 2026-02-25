import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Added for real logout
import '../theme/app_colors.dart';
import '../screens/login_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.card),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.analytics, color: AppColors.primary, size: 40),
                  SizedBox(height: 10),
                  Text(
                    "RETAIL INTEL",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildDrawerItem(context, Icons.person_outline, "Account Profile"),
          _buildDrawerItem(context, Icons.settings_outlined, "Settings"),
          _buildDrawerItem(context, Icons.help_outline, "Help & Support"),
          const Spacer(),
          // Logout Item with Real Firebase Sign Out
          _buildDrawerItem(context, Icons.logout, "Logout", isLogout: true),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context,
    IconData icon,
    String title, {
    bool isLogout = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isLogout ? Colors.redAccent : AppColors.textSecondary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isLogout ? Colors.redAccent : AppColors.textPrimary,
        ),
      ),
      onTap: () async {
        if (isLogout) {
          // 1. Sign out from Firebase
          await FirebaseAuth.instance.signOut();

          // 2. Clear stack and go to Login
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          }
        } else {
          Navigator.pop(context);
        }
      },
    );
  }
}
