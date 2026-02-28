import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── Notification toggles ───────────────────────────────────
  bool _pushNotifications = true;
  bool _priceAlerts = true;
  bool _demandAlerts = false;
  bool _notificationsLoading = false;

  // ── Appearance ─────────────────────────────────────────────
  bool _darkMode = true;
  String _selectedLanguage = 'English';
  bool _appearanceLoading = false;

  // ── Business Profile ───────────────────────────────────────
  final _businessNameCtrl = TextEditingController();
  String _industry = 'Retail';
  String _region = 'Kuala Lumpur';

  // Saved originals — used to detect unsaved changes
  String _savedBusinessName = '';
  String _savedIndustry = '';
  String _savedRegion = '';

  bool _isProfileLoading = true;
  bool _isSaving = false;
  bool _isProfileEmpty = true;

  final List<String> _languages = [
    'English',
    'Bahasa Melayu',
    'Chinese',
    'Tamil',
  ];
  final List<String> _industries = [
    'Retail',
    'F&B',
    'Services',
    'Manufacturing',
    'E-Commerce',
  ];
  final List<String> _regions = [
    'Kuala Lumpur',
    'Selangor',
    'Penang',
    'Johor',
    'Sabah',
    'Sarawak',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadBusinessProfile();
    _loadNotificationPrefs();
    _loadAppearancePrefs();
    _businessNameCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    super.dispose();
  }

  // ── Firebase: Appearance ───────────────────────────────────

  Future<void> _loadAppearancePrefs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final prefs = doc.data()?['appearancePrefs'] as Map<String, dynamic>?;
        if (prefs != null && mounted) {
          setState(() {
            _darkMode = prefs['darkMode'] ?? true;
            _selectedLanguage = prefs['language'] ?? 'English';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading appearance prefs: $e');
    }
  }

  Future<void> _saveAppearancePref(String key, dynamic value) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'appearancePrefs': {key: value},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving appearance pref: $e');
    }
  }

  // ── Firebase: Notifications ────────────────────────────────

  Future<void> _loadNotificationPrefs() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final prefs = doc.data()?['notificationPrefs'] as Map<String, dynamic>?;
        if (prefs != null && mounted) {
          setState(() {
            _pushNotifications = prefs['pushNotifications'] ?? true;
            _priceAlerts = prefs['priceAlerts'] ?? true;
            _demandAlerts = prefs['demandAlerts'] ?? false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading notification prefs: $e');
    }
  }

  Future<void> _saveNotificationPref(String key, bool value) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'notificationPrefs': {key: value},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving notification pref: $e');
    }
  }

  // ── Firebase: Load ─────────────────────────────────────────

  Future<void> _loadBusinessProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists) {
        final profile = doc.data()?['businessProfile'] as Map<String, dynamic>?;

        if (profile != null) {
          final bName = profile['businessName'] ?? '';
          final ind = profile['industry'] ?? 'Retail';
          final reg = profile['region'] ?? 'Kuala Lumpur';

          setState(() {
            _businessNameCtrl.text = bName;
            _industry = ind;
            _region = reg;
            _savedBusinessName = bName;
            _savedIndustry = ind;
            _savedRegion = reg;
            _isProfileEmpty = bName.isEmpty;
          });
        }
        // No businessProfile field yet → leave _isProfileEmpty = true
      }
    } catch (e) {
      debugPrint('Error loading business profile: $e');
    } finally {
      if (mounted) setState(() => _isProfileLoading = false);
    }
  }

  // ── Firebase: Save ─────────────────────────────────────────

  Future<void> _saveBusinessProfile() async {
    final businessName = _businessNameCtrl.text.trim();
    if (businessName.isEmpty) {
      _showSnackBar('Please enter a business name.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'businessProfile': {
          'businessName': businessName,
          'industry': _industry,
          'region': _region,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));

      setState(() {
        _savedBusinessName = businessName;
        _savedIndustry = _industry;
        _savedRegion = _region;
        _isProfileEmpty = false;
      });

      _showSnackBar('Business profile saved!');
    } catch (e) {
      _showSnackBar('Failed to save. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _hasUnsavedChanges =>
      _businessNameCtrl.text.trim() != _savedBusinessName ||
      _industry != _savedIndustry ||
      _region != _savedRegion;

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFFF5252) : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── Notifications ──────────────────────────────────
          _buildSectionHeader('Notifications'),
          const SizedBox(height: 12),
          _buildCard([
            _buildSwitchRow(
              icon: Icons.notifications_active_outlined,
              label: 'Push Notifications',
              value: _pushNotifications,
              onChanged: (v) {
                setState(() => _pushNotifications = v);
                _saveNotificationPref('pushNotifications', v);
              },
            ),
            _buildDivider(),
            _buildSwitchRow(
              icon: Icons.price_change_outlined,
              label: 'Price Alerts',
              subtitle: 'Notify when competitor price changes detected',
              value: _priceAlerts,
              onChanged: (v) {
                setState(() => _priceAlerts = v);
                _saveNotificationPref('priceAlerts', v);
              },
            ),
            _buildDivider(),
            _buildSwitchRow(
              icon: Icons.trending_up_outlined,
              label: 'Demand Alerts',
              subtitle: 'Notify when a demand spike is detected',
              value: _demandAlerts,
              onChanged: (v) {
                setState(() => _demandAlerts = v);
                _saveNotificationPref('demandAlerts', v);
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── Display & Appearance ───────────────────────────
          _buildSectionHeader('Display & Appearance'),
          const SizedBox(height: 12),
          _buildCard([
            _buildSwitchRow(
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              value: _darkMode,
              onChanged: (v) {
                setState(() => _darkMode = v);
                _saveAppearancePref('darkMode', v);
              },
            ),
            _buildDivider(),
            _buildDropdownRow(
              icon: Icons.language_outlined,
              label: 'Language',
              value: _selectedLanguage,
              items: _languages,
              onChanged: (v) {
                setState(() => _selectedLanguage = v!);
                _saveAppearancePref('language', v);
              },
            ),
          ]),

          const SizedBox(height: 24),

          // ── Business Profile ───────────────────────────────
          _buildSectionHeader('Business Profile'),
          const SizedBox(height: 8),

          // Info banner when profile is empty
          if (!_isProfileLoading && _isProfileEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      "You haven't set up your business profile yet. "
                      "Fill in the details below and tap Save.",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Business profile card
          _buildCard([
            // Business Name inline text field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _isProfileLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : TextFormField(
                      controller: _businessNameCtrl,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Business Name',
                        labelStyle: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.storefront_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
            ),

            _buildDivider(),

            _buildDropdownRow(
              icon: Icons.category_outlined,
              label: 'Industry',
              value: _industry,
              items: _industries,
              onChanged: (v) => setState(() => _industry = v!),
            ),

            _buildDivider(),

            _buildDropdownRow(
              icon: Icons.location_on_outlined,
              label: 'Region',
              value: _region,
              items: _regions,
              onChanged: (v) => setState(() => _region = v!),
            ),
          ]),

          const SizedBox(height: 12),

          // Save button — dims when no changes, active when unsaved changes exist
          AnimatedOpacity(
            opacity: _hasUnsavedChanges ? 1.0 : 0.35,
            duration: const Duration(milliseconds: 250),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: (_hasUnsavedChanges && !_isSaving)
                    ? _saveBusinessProfile
                    : null,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Save Business Profile',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── About ──────────────────────────────────────────
          _buildSectionHeader('About'),
          const SizedBox(height: 12),
          _buildCard([
            _buildInfoRow(
              icon: Icons.info_outline,
              label: 'App Version',
              value: '1.0.0',
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () {},
            ),
            _buildDivider(),
            _buildActionRow(
              icon: Icons.description_outlined,
              label: 'Terms of Service',
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Shared Builders ────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.white.withOpacity(0.06),
      indent: 52,
    );
  }

  Widget _buildSwitchRow({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            inactiveTrackColor: Colors.white12,
            inactiveThumbColor: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow({
    required IconData icon,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: AppColors.card,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              icon: Icon(Icons.expand_more, color: AppColors.primary, size: 18),
              items: items
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
