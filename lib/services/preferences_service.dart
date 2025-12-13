import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _lastWorkspaceIdKey = 'last_workspace_id';

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
}
