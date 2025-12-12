import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Users Collection
  Future<void> createUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(user.toMap());
    } catch (e) {
      throw Exception('Kullanıcı oluşturulamadı: $e');
    }
  }

  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      throw Exception('Kullanıcı getirilemedi: $e');
    }
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
    } catch (e) {
      throw Exception('Kullanıcı güncellenemedi: $e');
    }
  }

  Future<void> updateLastSeen(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Son görülme güncellenemedi: $e');
    }
  }

  Stream<UserModel?> getUserStream(String uid) {
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
      await _firestore.collection('users').doc(uid).update({
        'workspaceIds': FieldValue.arrayUnion([workspaceId]),
      });
    } catch (e) {
      throw Exception('Workspace eklenemedi: $e');
    }
  }

  Future<void> removeUserFromWorkspace(String uid, String workspaceId) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'workspaceIds': FieldValue.arrayRemove([workspaceId]),
      });
    } catch (e) {
      throw Exception('Workspace çıkarılamadı: $e');
    }
  }
}
