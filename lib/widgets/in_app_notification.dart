import 'package:flutter/material.dart';

/// In-app notification banner that slides down from top
/// Similar to WhatsApp/Telegram style notifications
class InAppNotification {
  static OverlayEntry? _currentOverlay;
  static bool _isShowing = false;

  /// Show an in-app notification banner
  static void show({
    required BuildContext context,
    required String title,
    required String body,
    String? avatarUrl,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    // Don't show if already showing
    if (_isShowing) {
      _currentOverlay?.remove();
      _currentOverlay = null;
    }

    _isShowing = true;

    final overlay = Overlay.of(context);

    _currentOverlay = OverlayEntry(
      builder: (context) => _InAppNotificationWidget(
        title: title,
        body: body,
        avatarUrl: avatarUrl,
        onTap: () {
          dismiss();
          onTap?.call();
        },
        onDismiss: dismiss,
        duration: duration,
      ),
    );

    overlay.insert(_currentOverlay!);
  }

  /// Dismiss the current notification
  static void dismiss() {
    _currentOverlay?.remove();
    _currentOverlay = null;
    _isShowing = false;
  }
}

class _InAppNotificationWidget extends StatefulWidget {
  final String title;
  final String body;
  final String? avatarUrl;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;
  final Duration duration;

  const _InAppNotificationWidget({
    required this.title,
    required this.body,
    this.avatarUrl,
    this.onTap,
    required this.onDismiss,
    required this.duration,
  });

  @override
  State<_InAppNotificationWidget> createState() => _InAppNotificationWidgetState();
}

class _InAppNotificationWidgetState extends State<_InAppNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Start animation
    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismissWithAnimation();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissWithAnimation() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onTap: widget.onTap,
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! < -10) {
                _dismissWithAnimation();
              }
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: EdgeInsets.only(
                  top: topPadding + 8,
                  left: 12,
                  right: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D3748),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Avatar or icon
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A9EFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  widget.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.chat_bubble_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                      ),
                      const SizedBox(width: 12),
                      // Title and body
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.body,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Close button
                      IconButton(
                        onPressed: _dismissWithAnimation,
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
