import 'package:flutter/material.dart';

/// Avatar picker dialog for profile picture selection
/// Uses local assets from assets/images/pp/ folder (pp0.png - pp9.png)
class AvatarPickerDialog extends StatelessWidget {
  final String? currentAvatarId;
  final Function(String avatarId) onAvatarSelected;

  const AvatarPickerDialog({
    super.key,
    this.currentAvatarId,
    required this.onAvatarSelected,
  });

  static const int _avatarCount = 10;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1D21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Profil Resmi Seç',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bir avatar seçin',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _avatarCount,
              itemBuilder: (context, index) {
                final avatarId = 'pp$index';
                final isSelected = currentAvatarId == avatarId;

                return GestureDetector(
                  onTap: () {
                    onAvatarSelected(avatarId);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4A9EFF)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/pp/$avatarId.png',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFF2D3748),
                            child: Icon(
                              Icons.person,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 32,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'İptal',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show the avatar picker dialog
  static Future<void> show(
    BuildContext context, {
    String? currentAvatarId,
    required Function(String avatarId) onAvatarSelected,
  }) {
    return showDialog(
      context: context,
      builder: (context) => AvatarPickerDialog(
        currentAvatarId: currentAvatarId,
        onAvatarSelected: onAvatarSelected,
      ),
    );
  }
}

/// Helper widget to display avatar from avatarId
class AvatarImage extends StatelessWidget {
  final String? avatarId;
  final double size;
  final String? fallbackText;

  const AvatarImage({
    super.key,
    this.avatarId,
    this.size = 40,
    this.fallbackText,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarId != null && avatarId!.isNotEmpty) {
      return ClipOval(
        child: Image.asset(
          'assets/images/pp/$avatarId.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallback();
          },
        ),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF4A9EFF),
      ),
      child: Center(
        child: Text(
          (fallbackText ?? '?').substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
