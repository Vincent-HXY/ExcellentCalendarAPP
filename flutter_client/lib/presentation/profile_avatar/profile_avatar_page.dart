import 'dart:io';

import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';

/// Avatar edit page — select image, crop, upload.
///
/// States: initial, selected, uploading, success, error.
class ProfileAvatarPage extends StatefulWidget {
  const ProfileAvatarPage({
    required this.authController,
    this.currentAvatarUrl,
    super.key,
  });

  final AuthController authController;
  final String? currentAvatarUrl;

  @override
  State<ProfileAvatarPage> createState() => _ProfileAvatarPageState();
}

class _ProfileAvatarPageState extends State<ProfileAvatarPage> {
  // Simulated — will use image_picker in production
  String? _selectedImagePath;
  bool _isUploading = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _pickImage() async {
    // Simulate image selection (image_picker dependency not available yet)
    // In production, use: final picked = await ImagePicker().pickImage();
    setState(() {
      _selectedImagePath = '/tmp/simulated_avatar.jpg';
      _errorMessage = null;
    });
  }

  Future<void> _uploadAvatar() async {
    if (_selectedImagePath == null || _isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      final file = File(_selectedImagePath!);
      final bytes = await file.readAsBytes();
      final filename = _selectedImagePath!.split('/').last;

      final success = await widget.authController.uploadAvatar(
        fileBytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      );
      if (_disposed) return;

      if (success) {
        setState(() => _isUploading = false);
        if (!_disposed) {
          Navigator.of(context).maybePop();
        }
      } else {
        setState(() {
          _isUploading = false;
          _errorMessage = '上传失败，请重试';
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _isUploading = false;
          _errorMessage = '上传失败，请重试';
        });
      }
    }
  }

  Future<void> _deleteAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除头像'),
        content: const Text('确定要删除头像吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _selectedImagePath = null;
        _errorMessage = null;
      });

      try {
        final success = await widget.authController.deleteAvatar();
        if (_disposed) return;

        if (success && !_disposed) {
          Navigator.of(context).maybePop();
        }
      } catch (_) {
        if (!_disposed) {
          setState(() => _errorMessage = '删除失败，请重试');
        }
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
          '修改头像',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Avatar preview
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _selectedImagePath != null
                      ? ClipOval(
                          child: Image.file(
                            File(_selectedImagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.person_rounded,
                              size: 80,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        )
                      : (widget.currentAvatarUrl != null
                          ? ClipOval(
                              child: Image.network(
                                widget.currentAvatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person_rounded,
                                  size: 80,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.person_rounded,
                              size: 80,
                              color: Color(0xFF9CA3AF),
                            )),
                ),
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 20, color: Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFFDC2626))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Upload progress
              if (_isUploading) ...[
                const LinearProgressIndicator(
                  backgroundColor: Color(0xFFE5E7EB),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF38B9C5)),
                ),
                const SizedBox(height: 8),
                const Text('正在上传…',
                    style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                const SizedBox(height: 24),
              ],

              // Buttons
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: (_isUploading) ? null : _pickImage,
                  icon: const Icon(Icons.image_rounded),
                  label: const Text('选择图片'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38B9C5),
                    disabledBackgroundColor: const Color(0xFF9CA3AF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_selectedImagePath != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isUploading ? null : _uploadAvatar,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text('上传头像'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      disabledBackgroundColor: const Color(0xFF9CA3AF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Delete avatar
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isUploading ? null : _deleteAvatar,
                  icon: const Icon(Icons.delete_rounded,
                      color: Color(0xFFEF4444)),
                  label: const Text('删除头像',
                      style: TextStyle(color: Color(0xFFEF4444))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}