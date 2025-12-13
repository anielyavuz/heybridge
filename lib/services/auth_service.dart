import 'package:firebase_auth/firebase_auth.dart';
import 'logger_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _logger = LoggerService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      _logger.log('Attempting to sign in',
        category: 'AUTH',
        data: {'email': email}
      );

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      _logger.logAuth('sign_in', success: true);
      _logger.log('User signed in successfully',
        level: LogLevel.success,
        category: 'AUTH',
        data: {'email': email, 'uid': credential.user?.uid}
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      _logger.logAuth('sign_in', success: false, error: e.code);
      _logger.log('Sign in failed',
        level: LogLevel.error,
        category: 'AUTH',
        data: {'email': email, 'errorCode': e.code, 'errorMessage': e.message}
      );
      throw _handleAuthException(e);
    }
  }

  Future<UserCredential?> signUpWithEmailAndPassword(
      String email, String password) async {
    try {
      _logger.log('Attempting to sign up',
        category: 'AUTH',
        data: {'email': email}
      );

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      _logger.logAuth('sign_up', success: true);
      _logger.log('User signed up successfully',
        level: LogLevel.success,
        category: 'AUTH',
        data: {'email': email, 'uid': credential.user?.uid}
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      _logger.logAuth('sign_up', success: false, error: e.code);
      _logger.log('Sign up failed',
        level: LogLevel.error,
        category: 'AUTH',
        data: {'email': email, 'errorCode': e.code, 'errorMessage': e.message}
      );
      throw _handleAuthException(e);
    }
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    _logger.log('Attempting to sign out',
      category: 'AUTH',
      data: {'uid': uid}
    );

    await _auth.signOut();

    _logger.logAuth('sign_out', success: true);
    _logger.log('User signed out successfully',
      level: LogLevel.success,
      category: 'AUTH',
      data: {'uid': uid}
    );
  }

  // Re-authenticate user (required for sensitive operations like email/password change)
  Future<UserCredential?> reauthenticate(String email, String password) async {
    try {
      _logger.log('Attempting to reauthenticate',
        category: 'AUTH',
        data: {'email': email}
      );

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      final result = await _auth.currentUser?.reauthenticateWithCredential(credential);

      _logger.logAuth('reauthenticate', success: true);
      _logger.log('User reauthenticated successfully',
        level: LogLevel.success,
        category: 'AUTH',
        data: {'email': email}
      );

      return result;
    } on FirebaseAuthException catch (e) {
      _logger.logAuth('reauthenticate', success: false, error: e.code);
      _logger.log('Reauthentication failed',
        level: LogLevel.error,
        category: 'AUTH',
        data: {'email': email, 'errorCode': e.code, 'errorMessage': e.message}
      );
      throw _handleAuthException(e);
    }
  }

  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Kullanıcı bulunamadı';
      case 'wrong-password':
        return 'Yanlış şifre';
      case 'email-already-in-use':
        return 'Bu e-posta zaten kullanımda';
      case 'weak-password':
        return 'Şifre çok zayıf';
      case 'invalid-email':
        return 'Geçersiz e-posta';
      default:
        return 'Bir hata oluştu: ${e.message}';
    }
  }
}
