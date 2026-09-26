import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_controller.dart';
import 'services/encrypted_journal_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');

  try {
    final store = EncryptedJournalStore();
    await store.initialize();
    final controller = AppController(store);
    await controller.load();
    runApp(FilterlosApp(controller: controller));
  } catch (_) {
    runApp(const _StartupFailureApp());
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'filterlos.ich',
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Der sichere lokale Speicher ist nicht verfügbar. '
              'Bitte entsperre den Geräte-Schlüsselbund und starte die App erneut.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
