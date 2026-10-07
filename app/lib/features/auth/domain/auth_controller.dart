import '../../../core/api/app_exception.dart';
import 'auth_exception.dart';
import 'profile_api.dart';
import 'auth_repository.dart';
import 'user_profile.dart';

class AuthController {
  const AuthController(
    this._authRepository,
    this._profileApi,
    this._clearProfileCache,
    this._updateAuthMessage,
  );

  final AuthRepository _authRepository;
  final ProfileApi _profileApi;
  final void Function() _clearProfileCache;
  final void Function(String? message) _updateAuthMessage;

  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    _updateAuthMessage(null);
    try {
      final identity = await _authRepository.signIn(
        email: email,
        password: password,
      );
      final profile = await _profileApi.getMe();
      if (profile.uid != identity.uid) {
        await signOut();
        throw const AuthException(
          'The signed-in account does not match the server profile.',
        );
      }
      return profile;
    } on AppException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await signOut();
        const message =
            'This account is disabled or inactive. Contact your administrator.';
        _updateAuthMessage(message);
        throw const AuthException(message);
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    _clearProfileCache();
    _updateAuthMessage(null);
    await _authRepository.signOut();
  }
}
