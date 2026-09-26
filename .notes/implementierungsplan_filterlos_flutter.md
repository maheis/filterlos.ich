# Implementierungsplan filterlos.ich

## Ziel

Eine lokale, datenschutzorientierte Flutter-App fuer spontane Gedanken- und Emotionsnotizen. Android ist primaeres Ziel; Linux Desktop dient als zusaetzliche lokale Laufzeit. Es gibt kein Backend und keine Cloud-Synchronisierung.

## README-Anforderungen

- 2x3 Instant-Capture-Grid mit sechs festen Kategorien
- Texteingabe fuer Gedanken und Kommentare
- Bildanhang
- Voice-to-Text mit lokaler Erkennung, soweit das Betriebssystem ein Offline-Sprachmodell bereitstellt
- optionaler Audioanhang
- Stealth-Modus
- Timeline und Kategoriefilter
- Timeline-Zugriff mit App-PIN und optionaler Biometrie
- optionale lokale KI, Daily Recap, RAG und lernendes Gedächtnis

## Sicherheitsmodell Version 1

- Ein zufaelliger AES-256-GCM-Schluessel wird mit `flutter_secure_storage` im nativen OS-Keystore/Keyring gehalten.
- Tagebuchdaten werden als authentifizierter Ciphertext in einer Datei im App-Support-Verzeichnis abgelegt.
- Die Timeline bleibt hinter App-PIN gesperrt; auf Android kann optional zusaetzlich lokale Biometrie verlangt werden.
- Die PIN ist ein UI-Zugriffsschutz und wird gehasht/verifiziert. Sie ist nicht der Verschluesselungsschluessel.
- Biometrie-/Secure-Storage-Unterstuetzung haengt vom OS ab. Linux nutzt PIN-Fallback und Secret Service/Keyring; keine Biometriebehauptung.
- Sprachaufnahme wird lokal gespeichert und als verschluesselter Anhang in den Journal-Datensatz aufgenommen.
- Speech-to-Text wird nur mit `onDevice: true` auf Android versucht. Wenn kein Offline-Modell verfuegbar ist, bleibt der Nutzer bei Text oder Audioanhang.

## Version 1 Funktionen

1. Flutter Android/Linux Scaffold und UI-X-Settings aus dem m.git Template.
2. AES-256-GCM verschluesselter lokaler Journal Store.
3. OS-sicher gespeicherter zufaelliger Datenschluessel.
4. Quick Capture Grid mit sechs Kategorien.
5. Capture-Seite mit Text, Bild, optionaler Audioaufnahme und optionaler On-Device-Transkription.
6. Timeline mit PIN-Gate, optionaler Android-Biometrie und Kategoriefilter.
7. Eintraege loeschen.
8. AMOLED Stealth-Theme sowie Button-Stil/Farboptionen.
9. PIN einrichten/aendern, Biometrieoption und Darstellung in Settings.
10. Tests fuer Crypto Roundtrip, falsche Schluessel, PIN-Verifikation und Kategorie-/Timeline-Logik.

## KI-Umfang

Version 1 integriert eine optionale lokale llama.cpp-Runtime. Der Nutzer importiert ein eigenes GGUF-Modell; die App liefert kein Modell aus und lädt keines automatisch.

Umgesetzt:

- manuelle Companion-Antwort zu einem Eintrag
- manueller Tagesrückblick
- Tagebuchfragen mit lokaler Stichwortauswahl relevanter Einträge
- manuelle Erstellung/Aktualisierung eines nutzerkontrollierten Memory-Profils

Noch offen:

- semantische Retrieval-/Vektor-Embeddings
- automatische Hintergrund-Extraktion von Präferenzen
- Modellkompatibilitäts- und Leistungsprofile je Gerät

Alle KI-Eingaben und Antworten bleiben auf dem Gerät; es gibt keine Cloud-API.

## Architektur

- `lib/main.dart`: Storage/Settings/Controller initialisieren.
- `lib/app.dart`: Theme, Navigation und App-Shell.
- `lib/models.dart`: Emotionen und JournalEntry.
- `lib/services/encrypted_journal_store.dart`: AES-GCM und Secure Storage.
- `lib/app_controller.dart`: Capture, Timeline, Filter, PIN und Settingslogik.
- `lib/pages/home_page.dart`: 2x3 Grid und Schnellzugriff.
- `lib/pages/capture_page.dart`: Text, Bild, Sprache und Audio.
- `lib/pages/timeline_page.dart`: PIN-/Biometrie-Gate und geschuetzte Timeline.
- `lib/pages/settings_page.dart`: PIN, Biometrie, Stealth und UI-X.

## Validierung

- `flutter analyze`
- `flutter test test/widget_test.dart --reporter compact`
- `flutter build linux --debug`
- Android debug build, falls vollstaendiges JDK mit `javac` installiert ist
