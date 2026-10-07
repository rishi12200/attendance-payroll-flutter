import 'user_profile.dart';

abstract interface class ProfileApi {
  Future<UserProfile> getMe();
}
