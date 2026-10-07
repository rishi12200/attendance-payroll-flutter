import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_exception.dart';
import '../domain/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._firebaseAuth);

  final FirebaseAuth _firebaseAuth;

  AuthIdentity? _identity(User? user) {
    if (user == null) return null;
    return AuthIdentity(uid: user.uid, email: user.email);
  }

  @override
  Stream<AuthIdentity?> get authStateChanges =>
      _firebaseAuth.authStateChanges().map(_identity);

  @override
  AuthIdentity? get currentUser => _identity(_firebaseAuth.currentUser);

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthException('Sign-in did not return a user account.');
      }
      return AuthIdentity(uid: user.uid, email: user.email);
    } on FirebaseAuthException catch (error) {
      throw AuthException(_messageForCode(error.code));
    }
  }

  @override
  Future<String?> getIdToken({required bool forceRefresh}) async {
    return _firebaseAuth.currentUser?.getIdToken(forceRefresh);
  }

  @override
  Future<void> signOut() => _firebaseAuth.signOut();

  String _messageForCode(String code) => switch (code) {
    'invalid-credential' || 'user-not-found' || 'wrong-password' =>
      'Email or password is incorrect.',
    'user-disabled' => 'This account is disabled. Contact your administrator.',
    'network-request-failed' =>
      'Could not reach Firebase. Check your connection and try again.',
    'too-many-requests' => 'Too many sign-in attempts. Please try again later.',
    _ => 'Unable to sign in. Please try again.',
  };
}
