import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_channel_provider.dart';

/// WebRTC Monitor Panel - Shows real-time connection statistics
class WebRTCMonitorPanel extends StatefulWidget {
  const WebRTCMonitorPanel({super.key});

  @override
  State<WebRTCMonitorPanel> createState() => _WebRTCMonitorPanelState();
}

class _WebRTCMonitorPanelState extends State<WebRTCMonitorPanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceChannelProvider>(
      builder: (context, voiceProvider, child) {
        if (!voiceProvider.isInVoiceChannel) {
          return const SizedBox.shrink();
        }

        final stats = voiceProvider.stats;

        return Positioned(
          top: 100,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: _isExpanded ? 320 : 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D21).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getConnectionColor(stats.connectionState),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isExpanded
                  ? _buildExpandedPanel(stats, voiceProvider)
                  : _buildCollapsedButton(stats),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedButton(WebRTCStats stats) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = true),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              color: _getConnectionColor(stats.connectionState),
              size: 24,
            ),
            // Pulse animation for active connection
            if (stats.connectionState == 'RTCPeerConnectionStateConnected')
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(WebRTCStats stats, VoiceChannelProvider voiceProvider) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics,
                      color: _getConnectionColor(stats.connectionState),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'WebRTC Monitor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => setState(() => _isExpanded = false),
                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Connection Status
            _buildSection(
              'Baglanti Durumu',
              Icons.wifi,
              [
                _buildStatRow('Durum', _formatConnectionState(stats.connectionState),
                    color: _getConnectionColor(stats.connectionState)),
                _buildStatRow('ICE', _formatIceState(stats.iceConnectionState)),
                _buildStatRow('Signaling', stats.signalingState),
              ],
            ),

            const SizedBox(height: 12),

            // Audio Stats
            _buildSection(
              'Ses Istatistikleri',
              Icons.graphic_eq,
              [
                _buildStatRow('Gonderilen', _formatBytes(stats.bytesSent)),
                _buildStatRow('Alinan', _formatBytes(stats.bytesReceived)),
                _buildStatRow('Paket Gond.', '${stats.packetsSent ?? '-'}'),
                _buildStatRow('Paket Alin.', '${stats.packetsReceived ?? '-'}'),
                _buildStatRow('Paket Kaybi', '${stats.packetsLost ?? '0'}',
                    color: (stats.packetsLost ?? 0) > 10 ? Colors.red : null),
              ],
            ),

            const SizedBox(height: 12),

            // Quality Stats
            _buildSection(
              'Kalite',
              Icons.speed,
              [
                _buildStatRow('RTT', _formatRTT(stats.roundTripTime)),
                _buildStatRow('Jitter', _formatJitter(stats.jitter)),
                _buildStatRow('Codec', stats.audioCodec?.replaceAll('audio/', '') ?? '-'),
                if (stats.sampleRate != null)
                  _buildStatRow('Sample Rate', '${stats.sampleRate} Hz'),
              ],
            ),

            const SizedBox(height: 12),

            // Network Path
            _buildSection(
              'Ag Yolu',
              Icons.route,
              [
                _buildStatRow('Yerel', stats.localCandidateType ?? '-'),
                _buildStatRow('Uzak', stats.remoteCandidateType ?? '-'),
                if (stats.localAddress != null && stats.localAddress != 'null:null')
                  _buildStatRow('Adres', stats.localAddress!, fontSize: 10),
              ],
            ),

            const SizedBox(height: 12),

            // Session Info
            _buildSection(
              'Oturum',
              Icons.timer,
              [
                _buildStatRow('Sure', _formatDuration(voiceProvider.sessionStartTime)),
                _buildStatRow('Mikrofon', voiceProvider.isMuted ? 'Kapali' : 'Acik',
                    color: voiceProvider.isMuted ? Colors.red : Colors.green),
                _buildStatRow('Hoparlor', voiceProvider.isSpeakerOn ? 'Acik' : 'Kapali'),
              ],
            ),

            // Last updated
            if (stats.lastUpdated != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Son guncelleme: ${_formatTime(stats.lastUpdated!)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D3748).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, {Color? color, double fontSize = 11}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: fontSize),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getConnectionColor(String state) {
    switch (state) {
      case 'RTCPeerConnectionStateConnected':
        return Colors.green;
      case 'RTCPeerConnectionStateConnecting':
        return Colors.orange;
      case 'RTCPeerConnectionStateFailed':
        return Colors.red;
      case 'RTCPeerConnectionStateDisconnected':
        return Colors.orange;
      default:
        return Colors.white54;
    }
  }

  String _formatConnectionState(String state) {
    switch (state) {
      case 'RTCPeerConnectionStateConnected':
        return 'Bagli';
      case 'RTCPeerConnectionStateConnecting':
        return 'Baglaniyor';
      case 'RTCPeerConnectionStateFailed':
        return 'Basarisiz';
      case 'RTCPeerConnectionStateDisconnected':
        return 'Kopuk';
      case 'RTCPeerConnectionStateNew':
        return 'Yeni';
      case 'RTCPeerConnectionStateClosed':
        return 'Kapali';
      default:
        return state;
    }
  }

  String _formatIceState(String state) {
    switch (state) {
      case 'RTCIceConnectionStateConnected':
        return 'Bagli';
      case 'RTCIceConnectionStateCompleted':
        return 'Tamamlandi';
      case 'RTCIceConnectionStateChecking':
        return 'Kontrol';
      case 'RTCIceConnectionStateFailed':
        return 'Basarisiz';
      case 'RTCIceConnectionStateDisconnected':
        return 'Kopuk';
      default:
        return state;
    }
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatRTT(double? rtt) {
    if (rtt == null) return '-';
    return '${(rtt * 1000).toStringAsFixed(0)} ms';
  }

  String _formatJitter(double? jitter) {
    if (jitter == null) return '-';
    return '${(jitter * 1000).toStringAsFixed(1)} ms';
  }

  String _formatDuration(DateTime? startTime) {
    if (startTime == null) return '-';
    final duration = DateTime.now().difference(startTime);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
