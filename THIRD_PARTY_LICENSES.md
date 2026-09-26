# Third-Party Licenses

This project bundles third-party fonts and uses Flutter packages. The project name, logo, icons, artwork, screenshots, store graphics, and other brand assets are covered separately by `TRADEMARK.md`.

## Fonts

### OpenDyslexic

- Included files: `assets/fonts/OpenDyslexic/OpenDyslexic-Regular.otf`, `assets/fonts/OpenDyslexic/OpenDyslexic-Bold.otf`
- License/source: https://opendyslexic.org

### Noto Sans

- Included files: `assets/fonts/Noto_Sans/static/NotoSans-Regular.ttf`, `assets/fonts/Noto_Sans/static/NotoSans-Bold.ttf`
- License: SIL Open Font License Version 1.1
- Local license file: `assets/fonts/Noto_Sans/OFL.txt`

### Courier Prime

- Included files: `assets/fonts/Courier_Prime/CourierPrime-Regular.ttf`, `assets/fonts/Courier_Prime/CourierPrime-Bold.ttf`
- License: SIL Open Font License Version 1.1
- Local license file: `assets/fonts/Courier_Prime/OFL.txt`

### Ubuntu / Ubuntu Mono

- Included files: `assets/fonts/Ubuntu/Ubuntu-Regular.ttf`, `assets/fonts/Ubuntu/Ubuntu-Bold.ttf`, `assets/fonts/Ubuntu/UbuntuMono-Regular.ttf`, `assets/fonts/Ubuntu/UbuntuMono-Bold.ttf`
- License: Ubuntu Font Licence Version 1.0
- Local license file: `assets/fonts/Ubuntu/UFL.txt`

## Flutter and Dart packages

Package dependencies are listed in `pubspec.yaml` and `pubspec.lock`. Consult each package's upstream license for its terms. Primary direct dependencies include Flutter, `cryptography`, `flutter_secure_storage`, `file_picker`, `speech_to_text`, `record`, `audioplayers`, `local_auth`, `llm_llamacpp`, `path`, `path_provider`, and `intl`.

No GGUF model is bundled with the app. Models imported by the user retain their own licenses and are not covered by this file or the app's MIT license.
