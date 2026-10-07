import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class InstallIdStore {
  Future<String> getOrCreate();
}

class SharedPreferencesInstallIdStore implements InstallIdStore {
  const SharedPreferencesInstallIdStore();

  static const _key = 'attendance_install_id';

  @override
  Future<String> getOrCreate() async {
    final preferences = await SharedPreferences.getInstance();
    final existing = preferences.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await preferences.setString(_key, id);
    return id;
  }
}
