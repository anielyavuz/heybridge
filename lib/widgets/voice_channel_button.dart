import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/voice_channel_provider.dart';

/// Voice channel join/leave button widget for DM screens
class VoiceChannelButton extends StatelessWidget {
  final String workspaceId;
  final String dmId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;

  const VoiceChannelButton({
    super.key,
    required this.workspaceId,
    required this.dmId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceChannelProvider>(
      builder: (context, voiceProvider, child) {
        final isInThisChannel = voiceProvider.currentDmId == dmId &&
            voiceProvider.isInVoiceChannel;

        return _buildButton(context, voiceProvider, isInThisChannel);
      },
    );
  }

  Widget _buildButton(
    BuildContext context,
    VoiceChannelProvider voiceProvider,
    bool isInThisChannel,
  ) {
    final state = voiceProvider.state;

    // If in a different channel, show disabled button
    if (voiceProvider.isInVoiceChannel && !isInThisChannel) {
      return _buildDisabledButton('Baska sohbette');
    }

    switch (state) {
      case VoiceChannelState.idle:
        return _buildJoinButton(context, voiceProvider);

      case VoiceChannelState.joining:
        return _buildLoadingButton('Baglaniyor...');

      case VoiceChannelState.waiting:
        return _buildWaitingButton(context, voiceProvider);

      case VoiceChannelState.connecting:
        return _buildLoadingButton('Baglaniliyor...');

      case VoiceChannelState.active:
        return _buildActiveButton(context, voiceProvider);

      case VoiceChannelState.reconnecting:
        return _buildLoadingButton('Yeniden baglaniyor...');

      case VoiceChannelState.leaving:
        return _buildLoadingButton('Ayriliyor...');
    }
  }

  Widget _buildJoinButton(
    BuildContext context,
    VoiceChannelProvider voiceProvider,
  ) {
    return InkWell(
      onTap: () => _joinVoice(context, voiceProvider),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D3748),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, color: Colors.white70, size: 20),
            SizedBox(width: 8),
            Text(
              'Sesli Sohbet',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingButton(
    BuildContext context,
    VoiceChannelProvider voiceProvider,
  ) {
    return InkWell(
      onTap: () => _leaveVoice(voiceProvider),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4A9EFF), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Bekleniyor...',
              style: TextStyle(
                color: Color(0xFF4A9EFF),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.close, color: Colors.white54, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveButton(
    BuildContext context,
    VoiceChannelProvider voiceProvider,
  ) {
    return InkWell(
      onTap: () => _leaveVoice(voiceProvider),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF48BB78).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF48BB78), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF48BB78),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$otherUserName ile sohbette',
              style: const TextStyle(
                color: Color(0xFF48BB78),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.call_end, color: Colors.redAccent, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4A9EFF)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisabledButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_off, color: Colors.white38, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinVoice(
    BuildContext context,
    VoiceChannelProvider voiceProvider,
  ) async {
    final success = await voiceProvider.joinVoiceChannel(
      workspaceId: workspaceId,
      dmId: dmId,
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );

    if (!success && context.mounted) {
      final errorMessage = voiceProvider.errorMessage;

      // Check if permission is permanently denied
      if (errorMessage == 'permanentlyDenied') {
        _showPermissionDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage ?? 'Baglanti hatasi'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D21),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.mic_off, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Text(
              'Mikrofon Izni Gerekli',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Sesli sohbet icin mikrofon iznine ihtiyacimiz var. Lutfen ayarlardan mikrofon iznini etkinlestirin.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Iptal',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A9EFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Ayarlara Git',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _leaveVoice(VoiceChannelProvider voiceProvider) {
    voiceProvider.leaveVoiceChannel();
  }
}
