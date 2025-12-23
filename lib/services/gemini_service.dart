import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'logger_service.dart';

/// Message model for chat history
class ChatMessage {
  final String role; // 'user' or 'model'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'role': role,
    'parts': [{'text': content}],
  };

  Map<String, dynamic> toMap() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    role: map['role'] ?? 'user',
    content: map['content'] ?? '',
    timestamp: map['timestamp'] != null
        ? DateTime.parse(map['timestamp'])
        : DateTime.now(),
  );
}

/// Gemini Service for HeyBridge Agent
/// Each user has their own chat history stored per-user
class GeminiService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LoggerService _logger = LoggerService();

  String? _apiKey;
  String? _modelVersion;
  bool _isInitialized = false;
  String? _currentUserId;

  // Chat history for current user (in-memory cache)
  final List<ChatMessage> _chatHistory = [];

  // Singleton pattern
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  bool get isInitialized => _isInitialized;
  List<ChatMessage> get chatHistory => List.unmodifiable(_chatHistory);
  String? get currentUserId => _currentUserId;

  /// Initialize service by fetching config from Firebase
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing Gemini service', category: 'GEMINI');

    try {
      final doc = await _firestore
          .collection('system')
          .doc('generalConfigs')
          .get();

      if (!doc.exists) {
        throw Exception('generalConfigs document not found');
      }

      final data = doc.data()!;
      _apiKey = data['geminiAPIKey'] as String?;
      _modelVersion = data['geminiVersion'] as String?;

      if (_apiKey == null || _apiKey!.isEmpty) {
        throw Exception('Gemini API key not found in config');
      }

      if (_modelVersion == null || _modelVersion!.isEmpty) {
        _modelVersion = 'gemini-2.0-flash-exp'; // Default fallback
      }

      _isInitialized = true;
      _logger.success(
        'Gemini service initialized',
        category: 'GEMINI',
        data: {'model': _modelVersion},
      );
    } catch (e) {
      _logger.error(
        'Failed to initialize Gemini service: $e',
        category: 'GEMINI',
      );
      rethrow;
    }
  }

  /// Set current user and load their chat history
  Future<void> setUser(String userId) async {
    if (_currentUserId == userId) return;

    _currentUserId = userId;
    _chatHistory.clear();

    _logger.info('Loading chat history for user',
        category: 'GEMINI', data: {'userId': userId});

    try {
      // Load chat history from Firestore
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('agentChats')
          .doc('history')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final messages = data['messages'] as List<dynamic>? ?? [];

        for (final msg in messages) {
          _chatHistory.add(ChatMessage.fromMap(Map<String, dynamic>.from(msg)));
        }

        _logger.info('Loaded ${_chatHistory.length} messages from history',
            category: 'GEMINI');
      }
    } catch (e) {
      _logger.error('Failed to load chat history: $e', category: 'GEMINI');
      // Continue with empty history
    }
  }

  /// Save chat history to Firestore
  Future<void> _saveChatHistory() async {
    if (_currentUserId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_currentUserId)
          .collection('agentChats')
          .doc('history')
          .set({
        'messages': _chatHistory.map((m) => m.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logger.error('Failed to save chat history: $e', category: 'GEMINI');
    }
  }

  /// Send a message to Gemini and get a response
  Future<String> sendMessage(String message) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_currentUserId == null) {
      throw Exception('User not set. Call setUser() first.');
    }

    _logger.info(
      'Sending message to Gemini',
      category: 'GEMINI',
      data: {'messageLength': message.length, 'userId': _currentUserId},
    );

    // Add user message to history
    _chatHistory.add(ChatMessage(role: 'user', content: message));

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_modelVersion:generateContent?key=$_apiKey',
      );

      // Build request body with chat history for context
      final requestBody = {
        'contents': _chatHistory.map((m) => m.toJson()).toList(),
        'generationConfig': {
          'temperature': 0.7,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 2048,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
        ],
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extract response text
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No response candidates from Gemini');
        }

        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw Exception('No response parts from Gemini');
        }

        final responseText = parts[0]['text'] as String;

        // Add model response to history
        _chatHistory.add(ChatMessage(role: 'model', content: responseText));

        // Save to Firestore
        await _saveChatHistory();

        _logger.success(
          'Received response from Gemini',
          category: 'GEMINI',
          data: {'responseLength': responseText.length},
        );

        return responseText;
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? 'Unknown error';
        throw Exception('Gemini API error (${response.statusCode}): $errorMessage');
      }
    } catch (e) {
      // Remove failed user message from history
      if (_chatHistory.isNotEmpty && _chatHistory.last.role == 'user') {
        _chatHistory.removeLast();
      }

      _logger.error(
        'Failed to get Gemini response: $e',
        category: 'GEMINI',
      );
      rethrow;
    }
  }

  /// Clear chat history to start a new conversation
  Future<void> clearHistory() async {
    _chatHistory.clear();

    // Also clear from Firestore
    if (_currentUserId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_currentUserId)
            .collection('agentChats')
            .doc('history')
            .delete();
      } catch (e) {
        _logger.error('Failed to delete chat history: $e', category: 'GEMINI');
      }
    }

    _logger.info('Chat history cleared', category: 'GEMINI');
  }

  /// Clear user session (call on logout)
  void clearUserSession() {
    _currentUserId = null;
    _chatHistory.clear();
    _logger.info('User session cleared', category: 'GEMINI');
  }

  /// Get the current model version
  String? get modelVersion => _modelVersion;

  /// Generate a summary of unread messages with per-user suggestions
  /// Returns a structured response with summary, actions, and per-target suggestions
  Future<String> generateSummary({
    required List<Map<String, dynamic>> channelMessages,
    required List<Map<String, dynamic>> dmMessages,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    _logger.info(
      'Generating summary',
      category: 'GEMINI',
      data: {
        'channelCount': channelMessages.length,
        'dmCount': dmMessages.length,
      },
    );

    // Build the prompt
    final buffer = StringBuffer();
    buffer.writeln('Sen HeyBridge uygulamasının AI asistanısın. Kullanıcının okunmamış mesajlarını özetle.');
    buffer.writeln('Özeti Türkçe olarak yaz. Kısa ve öz ol.');
    buffer.writeln('');

    if (channelMessages.isEmpty && dmMessages.isEmpty) {
      return '''📭 Okunmamış mesaj yok!

Tüm mesajlarınızı okudunuz. Harika iş! 🎉''';
    }

    if (channelMessages.isNotEmpty) {
      buffer.writeln('📢 KANAL MESAJLARI:');
      for (final channel in channelMessages) {
        buffer.writeln('');
        buffer.writeln('# ${channel['channelName']} (${channel['messages'].length} mesaj):');
        for (final msg in channel['messages']) {
          buffer.writeln('- ${msg['senderName']}: ${msg['text']}');
        }
      }
      buffer.writeln('');
    }

    if (dmMessages.isNotEmpty) {
      buffer.writeln('💬 DİREKT MESAJLAR:');
      for (final dm in dmMessages) {
        buffer.writeln('');
        buffer.writeln('# ${dm['otherUserName']} (${dm['messages'].length} mesaj):');
        for (final msg in dm['messages']) {
          buffer.writeln('- ${msg['senderName']}: ${msg['text']}');
        }
      }
      buffer.writeln('');
    }

    buffer.writeln('');
    buffer.writeln('Lütfen yukarıdaki mesajları özetle ve her kişi/kanal için ayrı ayrı cevap önerileri oluştur.');
    buffer.writeln('');
    buffer.writeln('FORMAT (bu formatı tam olarak takip et):');
    buffer.writeln('1. Genel özet yaz');
    buffer.writeln('2. Aksiyon gerektiren şeyleri "**Aksiyon:**" başlığı altında belirt');
    buffer.writeln('3. Her kişi/kanal için ayrı öneri bölümü oluştur. Format:');
    buffer.writeln('');
    buffer.writeln('**Öneriler:**');
    buffer.writeln('');

    // Add per-target suggestion format
    for (final dm in dmMessages) {
      buffer.writeln('[DM:${dm['otherUserName']}]');
      buffer.writeln('- Bu kişiye özel öneri cevap 1 (tam cümle olabilir)');
      buffer.writeln('- Bu kişiye özel öneri cevap 2');
      buffer.writeln('');
    }

    for (final channel in channelMessages) {
      buffer.writeln('[KANAL:${channel['channelName']}]');
      buffer.writeln('- Bu kanala özel öneri cevap 1');
      buffer.writeln('- Bu kanala özel öneri cevap 2');
      buffer.writeln('');
    }

    buffer.writeln('ÖNEMLİ KURALLAR:');
    buffer.writeln('- Her öneri mesaj içeriğine uygun ve anlamlı olmalı');
    buffer.writeln('- Öneriler tam cümle olabilir (kısa tutmak zorunda değilsin)');
    buffer.writeln('- Her kişi/kanal için 1-2 öneri yeterli');
    buffer.writeln('- [DM:İsim] ve [KANAL:İsim] formatını tam olarak koru');
    buffer.writeln('- Emoji kullanabilirsin');

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_modelVersion:generateContent?key=$_apiKey',
      );

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [{'text': buffer.toString()}],
          }
        ],
        'generationConfig': {
          'temperature': 0.5,
          'topK': 40,
          'topP': 0.95,
          'maxOutputTokens': 1024,
        },
        'safetySettings': [
          {
            'category': 'HARM_CATEGORY_HARASSMENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_HATE_SPEECH',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
          {
            'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
            'threshold': 'BLOCK_MEDIUM_AND_ABOVE',
          },
        ],
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('No response from Gemini');
        }

        final content = candidates[0]['content'];
        final parts = content['parts'] as List?;
        if (parts == null || parts.isEmpty) {
          throw Exception('No response parts from Gemini');
        }

        final responseText = parts[0]['text'] as String;

        _logger.success('Summary generated', category: 'GEMINI');
        return responseText;
      } else {
        final errorBody = jsonDecode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? 'Unknown error';
        throw Exception('Gemini API error: $errorMessage');
      }
    } catch (e) {
      _logger.error('Failed to generate summary: $e', category: 'GEMINI');
      rethrow;
    }
  }
}
