import 'package:app/features/attendance/data/install_id_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates a random hex install id once and reuses it', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesInstallIdStore();

    final simultaneous = await Future.wait([
      store.getOrCreate(),
      store.getOrCreate(),
    ]);
    final first = simultaneous.first;
    final second = await store.getOrCreate();

    expect(first, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(simultaneous.last, first);
    expect(second, first);
  });
}
