import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _lastWorkspaceIdKey = 'last_workspace_id';
  static const String _quickEmojiKey = 'quick_emoji';
  static const String _defaultQuickEmoji = '❤️';

  // Singleton pattern
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Save last workspace ID
  Future<void> saveLastWorkspaceId(String workspaceId) async {
    await init();
    await _prefs?.setString(_lastWorkspaceIdKey, workspaceId);
  }

  // Get last workspace ID
  Future<String?> getLastWorkspaceId() async {
    await init();
    return _prefs?.getString(_lastWorkspaceIdKey);
  }

  // Clear last workspace ID
  Future<void> clearLastWorkspaceId() async {
    await init();
    await _prefs?.remove(_lastWorkspaceIdKey);
  }

  // Clear all preferences
  Future<void> clearAll() async {
    await init();
    await _prefs?.clear();
  }

  // Save quick emoji for double-tap reaction
  Future<void> saveQuickEmoji(String emoji) async {
    await init();
    await _prefs?.setString(_quickEmojiKey, emoji);
  }

  // Get quick emoji (default: ❤️)
  Future<String> getQuickEmoji() async {
    await init();
    return _prefs?.getString(_quickEmojiKey) ?? _defaultQuickEmoji;
  }

  // Get quick emoji synchronously (after init)
  String getQuickEmojiSync() {
    return _prefs?.getString(_quickEmojiKey) ?? _defaultQuickEmoji;
  }
}
