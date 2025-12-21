import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_channel_provider.dart';

/// Voice channel controls overlay widget
/// Shows mute, speaker, and leave controls when in an active voice channel
class VoiceChannelControls extends StatefulWidget {
  final String otherUserName;

  const VoiceChannelControls({
    super.key,
    required this.otherUserName,
  });

  @override
  State<VoiceChannelControls> createState() => _VoiceChannelControlsState();
}

class _VoiceChannelControlsState extends State<VoiceChannelControls> {
  Timer? _durationTimer;
  Duration _duration = Duration.zero;
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _startDurationTimer();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final voiceProvider = context.read<VoiceChannelProvider>();
      if (voiceProvider.sessionStartTime != null) {
        setState(() {
          _duration = DateTime.now().difference(voiceProvider.sessionStartTime!);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceChannelProvider>(
      builder: (context, voiceProvider, child) {
        // Only show if in voice channel
        if (!voiceProvider.isInVoiceChannel) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D21),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isExpanded
              ? _buildExpandedControls(voiceProvider)
              : _buildCollapsedControls(voiceProvider),
        );
      },
    );
  }

  Widget _buildCollapsedControls(VoiceChannelProvider voiceProvider) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusIndicator(voiceProvider.state),
            const SizedBox(width: 8),
            Text(
              _getStatusText(voiceProvider.state),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_less, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedControls(VoiceChannelProvider voiceProvider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with collapse button
          Row(
            children: [
              _buildStatusIndicator(voiceProvider.state),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStatusText(voiceProvider.state),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (voiceProvider.state == VoiceChannelState.active)
                      Text(
                        widget.otherUserName,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _isExpanded = false),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.expand_more, color: Colors.white54, size: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildControlButton(
                icon: voiceProvider.isMuted ? Icons.mic_off : Icons.mic,
                label: voiceProvider.isMuted ? 'Sesi Ac' : 'Sustur',
                isActive: !voiceProvider.isMuted,
                activeColor: const Color(0xFF4A9EFF),
                onTap: () => voiceProvider.toggleMute(),
              ),
              _buildControlButton(
                icon: voiceProvider.isSpeakerOn
                    ? Icons.volume_up
                    : Icons.volume_off,
                label: voiceProvider.isSpeakerOn ? 'Hoparlor' : 'Hoparlor',
                isActive: voiceProvider.isSpeakerOn,
                activeColor: const Color(0xFF4A9EFF),
                onTap: () => voiceProvider.toggleSpeaker(),
              ),
              _buildControlButton(
                icon: Icons.call_end,
                label: 'Ayril',
                isActive: true,
                activeColor: Colors.redAccent,
                onTap: () => voiceProvider.leaveVoiceChannel(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(VoiceChannelState state) {
    Color color;
    bool shouldPulse = false;

    switch (state) {
      case VoiceChannelState.active:
        color = const Color(0xFF48BB78);
        break;
      case VoiceChannelState.waiting:
      case VoiceChannelState.connecting:
        color = Colors.orange;
        shouldPulse = true;
        break;
      case VoiceChannelState.reconnecting:
        color = Colors.orange;
        shouldPulse = true;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        boxShadow: shouldPulse
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }

  String _getStatusText(VoiceChannelState state) {
    switch (state) {
      case VoiceChannelState.idle:
        return 'Bagli degil';
      case VoiceChannelState.joining:
        return 'Baglaniyor...';
      case VoiceChannelState.waiting:
        return 'Bekleniyor';
      case VoiceChannelState.connecting:
        return 'Baglaniliyor...';
      case VoiceChannelState.active:
        return 'Sesli Sohbet';
      case VoiceChannelState.reconnecting:
        return 'Yeniden baglaniyor...';
      case VoiceChannelState.leaving:
        return 'Ayriliyor...';
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.2)
                  : const Color(0xFF2D3748),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isActive ? activeColor : Colors.white24,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white54,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
