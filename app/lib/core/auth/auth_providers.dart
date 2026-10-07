import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/app_exception.dart';
import '../../features/auth/data/firebase_auth_repository.dart';
import '../../features/auth/domain/auth_controller.dart';
import '../../features/auth/domain/auth_repository.dart';
import '../../features/auth/domain/profile_api.dart';
import '../../features/auth/domain/user_profile.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => FirebaseAuthRepository(ref.watch(firebaseAuthProvider)),
);

final authStateProvider = StreamProvider<AuthIdentity?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

class AuthMessageController extends Notifier<String?> {
  @override
  String? build() => null;

  void setMessage(String? message) => state = message;
}

final authMessageProvider =
    NotifierProvider<AuthMessageController, String?>(AuthMessageController.new);

final apiClientProvider = Provider<ApiClient>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return ApiClient(
    getIdToken: ({required forceRefresh}) =>
        authRepository.getIdToken(forceRefresh: forceRefresh),
    onUnauthorized: authRepository.signOut,
  );
});

class ProfileLoader {
  final Map<String, Future<UserProfile>> _pendingOrLoaded = {};

  Future<UserProfile> load(
    String uid,
    Future<UserProfile> Function() request,
  ) async {
    final existing = _pendingOrLoaded[uid];
    if (existing != null) return existing;

    final future = request();
    _pendingOrLoaded[uid] = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_pendingOrLoaded[uid], future)) {
        _pendingOrLoaded.remove(uid);
      }
      rethrow;
    }
  }

  void clear() => _pendingOrLoaded.clear();
}

final profileLoaderProvider = Provider<ProfileLoader>((ref) => ProfileLoader());

final currentProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (authState.isLoading) return null;
  if (authState.hasError) {
    Error.throwWithStackTrace(authState.error!, authState.stackTrace!);
  }

  final identity = authState.asData?.value;
  final profileLoader = ref.read(profileLoaderProvider);
  if (identity == null) {
    profileLoader.clear();
    return null;
  }

  try {
    return await profileLoader.load(
      identity.uid,
      () => ref.read(apiClientProvider).getMe(),
    );
  } on AppException catch (error) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      profileLoader.clear();
      ref
          .read(authMessageProvider.notifier)
          .setMessage(
            'This account is disabled or inactive. Contact your administrator.',
          );
      await ref.read(authRepositoryProvider).signOut();
    }
    rethrow;
  }
});

final authControllerProvider = Provider<AuthController>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  final profileApi = ref.watch(apiClientProvider);
  final profileLoader = ref.watch(profileLoaderProvider);
  return AuthController(
    authRepository,
    _CachedProfileApi(
      profileApi: profileApi,
      profileLoader: profileLoader,
      authRepository: authRepository,
    ),
    profileLoader.clear,
    ref.read(authMessageProvider.notifier).setMessage,
  );
});

class _CachedProfileApi implements ProfileApi {
  const _CachedProfileApi({
    required this.profileApi,
    required this.profileLoader,
    required this.authRepository,
  });

  final ProfileApi profileApi;
  final ProfileLoader profileLoader;
  final AuthRepository authRepository;

  @override
  Future<UserProfile> getMe() {
    final identity = authRepository.currentUser;
    if (identity == null) {
      throw StateError('Cannot load a profile without a signed-in user.');
    }
    return profileLoader.load(identity.uid, profileApi.getMe);
  }
}
