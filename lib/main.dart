import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'app_controller.dart';
import 'services/encrypted_journal_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');

  final store = EncryptedJournalStore();
  try {
    await store.initialize();
    final controller = AppController(store);
    await controller.load();
    runApp(FilterlosApp(controller: controller));
  } catch (error) {
    runApp(_StartupFailureApp(error: error, store: store));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.store});

  final Object error;
  final EncryptedJournalStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'filterlos.ich',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: _StartupFailureView(error: error, store: store),
      ),
    );
  }
}

class _StartupFailureView extends StatefulWidget {
  const _StartupFailureView({required this.error, required this.store});

  final Object error;
  final EncryptedJournalStore store;

  @override
  State<_StartupFailureView> createState() => _StartupFailureViewState();
}

class _StartupFailureViewState extends State<_StartupFailureView> {
  bool _resetting = false;
  String? _resetError;

  Future<void> _resetLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lokale Daten zurücksetzen?'),
        content: const Text(
          'Die verschlüsselte Journal-Datei und der lokale Schlüssel werden '
          'gelöscht. Dieser Vorgang kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _resetting = true;
      _resetError = null;
    });
    try {
      await widget.store.clearLocalData();
      await main();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resetting = false;
        _resetError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_reset_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Der sichere lokale Speicher konnte nicht geöffnet werden.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Details: ${widget.error}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _resetting ? null : _resetLocalData,
                icon: _resetting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep_outlined),
                label: const Text('Lokale Daten zurücksetzen'),
              ),
              if (_resetError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resetError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
