import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/webrtc_config.dart';
import '../services/logger_service.dart';

/// Voice channel state
enum VoiceChannelState {
  idle,        // Not in voice channel
  joining,     // Connecting to voice channel
  waiting,     // In voice channel, waiting for other user
  connecting,  // WebRTC connection in progress
  active,      // In voice channel, connected with other user
  reconnecting,// Connection issue, trying to reconnect
  leaving,     // Disconnecting from voice channel
}

/// Voice channel provider for managing WebRTC voice sessions in DMs
class VoiceChannelProvider extends ChangeNotifier {
  final LoggerService _logger = LoggerService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // State
  VoiceChannelState _state = VoiceChannelState.idle;
  String? _currentWorkspaceId;
  String? _currentDmId;
  String? _currentSessionId;
  String? _currentUserId;
  String? _otherUserId;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  DateTime? _sessionStartTime;
  String? _errorMessage;

  // WebRTC
  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;
  webrtc.MediaStream? _remoteStream;

  // Firestore subscriptions
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _signalingSubscription;

  // Getters
  VoiceChannelState get state => _state;
  String? get currentDmId => _currentDmId;
  String? get currentSessionId => _currentSessionId;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  DateTime? get sessionStartTime => _sessionStartTime;
  String? get errorMessage => _errorMessage;
  bool get isInVoiceChannel => _state != VoiceChannelState.idle;

  /// Check if microphone permission is granted
  Future<bool> checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Request microphone permission
  /// Returns: 'granted', 'denied', 'permanentlyDenied'
  Future<String> requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    _logger.info('Microphone permission status: ${status.name}', category: 'VOICE');

    if (status.isGranted) {
      return 'granted';
    }

    if (status.isPermanentlyDenied) {
      _logger.warning('Microphone permission permanently denied', category: 'VOICE');
      return 'permanentlyDenied';
    }

    // Request permission
    status = await Permission.microphone.request();
    _logger.info('Microphone permission after request: ${status.name}', category: 'VOICE');

    if (status.isGranted) {
      return 'granted';
    } else if (status.isPermanentlyDenied) {
      return 'permanentlyDenied';
    }
    return 'denied';
  }

  /// Open app settings for permission
  Future<bool> openPermissionSettings() async {
    return await openAppSettings();
  }

  /// Join voice channel for a DM
  Future<bool> joinVoiceChannel({
    required String workspaceId,
    required String dmId,
    required String currentUserId,
    required String otherUserId,
  }) async {
    if (_state != VoiceChannelState.idle) {
      _logger.warning('Already in a voice channel', category: 'VOICE');
      return false;
    }

    try {
      _setState(VoiceChannelState.joining);
      _currentWorkspaceId = workspaceId;
      _currentDmId = dmId;
      _currentUserId = currentUserId;
      _otherUserId = otherUserId;
      _errorMessage = null;

      _logger.info('Joining voice channel', category: 'VOICE', data: {
        'dmId': dmId,
        'userId': currentUserId,
      });

      // Request microphone permission
      final permissionResult = await requestMicrophonePermission();
      if (permissionResult != 'granted') {
        if (permissionResult == 'permanentlyDenied') {
          _errorMessage = 'permanentlyDenied';
        } else {
          _errorMessage = 'Mikrofon izni reddedildi';
        }
        _cleanup();
        return false;
      }

      // Get local audio stream
      _localStream = await webrtc.navigator.mediaDevices.getUserMedia(WebRTCConfig.mediaConstraints);
      _logger.debug('Local stream acquired', category: 'VOICE');

      // Get or create voice session
      final sessionRef = await _getOrCreateSession();
      if (sessionRef == null) {
        _errorMessage = 'Oturum oluşturulamadı';
        _cleanup();
        return false;
      }
      _currentSessionId = sessionRef.id;

      // Add self to active participants
      await sessionRef.update({
        'activeParticipants': FieldValue.arrayUnion([currentUserId]),
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Set up peer connection
      await _setupPeerConnection();

      // Listen to session changes (participant joins/leaves)
      _listenToSessionChanges();

      // Listen to signaling messages
      _listenToSignaling();

      _sessionStartTime = DateTime.now();
      _setState(VoiceChannelState.waiting);

      _logger.success('Joined voice channel', category: 'VOICE');
      return true;
    } catch (e) {
      _logger.error('Failed to join voice channel: $e', category: 'VOICE');
      _errorMessage = 'Bağlantı hatası: $e';
      _cleanup();
      return false;
    }
  }

  /// Leave voice channel
  Future<void> leaveVoiceChannel() async {
    if (_state == VoiceChannelState.idle) return;

    try {
      _setState(VoiceChannelState.leaving);
      _logger.info('Leaving voice channel', category: 'VOICE');

      // Remove self from active participants
      if (_currentSessionId != null && _currentUserId != null) {
        final sessionRef = _getSessionRef();
        await sessionRef.update({
          'activeParticipants': FieldValue.arrayRemove([_currentUserId]),
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        });

        // Send leave signal to other peer
        if (_otherUserId != null) {
          await _sendSignal('leave', {});
        }
      }

      _logger.success('Left voice channel', category: 'VOICE');
    } catch (e) {
      _logger.error('Error leaving voice channel: $e', category: 'VOICE');
    } finally {
      _cleanup();
    }
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    _logger.debug('Mute toggled: $_isMuted', category: 'VOICE');
    notifyListeners();
  }

  /// Toggle speaker
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    _remoteStream?.getAudioTracks().forEach((track) {
      track.enabled = _isSpeakerOn;
    });

    // Switch audio output
    if (!kIsWeb) {
      await webrtc.Helper.setSpeakerphoneOn(_isSpeakerOn);
    }

    _logger.debug('Speaker toggled: $_isSpeakerOn', category: 'VOICE');
    notifyListeners();
  }

  /// Get or create voice session
  Future<DocumentReference?> _getOrCreateSession() async {
    final sessionsRef = _firestore
        .collection('workspaces')
        .doc(_currentWorkspaceId)
        .collection('directMessages')
        .doc(_currentDmId)
        .collection('voiceSessions');

    // Check for active session
    final activeQuery = await sessionsRef
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (activeQuery.docs.isNotEmpty) {
      _logger.debug('Found active session', category: 'VOICE');
      return activeQuery.docs.first.reference;
    }

    // Create new session
    final newSession = sessionsRef.doc();
    await newSession.set({
      'sessionId': newSession.id,
      'dmId': _currentDmId,
      'activeParticipants': [],
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });

    _logger.debug('Created new session: ${newSession.id}', category: 'VOICE');
    return newSession;
  }

  /// Get session reference
  DocumentReference _getSessionRef() {
    return _firestore
        .collection('workspaces')
        .doc(_currentWorkspaceId)
        .collection('directMessages')
        .doc(_currentDmId)
        .collection('voiceSessions')
        .doc(_currentSessionId);
  }

  /// Set up WebRTC peer connection
  Future<void> _setupPeerConnection() async {
    _peerConnection = await webrtc.createPeerConnection(
      WebRTCConfig.iceServers,
      {},
    );

    // Add local stream tracks
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // Handle ICE candidates
    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendSignal('ice-candidate', {
          'candidate': candidate.candidate,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'sdpMid': candidate.sdpMid,
        });
      }
    };

    // Handle remote stream
    _peerConnection?.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        _logger.debug('Remote stream received', category: 'VOICE');
        notifyListeners();
      }
    };

    // Handle connection state
    _peerConnection?.onConnectionState = (state) {
      _logger.debug('Connection state: $state', category: 'VOICE');
      if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(VoiceChannelState.active);
      } else if (state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
                 state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_state == VoiceChannelState.active) {
          _setState(VoiceChannelState.reconnecting);
          _attemptReconnect();
        }
      }
    };

    // Handle ICE connection state
    _peerConnection?.onIceConnectionState = (state) {
      _logger.debug('ICE connection state: $state', category: 'VOICE');
    };

    _logger.debug('Peer connection set up', category: 'VOICE');
  }

  /// Listen to session changes
  void _listenToSessionChanges() {
    _sessionSubscription = _getSessionRef().snapshots().listen((snapshot) {
      if (!snapshot.exists) {
        _logger.warning('Session deleted', category: 'VOICE');
        _cleanup();
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final participants = List<String>.from(data['activeParticipants'] ?? []);

      _logger.debug('Session updated, participants: $participants', category: 'VOICE');

      // Check if other user joined
      if (participants.contains(_otherUserId) &&
          participants.contains(_currentUserId)) {
        // Both users are in the channel
        if (_state == VoiceChannelState.waiting) {
          _initiateWebRTCConnection();
        }
      } else if (!participants.contains(_otherUserId) &&
                 _state == VoiceChannelState.active) {
        // Other user left
        _logger.info('Other user left the voice channel', category: 'VOICE');
        _setState(VoiceChannelState.waiting);
        _closePeerConnection();
      }
    });
  }

  /// Listen to signaling messages
  void _listenToSignaling() {
    final signalingRef = _getSessionRef().collection('signaling');

    _signalingSubscription = signalingRef
        .where('to', isEqualTo: _currentUserId)
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          await _processSignal(change.doc);
        }
      }
    });
  }

  /// Process incoming signaling message
  Future<void> _processSignal(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] as String;
    final signalData = data['data'] as Map<String, dynamic>;

    _logger.debug('Processing signal: $type', category: 'VOICE');

    try {
      switch (type) {
        case 'offer':
          await _handleOffer(signalData);
          break;
        case 'answer':
          await _handleAnswer(signalData);
          break;
        case 'ice-candidate':
          await _handleIceCandidate(signalData);
          break;
        case 'leave':
          _logger.info('Received leave signal', category: 'VOICE');
          _setState(VoiceChannelState.waiting);
          _closePeerConnection();
          break;
      }

      // Delete processed signal
      await doc.reference.delete();
    } catch (e) {
      _logger.error('Error processing signal: $e', category: 'VOICE');
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(Map<String, dynamic> data) async {
    _setState(VoiceChannelState.connecting);

    final description = webrtc.RTCSessionDescription(
      data['sdp'],
      data['type'],
    );

    await _peerConnection?.setRemoteDescription(description);

    // Create answer
    final answer = await _peerConnection?.createAnswer(
      WebRTCConfig.answerSdpConstraints,
    );
    await _peerConnection?.setLocalDescription(answer!);

    // Send answer
    await _sendSignal('answer', {
      'sdp': answer?.sdp,
      'type': answer?.type,
    });

    _logger.debug('Sent answer', category: 'VOICE');
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final description = webrtc.RTCSessionDescription(
      data['sdp'],
      data['type'],
    );

    await _peerConnection?.setRemoteDescription(description);
    _logger.debug('Answer set', category: 'VOICE');
  }

  /// Handle incoming ICE candidate
  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final candidate = webrtc.RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );

    await _peerConnection?.addCandidate(candidate);
    _logger.debug('ICE candidate added', category: 'VOICE');
  }

  /// Initiate WebRTC connection (create and send offer)
  Future<void> _initiateWebRTCConnection() async {
    // Only the user with the smaller userId creates the offer
    // This prevents both users from creating offers simultaneously
    if (_currentUserId!.compareTo(_otherUserId!) > 0) {
      _logger.debug('Waiting for offer from other user', category: 'VOICE');
      _setState(VoiceChannelState.connecting);
      return;
    }

    _logger.info('Initiating WebRTC connection', category: 'VOICE');
    _setState(VoiceChannelState.connecting);

    try {
      // Create offer
      final offer = await _peerConnection?.createOffer(
        WebRTCConfig.offerSdpConstraints,
      );
      await _peerConnection?.setLocalDescription(offer!);

      // Send offer
      await _sendSignal('offer', {
        'sdp': offer?.sdp,
        'type': offer?.type,
      });

      _logger.debug('Sent offer', category: 'VOICE');
    } catch (e) {
      _logger.error('Error creating offer: $e', category: 'VOICE');
      _errorMessage = 'Bağlantı kurulamadı';
      _setState(VoiceChannelState.waiting);
    }
  }

  /// Send signaling message
  Future<void> _sendSignal(String type, Map<String, dynamic> data) async {
    if (_otherUserId == null || _currentSessionId == null) return;

    final signalingRef = _getSessionRef().collection('signaling');

    await signalingRef.add({
      'type': type,
      'from': _currentUserId,
      'to': _otherUserId,
      'data': data,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Attempt to reconnect
  Future<void> _attemptReconnect() async {
    _logger.info('Attempting to reconnect', category: 'VOICE');

    for (int i = 0; i < WebRTCConfig.maxReconnectAttempts; i++) {
      await Future.delayed(
        Duration(milliseconds: WebRTCConfig.reconnectDelayMs),
      );

      if (_state != VoiceChannelState.reconnecting) break;

      try {
        await _closePeerConnection();
        await _setupPeerConnection();
        _initiateWebRTCConnection();
        return;
      } catch (e) {
        _logger.warning('Reconnect attempt ${i + 1} failed', category: 'VOICE');
      }
    }

    _logger.error('Failed to reconnect after max attempts', category: 'VOICE');
    _errorMessage = 'Bağlantı koptu';
    await leaveVoiceChannel();
  }

  /// Close peer connection
  Future<void> _closePeerConnection() async {
    await _peerConnection?.close();
    _peerConnection = null;
    _remoteStream = null;
  }

  /// Set state and notify listeners
  void _setState(VoiceChannelState newState) {
    _state = newState;
    notifyListeners();
  }

  /// Cleanup resources
  void _cleanup() {
    _sessionSubscription?.cancel();
    _sessionSubscription = null;

    _signalingSubscription?.cancel();
    _signalingSubscription = null;

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    _remoteStream?.dispose();
    _remoteStream = null;

    _peerConnection?.close();
    _peerConnection = null;

    _currentWorkspaceId = null;
    _currentDmId = null;
    _currentSessionId = null;
    _currentUserId = null;
    _otherUserId = null;
    _isMuted = false;
    _isSpeakerOn = true;
    _sessionStartTime = null;

    _setState(VoiceChannelState.idle);
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
