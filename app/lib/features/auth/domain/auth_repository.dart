class AuthIdentity {
  const AuthIdentity({required this.uid, required this.email});

  final String uid;
  final String? email;
}

abstract interface class AuthRepository {
  Stream<AuthIdentity?> get authStateChanges;
  AuthIdentity? get currentUser;

  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  });
  Future<String?> getIdToken({required bool forceRefresh});
  Future<void> signOut();
}
