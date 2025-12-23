import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/logger_service.dart';

/// Provider that caches the current user's data to reduce Firestore reads.
/// This eliminates repeated fetches for the same user data during message sends.
class CurrentUserProvider extends ChangeNotifier {
  final LoggerService _logger = LoggerService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  UserModel? _currentUser;
  String? _currentUserId;
  StreamSubscription? _userSubscription;
  bool _isLoading = false;

  // Getters
  UserModel? get currentUser => _currentUser;
  String? get currentUserId => _currentUserId;
  bool get isLoading => _isLoading;
  bool get hasUser => _currentUser != null;

  // Convenience getters for common fields
  String get displayName => _currentUser?.displayName ?? '';
  String? get photoURL => _currentUser?.photoURL;
  String get email => _currentUser?.email ?? '';

  /// Initialize with user ID and start listening to user document
  Future<void> initialize(String userId) async {
    if (_currentUserId == userId && _currentUser != null) {
      _logger.debug('CurrentUserProvider already initialized for $userId', category: 'USER_CACHE');
      return;
    }

    _logger.info('Initializing CurrentUserProvider', category: 'USER_CACHE', data: {'userId': userId});
    _currentUserId = userId;
    _isLoading = true;
    notifyListeners();

    // Cancel previous subscription
    await _userSubscription?.cancel();

    // Start listening to user document
    _userSubscription = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.exists) {
              _currentUser = UserModel.fromMap(snapshot.data()!);
              _isLoading = false;
              _logger.debug('User data updated from stream', category: 'USER_CACHE', data: {
                'displayName': _currentUser?.displayName,
              });
              notifyListeners();
            }
          },
          onError: (e) {
            _logger.error('Error listening to user document: $e', category: 'USER_CACHE');
            _isLoading = false;
            notifyListeners();
          },
        );

    // Also do an initial fetch to ensure we have data immediately
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        _currentUser = UserModel.fromMap(doc.data()!);
        _isLoading = false;
        notifyListeners();
      }
    } catch (e) {
      _logger.error('Error fetching initial user data: $e', category: 'USER_CACHE');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update cached user data locally (and in Firestore)
  Future<void> updateUserData(Map<String, dynamic> updates) async {
    if (_currentUserId == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).update(updates);
      _logger.debug('User data updated', category: 'USER_CACHE', data: updates);
    } catch (e) {
      _logger.error('Error updating user data: $e', category: 'USER_CACHE');
      rethrow;
    }
  }

  /// Clear cached user data on logout
  void clear() {
    _logger.info('Clearing CurrentUserProvider', category: 'USER_CACHE');
    _userSubscription?.cancel();
    _userSubscription = null;
    _currentUser = null;
    _currentUserId = null;
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }
}
