import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'logger_service.dart';

/// Cached user data with timestamp
class _CachedUser {
  final UserModel user;
  final DateTime cachedAt;

  _CachedUser(this.user) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > const Duration(minutes: 5);
}

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = LoggerService();

  // User cache to reduce Firestore reads
  static final Map<String, _CachedUser> _userCache = {};

  // Expose firestore instance for direct access when needed
  FirebaseFirestore get firestore => _firestore;

  // Users Collection
  Future<void> createUser(UserModel user) async {
    try {
      _logger.log('Creating user document',
        category: 'FIRESTORE',
        data: {'uid': user.uid, 'email': user.email}
      );

      await _firestore.collection('users').doc(user.uid).set(user.toMap());

      _logger.logFirestore('create_user', success: true, collection: 'users');
      _logger.log('User document created successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'uid': user.uid, 'email': user.email}
      );
    } catch (e) {
      _logger.logFirestore('create_user', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to create user document',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': user.uid, 'error': e.toString()}
      );
      throw Exception('Kullanıcı oluşturulamadı: $e');
    }
  }

  Future<UserModel?> getUser(String uid, {bool useCache = true}) async {
    // Check cache first
    if (useCache && _userCache.containsKey(uid)) {
      final cached = _userCache[uid]!;
      if (!cached.isExpired) {
        _logger.debug('User fetched from cache', category: 'FIRESTORE', data: {'uid': uid});
        return cached.user;
      } else {
        _userCache.remove(uid);
      }
    }

    try {
      _logger.log('Fetching user document',
        category: 'FIRESTORE',
        data: {'uid': uid}
      );

      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        final user = UserModel.fromMap(doc.data()!);
        // Cache the user
        _userCache[uid] = _CachedUser(user);

        _logger.logFirestore('get_user', success: true, collection: 'users');
        _logger.log('User document fetched successfully',
          level: LogLevel.success,
          category: 'FIRESTORE',
          data: {'uid': uid, 'exists': true}
        );
        return user;
      }

      _logger.log('User document does not exist',
        level: LogLevel.warning,
        category: 'FIRESTORE',
        data: {'uid': uid, 'exists': false}
      );
      return null;
    } catch (e) {
      _logger.logFirestore('get_user', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to fetch user document',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'error': e.toString()}
      );
      throw Exception('Kullanıcı getirilemedi: $e');
    }
  }

  /// Batch fetch multiple users at once (reduces N reads to 1 query for cached + N-cached)
  /// Returns a map of userId -> UserModel
  Future<Map<String, UserModel>> getUsers(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    final result = <String, UserModel>{};
    final uncachedIds = <String>[];

    // Check cache first
    for (final uid in userIds) {
      if (_userCache.containsKey(uid)) {
        final cached = _userCache[uid]!;
        if (!cached.isExpired) {
          result[uid] = cached.user;
        } else {
          _userCache.remove(uid);
          uncachedIds.add(uid);
        }
      } else {
        uncachedIds.add(uid);
      }
    }

    if (uncachedIds.isEmpty) {
      _logger.debug('All users fetched from cache', category: 'FIRESTORE', data: {'count': result.length});
      return result;
    }

    // Firestore 'in' query supports max 10 items, so batch if needed
    try {
      for (var i = 0; i < uncachedIds.length; i += 10) {
        final batch = uncachedIds.skip(i).take(10).toList();
        final snapshot = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in snapshot.docs) {
          final user = UserModel.fromMap(doc.data());
          result[doc.id] = user;
          _userCache[doc.id] = _CachedUser(user);
        }
      }

      _logger.debug('Batch user fetch completed', category: 'FIRESTORE', data: {
        'cachedCount': userIds.length - uncachedIds.length,
        'fetchedCount': uncachedIds.length,
      });

      return result;
    } catch (e) {
      _logger.error('Failed to batch fetch users: $e', category: 'FIRESTORE');
      throw Exception('Kullanıcılar getirilemedi: $e');
    }
  }

  /// Clear user cache (call on logout)
  void clearUserCache() {
    _userCache.clear();
    _logger.debug('User cache cleared', category: 'FIRESTORE');
  }

  /// Update cache when user data changes
  void updateUserCache(String uid, UserModel user) {
    _userCache[uid] = _CachedUser(user);
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      _logger.log('Updating user document',
        category: 'FIRESTORE',
        data: {'uid': uid, 'fields': data.keys.toList()}
      );

      await _firestore.collection('users').doc(uid).update(data);

      _logger.logFirestore('update_user', success: true, collection: 'users');
      _logger.log('User document updated successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'uid': uid, 'updatedFields': data.keys.toList()}
      );
    } catch (e) {
      _logger.logFirestore('update_user', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to update user document',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'error': e.toString()}
      );
      throw Exception('Kullanıcı güncellenemedi: $e');
    }
  }

  Future<void> updateLastSeen(String uid) async {
    try {
      _logger.log('Updating user last seen',
        category: 'FIRESTORE',
        data: {'uid': uid}
      );

      await _firestore.collection('users').doc(uid).update({
        'lastSeen': DateTime.now().toIso8601String(),
      });

      _logger.logFirestore('update_last_seen', success: true, collection: 'users');
    } catch (e) {
      _logger.logFirestore('update_last_seen', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to update last seen',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'error': e.toString()}
      );
      throw Exception('Son görülme güncellenemedi: $e');
    }
  }

  // Update user presence (online status and last seen)
  Future<void> updatePresence(String uid, bool isOnline) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      _logger.logFirestore('update_presence', success: true, collection: 'users');
    } catch (e) {
      _logger.logFirestore('update_presence', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to update presence',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'error': e.toString()}
      );
    }
  }

  Stream<UserModel?> getUserStream(String uid) {
    _logger.log('Starting user stream',
      category: 'FIRESTORE',
      data: {'uid': uid}
    );

    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    });
  }

  // Workspace Methods
  Future<void> addUserToWorkspace(String uid, String workspaceId) async {
    try {
      _logger.log('Adding user to workspace',
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId}
      );

      await _firestore.collection('users').doc(uid).update({
        'workspaceIds': FieldValue.arrayUnion([workspaceId]),
      });

      _logger.logFirestore('add_user_to_workspace', success: true, collection: 'users');
      _logger.log('User added to workspace successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId}
      );
    } catch (e) {
      _logger.logFirestore('add_user_to_workspace', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to add user to workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId, 'error': e.toString()}
      );
      throw Exception('Workspace eklenemedi: $e');
    }
  }

  Future<void> removeUserFromWorkspace(String uid, String workspaceId) async {
    try {
      _logger.log('Removing user from workspace',
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId}
      );

      await _firestore.collection('users').doc(uid).update({
        'workspaceIds': FieldValue.arrayRemove([workspaceId]),
      });

      _logger.logFirestore('remove_user_from_workspace', success: true, collection: 'users');
      _logger.log('User removed from workspace successfully',
        level: LogLevel.success,
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId}
      );
    } catch (e) {
      _logger.logFirestore('remove_user_from_workspace', success: false, collection: 'users', error: e.toString());
      _logger.log('Failed to remove user from workspace',
        level: LogLevel.error,
        category: 'FIRESTORE',
        data: {'uid': uid, 'workspaceId': workspaceId, 'error': e.toString()}
      );
      throw Exception('Workspace çıkarılamadı: $e');
    }
  }
}
