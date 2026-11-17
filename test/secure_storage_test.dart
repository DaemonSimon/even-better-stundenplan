import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:better_stundenplan/services/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureCredentialStorage.migrateFromSharedPreferences', () {
    test('übernimmt das Passwort aus dem Tippfehler-Schlüssel', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'sessionId': 'sid',
        'email': 'a@b.de',
        'passowrd': 'geheim',
      });
      final storage = SecureCredentialStorage();

      await storage.migrateFromSharedPreferences();

      expect(await storage.getSessionId(), 'sid');
      expect(await storage.getEmail(), 'a@b.de');
      expect(await storage.getPassword(), 'geheim');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('korrekter Schlüssel gewinnt gegen den Tippfehler', () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({
        'password': 'richtig',
        'passowrd': 'alt',
      });
      final storage = SecureCredentialStorage();

      await storage.migrateFromSharedPreferences();

      expect(await storage.getPassword(), 'richtig');
    });

    test('repariert eine frühere Migration unter dem Tippfehler-Schlüssel',
        () async {
      FlutterSecureStorage.setMockInitialValues({'passowrd': 'geheim'});
      SharedPreferences.setMockInitialValues({});
      final storage = SecureCredentialStorage();

      await storage.migrateFromSharedPreferences();

      expect(await storage.getPassword(), 'geheim');
      expect(
        await const FlutterSecureStorage().read(key: 'passowrd'),
        isNull,
      );
    });
  });
}
