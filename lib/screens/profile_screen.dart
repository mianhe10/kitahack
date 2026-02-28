import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final User? _user = FirebaseAuth.instance.currentUser;
  File? _selectedImage;

  final _shopNameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _isSaving = false;
  bool _isCheckingUsername = false;
  String? _usernameError;
  String? _photoURL;
  String? _photoBase64;

  // Original values — used to detect changes
  String _originalShopName = '';
  String _originalFullName = '';
  String _originalUsername = '';
  String _originalPhone = '';

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));

    _animCtrl.forward();
    _loadUserData();

    // Listen to all fields to detect changes
    _shopNameCtrl.addListener(_onAnyFieldChanged);
    _fullNameCtrl.addListener(_onAnyFieldChanged);
    _usernameCtrl.addListener(_onAnyFieldChanged);
    _usernameCtrl.addListener(_onUsernameChanged);
    _phoneCtrl.addListener(_onAnyFieldChanged);
    _currentPassCtrl.addListener(_onAnyFieldChanged);
    _newPassCtrl.addListener(_onAnyFieldChanged);
  }

  Future<void> _loadUserData() async {
    if (_user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      final shopName = data['shopName'] ?? '';
      final fullName = data['fullname'] ?? '';
      final username = data['username'] ?? '';
      final phone = data['phone'] ?? '';
      final photoURL = data['photoURL'] ?? _user?.photoURL;
      _photoBase64 = data['photoBase64'];

      setState(() {
        _shopNameCtrl.text = shopName;
        _fullNameCtrl.text = fullName;
        _usernameCtrl.text = username;
        _phoneCtrl.text = phone;
        _photoURL = photoURL;

        // Store originals
        _originalShopName = shopName;
        _originalFullName = fullName;
        _originalUsername = username;
        _originalPhone = phone;
      });
    }
  }

  /// Returns true if the user has changed anything
  bool get _hasChanges {
    if (_selectedImage != null) return true;
    if (_fullNameCtrl.text.trim() != _originalFullName) return true;
    if (_usernameCtrl.text.trim() != _originalUsername) return true;
    if (_phoneCtrl.text.trim() != _originalPhone) return true;
    if (_shopNameCtrl.text.trim() != _originalShopName) return true;
    if (_newPassCtrl.text.trim().isNotEmpty &&
        _currentPassCtrl.text.trim().isNotEmpty)
      return true;
    return false;
  }

  void _onAnyFieldChanged() {
    // Just trigger a rebuild so the button state updates
    setState(() {});
  }

  DateTime _lastTypeTime = DateTime.now();

  void _onUsernameChanged() {
    final typed = _usernameCtrl.text.trim();
    if (typed == _originalUsername) {
      setState(() => _usernameError = null);
      return;
    }
    setState(() => _usernameError = null);
    _lastTypeTime = DateTime.now();

    Future.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.difference(_lastTypeTime).inMilliseconds < 500) return;
      if (_usernameCtrl.text.trim() == _originalUsername) return;
      if (_usernameCtrl.text.trim().isEmpty) return;

      setState(() => _isCheckingUsername = true);
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: typed)
          .get();

      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _usernameError = query.docs.isNotEmpty
            ? 'Username "$typed" is already taken'
            : null;
      });
    });
  }

  @override
  void dispose() {
    _shopNameCtrl.removeListener(_onAnyFieldChanged);
    _fullNameCtrl.removeListener(_onAnyFieldChanged);
    _usernameCtrl.removeListener(_onAnyFieldChanged);
    _usernameCtrl.removeListener(_onUsernameChanged);
    _phoneCtrl.removeListener(_onAnyFieldChanged);
    _currentPassCtrl.removeListener(_onAnyFieldChanged);
    _newPassCtrl.removeListener(_onAnyFieldChanged);

    _animCtrl.dispose();
    _shopNameCtrl.dispose();
    _fullNameCtrl.dispose();
    _usernameCtrl.dispose();
    _phoneCtrl.dispose();
    _currentPassCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 40, // keep it small since it's stored as base64
      maxWidth: 300,
      maxHeight: 300,
    );
    if (picked == null || !mounted) return;

    setState(() => _selectedImage = File(picked.path));

    try {
      final bytes = await picked.readAsBytes();
      final base64Str = base64Encode(bytes);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({'photoBase64': base64Str});

      if (mounted) {
        setState(() => _photoBase64 = base64Str);
        _showSnack('Photo updated ✓', success: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to save photo: $e');
    }
  }

  Future<void> _saveChanges() async {
    if (_user == null || !_hasChanges) return;
    if (_usernameError != null) {
      _showSnack(_usernameError!);
      return;
    }

    final newUsername = _usernameCtrl.text.trim();

    // Only check username uniqueness if it actually changed
    if (newUsername != _originalUsername) {
      setState(() => _isSaving = true);
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: newUsername)
          .get();
      if (query.docs.isNotEmpty) {
        setState(() {
          _isSaving = false;
          _usernameError = 'Username "$newUsername" is already taken';
        });
        _showSnack('Username is already taken');
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      // Build update map with ONLY changed fields
      final Map<String, dynamic> updates = {};

      if (_shopNameCtrl.text.trim() != _originalShopName) {
        updates['shopName'] = _shopNameCtrl.text.trim();
      }
      if (_fullNameCtrl.text.trim() != _originalFullName) {
        updates['fullname'] = _fullNameCtrl.text.trim();
      }
      if (newUsername != _originalUsername) {
        updates['username'] = newUsername;
      }
      if (_phoneCtrl.text.trim() != _originalPhone) {
        updates['phone'] = _phoneCtrl.text.trim();
      }

      // Only hit Firestore if there's something to update
      if (updates.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .update(updates);
      }

      // Update local originals to reflect the new saved state
      if (updates.containsKey('shopName'))
        _originalShopName = updates['shopName'];
      if (updates.containsKey('fullname'))
        _originalFullName = updates['fullname'];
      if (updates.containsKey('username'))
        _originalUsername = updates['username'];
      if (updates.containsKey('phone')) _originalPhone = updates['phone'];

      // Handle password change separately
      if (_newPassCtrl.text.trim().isNotEmpty &&
          _currentPassCtrl.text.trim().isNotEmpty) {
        final cred = EmailAuthProvider.credential(
          email: _user!.email!,
          password: _currentPassCtrl.text.trim(),
        );
        await _user!.reauthenticateWithCredential(cred);
        await _user!.updatePassword(_newPassCtrl.text.trim());
        _currentPassCtrl.clear();
        _newPassCtrl.clear();
      }

      if (mounted) _showSnack('Profile updated ✓', success: true);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showSnack(
          e.code == 'wrong-password'
              ? 'Current password is incorrect'
              : 'Auth error: ${e.message}',
        );
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? AppColors.primary : Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _hasChanges && !_isSaving && _usernameError == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Account Profile',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                // ── Avatar ────────────────────────────────────
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 116,
                        height: 116,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 24,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary.withValues(alpha: 0.8),
                                  AppColors.primary.withValues(alpha: 0.3),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: ClipOval(
                              child: _selectedImage != null
                                  ? Image.file(
                                      _selectedImage!,
                                      fit: BoxFit.cover,
                                    )
                                  : _photoBase64 != null
                                  ? Image.memory(
                                      base64Decode(_photoBase64!),
                                      fit: BoxFit.cover,
                                    )
                                  : _photoURL != null
                                  ? Image.network(_photoURL!, fit: BoxFit.cover)
                                  : const Icon(
                                      Icons.store_rounded,
                                      size: 52,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 5),

                // ── Email (read-only) ──────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.mail_outline_rounded,
                      color: AppColors.textSecondary,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _user?.email ?? '',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 36),

                // ── Personal Info ──────────────────────────────
                _sectionLabel('Personal Info'),
                const SizedBox(height: 12),
                _buildField('Full Name', _fullNameCtrl, Icons.badge_outlined),
                const SizedBox(height: 14),
                _buildUsernameField(),
                const SizedBox(height: 14),
                _buildField(
                  'Phone Number',
                  _phoneCtrl,
                  Icons.phone_outlined,
                  keyboard: TextInputType.phone,
                ),

                const SizedBox(height: 32),

                // ── Change Password ────────────────────────────
                _sectionLabel('Change Password'),
                const SizedBox(height: 12),
                _buildPasswordField(
                  'Current Password',
                  _currentPassCtrl,
                  _obscureCurrent,
                  () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
                const SizedBox(height: 14),
                _buildPasswordField(
                  'New Password',
                  _newPassCtrl,
                  _obscureNew,
                  () => setState(() => _obscureNew = !_obscureNew),
                ),

                const SizedBox(height: 40),

                // ── Save Button ────────────────────────────────
                AnimatedOpacity(
                  opacity: canSave ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 250),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      // null disables the button entirely
                      onPressed: canSave ? _saveChanges : null,
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _usernameCtrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Username',
            labelStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.alternate_email_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            suffixIcon: _usernameCtrl.text.trim() == _originalUsername
                ? null
                : _isCheckingUsername
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  )
                : Icon(
                    _usernameError == null
                        ? Icons.check_circle_outline_rounded
                        : Icons.cancel_outlined,
                    color: _usernameError == null
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 20,
                  ),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: _usernameError != null
                    ? Colors.redAccent
                    : AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: _usernameError != null
                  ? const BorderSide(color: Colors.redAccent, width: 1)
                  : BorderSide.none,
            ),
          ),
        ),
        if (_usernameError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 14),
            child: Text(
              _usernameError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
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
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(
    String label,
    TextEditingController ctrl,
    bool obscure,
    VoidCallback toggle,
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        prefixIcon: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.primary,
          size: 20,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.textSecondary,
            size: 20,
          ),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
