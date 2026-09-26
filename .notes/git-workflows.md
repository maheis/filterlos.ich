# Git und Release Workflow

Das Projekt ist ein einzelnes Git-Repository. Vor Commit/Release:

```bash
git status --short
flutter analyze
flutter test test/widget_test.dart --reporter compact
flutter build linux --release
```

Android APK/AAB Release benoetigt JDK 17 und signierte Release-Secrets. Secrets, Modell-Dateien und unverschluesselte Tagebuchdaten duerfen nie committet werden.
