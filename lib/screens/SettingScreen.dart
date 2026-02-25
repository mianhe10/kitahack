import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isDarkMode = false;
  bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Settings",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          _buildSectionHeader("Account"),
          _buildListTile(
            title: "Change Password",
            icon: Icons.lock_outline,
            onTap: () {
              // TODO: Navigate to Change Password
            },
          ),
          const Divider(height: 40, thickness: 1),
          
          _buildSectionHeader("Preferences"),
          SwitchListTile(
            title: const Text(
              "Dark Mode",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            secondary: const Icon(
              Icons.dark_mode_outlined,
              color: AppColors.textSecondary,
            ),
            activeColor: AppColors.primary,
            value: _isDarkMode,
            onChanged: (bool value) {
              setState(() {
                _isDarkMode = value;
              });
            },
          ),
          SwitchListTile(
            title: const Text(
              "Push Notifications",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            secondary: const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.textSecondary,
            ),
            activeColor: AppColors.primary,
            value: _notificationsEnabled,
            onChanged: (bool value) {
              setState(() {
                _notificationsEnabled = value;
              });
            },
          ),
          const Divider(height: 40, thickness: 1),

          _buildSectionHeader("About"),
          _buildListTile(
            title: "App Version",
            icon: Icons.info_outline,
            trailingWidget: const Text(
              "1.0.0",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: null,
          ),
          _buildListTile(
            title: "Privacy Policy",
            icon: Icons.privacy_tip_outlined,
            onTap: () {
              // TODO: Navigate to Privacy Policy or launch URL
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required IconData icon,
    Widget? trailingWidget,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      trailing: trailingWidget ?? 
          const Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: AppColors.textSecondary,
          ),
      onTap: onTap,
    );
  }
}