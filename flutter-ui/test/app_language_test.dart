import 'package:flutter_test/flutter_test.dart';
import 'package:hyesread_flutter/ui/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persisted language uses a safe Chinese default and restores English',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(HyesLanguagePreference.read(prefs), HyesLanguage.chinese);
    await HyesLanguagePreference.save(prefs, HyesLanguage.english);
    expect(prefs.getString(HyesLanguagePreference.key), 'en');
    expect(HyesLanguagePreference.read(prefs), HyesLanguage.english);
    await HyesLanguagePreference.save(prefs, HyesLanguage.chinese);
    expect(HyesLanguagePreference.read(prefs), HyesLanguage.chinese);
    await prefs.setString(HyesLanguagePreference.key, 'invalid');
    expect(HyesLanguagePreference.read(prefs), HyesLanguage.chinese);
  });

  test('English changes chrome only, not reading content', () {
    const translated = HyesCopy(HyesLanguage.english);
    expect(translated.tr('我的书架'), 'My library');
    expect(translated.tr('语言'), 'Language');
    expect(translated.tr('笔记思考术'), '笔记思考术');
    expect(translated.progress(.19), '19% read');
    expect(translated.chapter(10, total: 52), 'Chapter 10 of 52');
  });
}
