import 'package:app/core/api/app_exception.dart';
import 'package:app/features/auth/domain/auth_controller.dart';
import 'package:app/features/auth/domain/auth_exception.dart';
import 'package:app/features/auth/domain/auth_repository.dart';
import 'package:app/features/auth/domain/profile_api.dart';
import 'package:app/features/auth/domain/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  AuthIdentity? identity;
  bool signedOut = false;
  Object? signInError;

  @override
  Stream<AuthIdentity?> get authStateChanges => Stream.value(identity);

  @override
  AuthIdentity? get currentUser => identity;

  @override
  Future<AuthIdentity> signIn({
    required String email,
    required String password,
  }) async {
    if (signInError case final error?) throw error;
    identity = const AuthIdentity(uid: 'user-1', email: 'test@example.com');
    return identity!;
  }

  @override
  Future<String?> getIdToken({required bool forceRefresh}) async =>
      'fake-token';

  @override
  Future<void> signOut() async {
    signedOut = true;
    identity = null;
  }
}

class FakeProfileApi implements ProfileApi {
  FakeProfileApi(this.response);

  final Future<UserProfile> Function() response;
  int requestCount = 0;

  @override
  Future<UserProfile> getMe() {
    requestCount++;
    return response();
  }
}

UserProfile profile(String uid) => UserProfile(
  uid: uid,
  name: 'Test User',
  email: 'test@example.com',
  role: UserRole.employee,
);

void main() {
  test('signs in then uses the server profile role', () async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileApi(() async => profile('user-1'));
    var cacheCleared = false;
    final controller = AuthController(
      auth,
      profiles,
      () => cacheCleared = true,
      (_) {},
    );

    final result = await controller.signIn(
      email: 'test@example.com',
      password: 'password',
    );

    expect(result.role, UserRole.employee);
    expect(profiles.requestCount, 1);
    expect(auth.signedOut, isFalse);
    expect(cacheCleared, isFalse);
  });

  test('preserves friendly Firebase credential errors', () async {
    final auth = FakeAuthRepository()
      ..signInError = const AuthException('Email or password is incorrect.');
    final controller = AuthController(
      auth,
      FakeProfileApi(() async => profile('user-1')),
      () {},
      (_) {},
    );

    await expectLater(
      controller.signIn(email: 'test@example.com', password: 'wrong'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          'Email or password is incorrect.',
        ),
      ),
    );
    expect(auth.signedOut, isFalse);
  });

  test('signs out when the backend rejects an inactive account', () async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileApi(
      () async => throw const AppException(
        code: 'ACCOUNT_INACTIVE',
        message: 'Inactive',
        details: {},
        statusCode: 403,
      ),
    );
    var cacheCleared = false;
    final controller = AuthController(
      auth,
      profiles,
      () => cacheCleared = true,
      (_) {},
    );

    await expectLater(
      controller.signIn(email: 'test@example.com', password: 'password'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.message,
          'message',
          contains('disabled or inactive'),
        ),
      ),
    );
    expect(auth.signedOut, isTrue);
    expect(cacheCleared, isTrue);
  });

  test('reports a clear message when the backend rejects the profile', () async {
    final auth = FakeAuthRepository();
    final profiles = FakeProfileApi(
      () async => throw const AppException(
        code: 'INVALID_TOKEN',
        message: 'Invalid',
        details: {},
        statusCode: 401,
      ),
    );
    String? message;
    final controller = AuthController(
      auth,
      profiles,
      () {},
      (value) => message = value,
    );

    await expectLater(
      controller.signIn(email: 'test@example.com', password: 'password'),
      throwsA(isA<AuthException>()),
    );
    expect(message, contains('disabled or inactive'));
  });

  test(
    'signs out if the server profile uid does not match the session',
    () async {
      final auth = FakeAuthRepository();
      final controller = AuthController(
        auth,
        FakeProfileApi(() async => profile('other-user')),
        () {},
        (_) {},
      );

      await expectLater(
        controller.signIn(email: 'test@example.com', password: 'password'),
        throwsA(isA<AuthException>()),
      );
      expect(auth.signedOut, isTrue);
    },
  );
}
