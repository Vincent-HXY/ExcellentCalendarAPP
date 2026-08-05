import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';

/// Edit profile page — edit display name, username, language, timezone.
///
/// States: initial, changed, submitting, success, error.
/// Save button disabled when no changes detected.
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    required this.authController,
    required this.currentDisplayName,
    required this.currentUsername,
    super.key,
  });

  final AuthController authController;
  final String currentDisplayName;
  final String currentUsername;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  String? _errorMessage;
  bool _disposed = false;

  bool get _hasChanges =>
      _displayNameController.text.trim() != widget.currentDisplayName ||
      _usernameController.text.trim() != widget.currentUsername;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.currentDisplayName);
    _usernameController =
        TextEditingController(text: widget.currentUsername);
    _displayNameController.addListener(_onFieldChanged);
    _usernameController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _disposed = true;
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (!_disposed) setState(() {});
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.updateProfile(
        displayName: _displayNameController.text.trim(),
        username: _usernameController.text.trim(),
      );
      if (_disposed) return;

      if (success) {
        setState(() => _isSubmitting = false);
        if (!_disposed) {
          Navigator.of(context).pop(_displayNameController.text.trim());
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = '保存失败，请重试';
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = '保存失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          '编辑资料',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: (_hasChanges && !_isSubmitting) ? _handleSave : null,
              style: FilledButton.styleFrom(
                backgroundColor: _hasChanges
                    ? const Color(0xFF38B9C5)
                    : const Color(0xFF9CA3AF),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('保存',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_errorMessage!,
                        style: const TextStyle(
                            fontSize: 14, color: Color(0xFFDC2626))),
                  ),
                  const SizedBox(height: 16),
                ],

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: '昵称',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '请输入昵称';
                          if (v.trim().length > 100) return '昵称不能超过100个字符';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: '用户名',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 3) {
                            return '用户名至少3个字符';
                          }
                          if (v.trim().length > 50) {
                            return '用户名不能超过50个字符';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}