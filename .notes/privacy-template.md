# Datenschutz- und Sicherheitsgrenzen

- Kein Backend, kein Cloud-Sync, keine Analytics und keine automatische Datenuebertragung.
- AES-GCM verschluesselt den Journalcontainer; der zufaellige Schluessel wird in OS Secure Storage gehalten.
- Timeline-PIN wird gesalzen mit PBKDF2-HMAC-SHA256 verifiziert und nicht im Klartext gespeichert.
- PIN ist ein UI-Zugriffsschutz, nicht der AES-Datenschluessel.
- Android-Biometrie ist ein optionaler Timeline-Gate-Schritt; Linux verwendet PIN.
- Android Speech-to-Text wird nur mit On-Device-Option angefordert. Wenn die Plattform keinen lokalen Dienst bereitstellt, wird kein Cloud-Fallback verwendet.
- Stealth-Modus ist nur visuell und verhindert keine Screenshots.
- Audio- und Bildanhänge sind Teil des verschluesselten Containers.
- Der Betriebssystem-Schluesselbund muss verfuegbar sein; bei Verlust des Schluessels kann das Journal nicht entschluesselt werden.
