/// WebRTC configuration for voice channels
class WebRTCConfig {
  // ICE Servers for NAT traversal
  static final Map<String, dynamic> iceServers = {
    'iceServers': [
      // Google STUN servers (free, public)
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // Audio-only media constraints (cross-platform compatible)
  static final Map<String, dynamic> mediaConstraints = {
    'audio': true,  // Basit constraint, tüm platformlarda çalışır
    'video': false,
  };

  // Offer constraints
  static final Map<String, dynamic> offerSdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  // Answer constraints
  static final Map<String, dynamic> answerSdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  // Connection timeout in seconds
  static const int connectionTimeout = 30;

  // Reconnection attempts
  static const int maxReconnectAttempts = 3;

  // Time between reconnection attempts in milliseconds
  static const int reconnectDelayMs = 2000;
}
