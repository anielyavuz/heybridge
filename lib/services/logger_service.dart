import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error,
  success,
}

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  final List<Map<String, dynamic>> _logs = [];
  static const int _maxLogs = 1000;
  static const String _logFileName = 'heybridge_logs.json';

  // Log a message
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? category,
    Map<String, dynamic>? data,
    String? phase,
    String? feature,
  }) {
    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'level': level.name,
      'message': message,
      if (category != null) 'category': category,
      if (phase != null) 'phase': phase,
      if (feature != null) 'feature': feature,
      if (data != null) 'data': data,
    };

    _logs.add(logEntry);

    // Keep only last N logs in memory
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // Print to console in debug mode
    if (kDebugMode) {
      _printLog(logEntry);
    }

    // Save to file periodically
    _saveToFile();
  }

  // Convenience methods for different log levels
  void debug(String message, {String? category, Map<String, dynamic>? data}) {
    log(message, level: LogLevel.debug, category: category, data: data);
  }

  void info(String message, {String? category, Map<String, dynamic>? data}) {
    log(message, level: LogLevel.info, category: category, data: data);
  }

  void warning(String message, {String? category, Map<String, dynamic>? data}) {
    log(message, level: LogLevel.warning, category: category, data: data);
  }

  void error(String message, {String? category, Map<String, dynamic>? data}) {
    log(message, level: LogLevel.error, category: category, data: data);
  }

  void success(String message, {String? category, Map<String, dynamic>? data}) {
    log(message, level: LogLevel.success, category: category, data: data);
  }

  // Phase-specific logging
  void logPhase(String phase, String message, {bool isComplete = false}) {
    log(
      message,
      level: isComplete ? LogLevel.success : LogLevel.info,
      category: 'PHASE',
      phase: phase,
    );
  }

  // Feature-specific logging
  void logFeature(String feature, String message, {String? phase, Map<String, dynamic>? data}) {
    log(
      message,
      level: LogLevel.info,
      category: 'FEATURE',
      phase: phase,
      feature: feature,
      data: data,
    );
  }

  // Auth logging
  void logAuth(String action, {bool success = true, String? error}) {
    log(
      success ? 'Auth: $action succeeded' : 'Auth: $action failed',
      level: success ? LogLevel.success : LogLevel.error,
      category: 'AUTH',
      data: {'action': action, if (error != null) 'error': error},
    );
  }

  // Firestore logging
  void logFirestore(String operation, {bool success = true, String? collection, String? error}) {
    log(
      success ? 'Firestore: $operation succeeded' : 'Firestore: $operation failed',
      level: success ? LogLevel.success : LogLevel.error,
      category: 'FIRESTORE',
      data: {
        'operation': operation,
        if (collection != null) 'collection': collection,
        if (error != null) 'error': error,
      },
    );
  }

  // UI logging
  void logUI(String screen, String action, {Map<String, dynamic>? data}) {
    log(
      'UI: $screen - $action',
      level: LogLevel.info,
      category: 'UI',
      data: {'screen': screen, 'action': action, ...?data},
    );
  }

  // Navigation logging
  void logNavigation(String from, String to) {
    log(
      'Navigation: $from → $to',
      level: LogLevel.info,
      category: 'NAVIGATION',
      data: {'from': from, 'to': to},
    );
  }

  // Get logs
  List<Map<String, dynamic>> getLogs({
    LogLevel? level,
    String? category,
    String? phase,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    var filteredLogs = _logs;

    if (level != null) {
      filteredLogs = filteredLogs.where((log) => log['level'] == level.name).toList();
    }

    if (category != null) {
      filteredLogs = filteredLogs.where((log) => log['category'] == category).toList();
    }

    if (phase != null) {
      filteredLogs = filteredLogs.where((log) => log['phase'] == phase).toList();
    }

    if (startTime != null || endTime != null) {
      filteredLogs = filteredLogs.where((log) {
        final timestamp = DateTime.parse(log['timestamp']);
        if (startTime != null && timestamp.isBefore(startTime)) return false;
        if (endTime != null && timestamp.isAfter(endTime)) return false;
        return true;
      }).toList();
    }

    return filteredLogs;
  }

  // Get logs as JSON string
  String getLogsAsJson({
    LogLevel? level,
    String? category,
    String? phase,
  }) {
    final logs = getLogs(level: level, category: category, phase: phase);
    return const JsonEncoder.withIndent('  ').convert(logs);
  }

  // Save logs to file
  Future<void> _saveToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');
      final jsonString = const JsonEncoder.withIndent('  ').convert(_logs);
      await file.writeAsString(jsonString);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving logs to file: $e');
      }
    }
  }

  // Load logs from file
  Future<void> loadLogsFromFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_logFileName');

      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final List<dynamic> logs = jsonDecode(jsonString);
        _logs.clear();
        _logs.addAll(logs.cast<Map<String, dynamic>>());
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading logs from file: $e');
      }
    }
  }

  // Export logs to a specific file
  Future<String?> exportLogs({String? fileName}) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final exportFileName = fileName ?? 'heybridge_logs_export_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$exportFileName');
      final jsonString = const JsonEncoder.withIndent('  ').convert(_logs);
      await file.writeAsString(jsonString);
      return file.path;
    } catch (e) {
      if (kDebugMode) {
        print('Error exporting logs: $e');
      }
      return null;
    }
  }

  // Clear all logs
  void clearLogs() {
    _logs.clear();
    _saveToFile();
  }

  // Print formatted log to console
  void _printLog(Map<String, dynamic> logEntry) {
    final level = logEntry['level'];
    final message = logEntry['message'];
    final timestamp = logEntry['timestamp'];

    String emoji;
    switch (level) {
      case 'debug':
        emoji = '🔍';
        break;
      case 'info':
        emoji = 'ℹ️';
        break;
      case 'warning':
        emoji = '⚠️';
        break;
      case 'error':
        emoji = '❌';
        break;
      case 'success':
        emoji = '✅';
        break;
      default:
        emoji = '📝';
    }

    print('$emoji [$level] $timestamp - $message');
    if (logEntry.containsKey('data')) {
      print('   Data: ${logEntry['data']}');
    }
  }

  // Get statistics
  Map<String, dynamic> getStatistics() {
    final stats = {
      'total_logs': _logs.length,
      'by_level': <String, int>{},
      'by_category': <String, int>{},
      'by_phase': <String, int>{},
      'first_log': _logs.isNotEmpty ? _logs.first['timestamp'] : null,
      'last_log': _logs.isNotEmpty ? _logs.last['timestamp'] : null,
    };

    for (var log in _logs) {
      // Count by level
      final level = log['level'] as String;
      stats['by_level'][level] = (stats['by_level'][level] ?? 0) + 1;

      // Count by category
      if (log.containsKey('category')) {
        final category = log['category'] as String;
        stats['by_category'][category] = (stats['by_category'][category] ?? 0) + 1;
      }

      // Count by phase
      if (log.containsKey('phase')) {
        final phase = log['phase'] as String;
        stats['by_phase'][phase] = (stats['by_phase'][phase] ?? 0) + 1;
      }
    }

    return stats;
  }
}
