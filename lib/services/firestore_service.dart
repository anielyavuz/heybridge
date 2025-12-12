import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'logger_service.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _logger = LoggerService();

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

  Future<UserModel?> getUser(String uid) async {
    try {
      _logger.log('Fetching user document',
        category: 'FIRESTORE',
        data: {'uid': uid}
      );

      final doc = await _firestore.collection('users').doc(uid).get();

      if (doc.exists) {
        _logger.logFirestore('get_user', success: true, collection: 'users');
        _logger.log('User document fetched successfully',
          level: LogLevel.success,
          category: 'FIRESTORE',
          data: {'uid': uid, 'exists': true}
        );
        return UserModel.fromMap(doc.data()!);
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
