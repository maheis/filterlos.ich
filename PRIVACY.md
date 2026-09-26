# Datenschutzerklärung für filterlos.ich

Stand: 26.09.2026

## 1. Verantwortlicher

Verantwortlich für die Verarbeitung personenbezogener Daten im Zusammenhang mit filterlos.ich ist:

- Name/Handle: maheis
- Kontakt: [maheis](mailto:maheis@heister.be)

## 2. Über die App

filterlos.ich ist ein lokales Tagebuch für spontane Gedanken und Emotionen. Einträge können besonders persönliche oder sensible Inhalte enthalten.

## 3. Welche Daten verarbeitet werden

Wenn du die App nutzt, können lokal verarbeitet werden:

- Emotion/Kategorie, Text und Zeitstempel eines Eintrags
- Bilder und Audioaufnahmen, die du selbst hinzufügst
- ein Transkript, wenn du die optionale On-Device-Spracherkennung nutzt
- Timeline-PIN-Prüfwerte, App-Einstellungen und verschlüsselte Journaldaten

Die App speichert die App-PIN nicht im Klartext. Biometrische Daten werden nicht von filterlos.ich erfasst; die Authentifizierung wird an das Betriebssystem übergeben.

## 4. Speicherung und Verschlüsselung

Einträge und Anhänge werden lokal in einer AES-256-GCM-verschlüsselten Datei im App-Support-Verzeichnis gespeichert. Der zufällige Datenschlüssel liegt in der sicheren Speicherfunktion des Betriebssystems: Android Keystore auf Android beziehungsweise Secret Service/Keyring unter Linux.

Der Timeline-PIN-Prüfwert wird mit PBKDF2-HMAC-SHA256 und zufälligem Salt gebildet. Die PIN ist ein zusätzlicher Zugriffsschutz für die Timeline; sie ist nicht der AES-Datenschlüssel.

## 5. Sprach- und Medienfunktionen

- Bilder werden erst nach deiner Auswahl in die App übernommen und dann innerhalb des verschlüsselten Journals gespeichert.
- Audio wird lokal aufgenommen, als verschlüsselter Anhang abgelegt und nicht automatisch geteilt.
- Unter Android fordert die Spracherkennung `onDevice: true` an. Wenn kein Offline-Modell verfügbar ist, wird kein Cloud-Fallback genutzt; du kannst stattdessen tippen oder nur Audio anhängen.
- Unter Linux ist die Speech-to-Text-Funktion derzeit nicht aktiviert.

Die Verfügbarkeit und interne Verarbeitung von Android-Sprachdiensten hängt vom Betriebssystem und den installierten Sprachpaketen ab. Die App fordert ausdrücklich lokale Erkennung an.

## 6. Weitergabe und Cloud

Es gibt kein Backend, keine Cloud-Synchronisierung, keine automatische Serverübertragung und keine Analyse-, Werbe-, Tracking- oder Crash-Reporting-Dienste.

Wenn du außerhalb der App Dateien oder Screenshots teilst, gelten zusätzlich die Datenschutzbestimmungen der jeweiligen Ziel-App oder des jeweiligen Dienstes.

## 7. Timeline-Schutz und Stealth-Modus

Die Timeline wird mit deiner App-PIN gesperrt; auf Android kann zusätzlich Biometrie verwendet werden. Der Stealth-Modus verändert nur die Darstellung. Er verhindert keine Screenshots und schützt nicht vor Zugriff auf ein entsperrtes oder kompromittiertes Betriebssystem.

## 8. Speicherdauer und Löschung

Einträge bleiben lokal gespeichert, bis du sie in der Timeline löschst, die App-Daten entfernst oder die App deinstallierst. Beim Löschen wird der Eintrag aus dem verschlüsselten Journal entfernt. Temporäre Aufnahmedateien werden nach dem Einlesen gelöscht.

## 9. Datensicherheit

Schütze dein Gerät mit Bildschirmsperre und Systemverschlüsselung. Unter Linux muss ein geschützter Secret-Service-Keyring verfügbar sein. Bei Verlust des Betriebssystem-Schlüsselbunds kann der Datenschlüssel nicht aus dem verschlüsselten Journal rekonstruiert werden.

## 10. Deine Rechte

Du hast im Rahmen der geltenden gesetzlichen Vorschriften insbesondere Rechte auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung und Datenübertragbarkeit. Da die Daten lokal auf deinem Gerät gespeichert werden, kannst du sie auch direkt in der App löschen oder durch Entfernen der App-Daten entfernen.

Für Fragen zur Verarbeitung deiner Daten kannst du dich an den oben genannten Verantwortlichen wenden.

## 11. Änderungen

Diese Datenschutzerklärung kann angepasst werden, wenn sich die App oder die Datenverarbeitung ändert. Die aktuelle Fassung ist in diesem Repository unter `PRIVACY.md` verfügbar.
