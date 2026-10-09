import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_controller.dart';
import '../services/daily_text_export_service.dart';
import '../services/local_model_download_service.dart';
import '../ui_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late FilterlosSettings _draft = widget.controller.settings;
  final _memoryController = TextEditingController();
  final _modelDownloadService = LocalModelDownloadService();
  bool _copyingModel = false;
  bool _updatingMemory = false;
  bool _memoryUnlocked = false;
  String? _downloadingModelId;
  int _downloadedModelBytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _memoryUnlocked) {
      setState(() {
        _memoryUnlocked = false;
        _memoryController.clear();
      });
    }
  }

  String get _memoryValue => _memoryUnlocked
      ? _memoryController.text.trim()
      : _draft.userMemorySummary;

  Future<void> _saveSettings() async {
    _draft = _draft.copyWith(userMemorySummary: _memoryValue);
    await widget.controller.updateSettings(_draft);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Einstellungen gespeichert.')));
  }

  Future<void> _exportBackup() async {
    final password = await _askMasterPassword(confirm: true);
    if (password == null) return;
    try {
      final backup = await widget.controller.createPasswordBackup(password);
      final path = await FilePicker.saveFile(
        dialogTitle: 'Verschlüsseltes Backup speichern',
        fileName: 'filterlos-ich-backup.json',
        bytes: Uint8List.fromList(utf8.encode(backup)),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null) return;
      _showMessage('Passwort-Backup gespeichert.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Invalid argument(s): ', ''));
    }
  }

  Future<String?> _askTimelinePinForExport() async {
    final pinController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tagesexport schützen'),
          content: TextField(
            key: const ValueKey('daily-export-pin-input'),
            controller: pinController,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'App-PIN'),
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(pinController.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const ValueKey('confirm-daily-export-pin'),
              onPressed: () =>
                  Navigator.of(dialogContext).pop(pinController.text),
              child: const Text('Exportieren'),
            ),
          ],
        ),
      );
    } finally {
      pinController.dispose();
    }
  }

  Future<void> _exportDailyTextZip() async {
    if (!widget.controller.hasTimelinePin) {
      _showMessage('Richte zuerst in den Einstellungen eine App-PIN ein.');
      return;
    }
    if (widget.controller.entries.isEmpty) {
      _showMessage('Das Tagebuch enthält noch keine Einträge.');
      return;
    }

    final availableDays =
        widget.controller.entries
            .map((entry) {
              final date = entry.createdAt.toLocal();
              return DateTime(date.year, date.month, date.day);
            })
            .toSet()
            .toList()
          ..sort();
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: availableDays.first,
      lastDate: availableDays.last,
      initialDateRange: DateTimeRange(
        start: availableDays.first,
        end: availableDays.last,
      ),
      helpText: 'Exportzeitraum auswählen',
      saveText: 'Zeitraum verwenden',
    );
    if (selectedRange == null) return;

    final pin = await _askTimelinePinForExport();
    if (pin == null) return;
    if (!await widget.controller.verifyTimelinePinForExport(pin)) {
      _showMessage('Die App-PIN stimmt nicht oder ist vorübergehend gesperrt.');
      return;
    }

    try {
      final bytes = DailyTextExportService().createEncryptedZip(
        widget.controller.entries,
        pin,
        startDate: selectedRange.start,
        endDate: selectedRange.end,
      );
      final start = _exportDateLabel(selectedRange.start);
      final end = _exportDateLabel(selectedRange.end);
      final path = await FilePicker.saveFile(
        dialogTitle: 'PIN-geschütztes Tagebuch-ZIP speichern',
        fileName: 'filterlos-ich-export-$start-$end.zip',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (path != null) _showMessage('Tagesexport gespeichert.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Invalid argument(s): ', ''));
    }
  }

  String _exportDateLabel(DateTime value) =>
      '${(value.year % 100).toString().padLeft(2, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _importBackup() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup wiederherstellen?'),
        content: const Text(
          'Der aktuelle lokale Store wird durch den Inhalt des Backups ersetzt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fortfahren'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (files.isEmpty) return;
    final selected = files.single;
    final backupBytes = <int>[];
    await for (final chunk in selected.readAsByteStream()) {
      backupBytes.addAll(chunk);
    }
    final backup = utf8.decode(backupBytes);
    final password = await _askMasterPassword();
    if (password == null) return;
    try {
      await widget.controller.restorePasswordBackup(backup, password);
      if (!mounted) return;
      _draft = widget.controller.settings;
      if (_memoryUnlocked) _memoryController.text = _draft.userMemorySummary;
      _showMessage('Backup wiederhergestellt.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<String?> _askMasterPassword({bool confirm = false}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _MasterPasswordDialog(confirm: confirm),
    );
  }

  Future<void> _managePin() async {
    final result = await showDialog<_PinChange>(
      context: context,
      builder: (_) => _PinDialog(hasPin: widget.controller.hasTimelinePin),
    );
    if (result == null) return;

    try {
      if (widget.controller.hasTimelinePin) {
        final updated = await widget.controller.changePin(
          result.currentPin,
          result.newPin,
        );
        if (!updated) {
          _showMessage('Die aktuelle PIN stimmt nicht.');
          return;
        }
      } else {
        await widget.controller.configurePin(result.newPin);
      }
      _showMessage('Timeline-PIN gespeichert.');
      setState(() {});
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? 'Die PIN ist ungültig.');
    } catch (_) {
      _showMessage('Die PIN konnte nicht gespeichert werden.');
    }
  }

  Future<String?> _askAppPin({
    required String title,
    required String inputKey,
    required String confirmKey,
    required String confirmLabel,
  }) {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: ValueKey(inputKey),
          controller: pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'App-PIN'),
          onSubmitted: (_) =>
              Navigator.of(dialogContext).pop(pinController.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: ValueKey(confirmKey),
            onPressed: () =>
                Navigator.of(dialogContext).pop(pinController.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).whenComplete(pinController.dispose);
  }

  Future<void> _unlockMemory() async {
    if (!widget.controller.hasTimelinePin) {
      await _managePin();
      if (!mounted || !widget.controller.hasTimelinePin) return;
      _memoryController.text = widget.controller.settings.userMemorySummary;
      setState(() => _memoryUnlocked = true);
      return;
    }

    final pin = await _askAppPin(
      title: 'Vorlieben entsperren',
      inputKey: 'memory-pin-input',
      confirmKey: 'confirm-memory-pin',
      confirmLabel: 'Entsperren',
    );
    if (pin == null || !mounted) return;
    if (!await widget.controller.verifyTimelinePinForExport(pin)) {
      _showMessage('Die App-PIN stimmt nicht oder ist vorübergehend gesperrt.');
      return;
    }
    _memoryController.text = widget.controller.settings.userMemorySummary;
    setState(() => _memoryUnlocked = true);
  }

  Future<void> _chooseModel() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lokales Modell auswählen'),
        content: const Text(
          'Wähle eine GGUF-Datei, die du verwenden darfst. Sie wird in den '
          'privaten App-Ordner kopiert, dort aber nicht als Tagebuchinhalt '
          'verschlüsselt. Die Inferenz läuft lokal und lädt nichts aus dem Netz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Datei wählen'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['gguf'],
      );
      if (files.isEmpty) return;
      final selected = files.single;
      final size = await selected.length();
      if (size != null && size > 4 * 1024 * 1024 * 1024) {
        _showMessage('Modelle über 4 GB werden nicht importiert.');
        return;
      }

      setState(() => _copyingModel = true);
      final support = await getApplicationSupportDirectory();
      final modelDirectory = Directory(
        p.join(support.path, 'filterlos.ich', 'models'),
      );
      await modelDirectory.create(recursive: true);
      final safeName = p
          .basename(selected.name)
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final target = File(p.join(modelDirectory.path, safeName));
      final sink = target.openWrite();
      try {
        await for (final chunk in selected.readAsByteStream()) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final next = _draft.copyWith(
        localModelPath: target.path,
        userMemorySummary: _memoryValue,
      );
      await widget.controller.updateSettings(next);
      if (!mounted) return;
      setState(() => _draft = next);
      _showMessage(
        'Modell lokal importiert. Beim ersten Aufruf wird es geladen.',
      );
    } catch (_) {
      _showMessage('Das GGUF-Modell konnte nicht importiert werden.');
    } finally {
      if (mounted) setState(() => _copyingModel = false);
    }
  }

  Future<void> _downloadModel(
    LocalModelCatalogEntry model, {
    bool asEmbeddingModel = false,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lokales Modell herunterladen?'),
        content: Text(
          '${model.name}\n'
          'Download: ${formatModelSize(model.sizeBytes)}\n'
          'Lizenz: ${model.licenseLabel}\n\n'
          'Die Datei wird von Hugging Face geladen und im privaten App-Ordner '
          'gespeichert. Dafür wird zusätzlicher Gerätespeicher benötigt. '
          'Tagebucheinträge werden nicht übertragen. Das Modell selbst ist '
          'nicht verschlüsselt. Lizenzquelle:\n${model.licenseUrl}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Herunterladen'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() {
      _downloadingModelId = model.id;
      _downloadedModelBytes = 0;
    });
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        p.join(support.path, 'filterlos.ich', 'models'),
      );
      final file = await _modelDownloadService.download(
        model,
        directory: directory,
        onProgress: (receivedBytes) {
          if (mounted) setState(() => _downloadedModelBytes = receivedBytes);
        },
      );
      if (!mounted) return;
      final next = asEmbeddingModel
          ? _draft.copyWith(
              embeddingModelPath: file.path,
              userMemorySummary: _memoryValue,
            )
          : _draft.copyWith(
              localModelPath: file.path,
              userMemorySummary: _memoryValue,
            );
      await widget.controller.updateSettings(next);
      if (!mounted) return;
      setState(() => _draft = next);
      _showMessage('Modell geprüft und lokal aktiviert.');
    } on LocalModelDownloadCancelled {
      if (mounted) _showMessage('Modelldownload abgebrochen.');
    } on LocalModelDownloadException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Das Modell konnte nicht geladen werden.');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingModelId = null;
          _downloadedModelBytes = 0;
        });
      }
    }
  }

  void _cancelModelDownload() {
    _modelDownloadService.cancel();
  }

  Future<void> _removeModel() async {
    final modelPath = _draft.localModelPath;
    if (modelPath.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Modell entfernen?'),
        content: const Text('Die lokale GGUF-Datei wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      final file = File(modelPath);
      if (await file.exists()) await file.delete();
      final next = _draft.copyWith(localModelPath: '');
      await widget.controller.updateSettings(next);
      if (mounted) setState(() => _draft = next);
    } catch (_) {
      _showMessage('Das Modell konnte nicht entfernt werden.');
    }
  }

  Future<void> _removeEmbeddingModel() async {
    final modelPath = _draft.embeddingModelPath;
    if (modelPath.isEmpty) return;
    try {
      final file = File(modelPath);
      if (await file.exists()) await file.delete();
      final next = _draft.copyWith(embeddingModelPath: '');
      await widget.controller.updateSettings(next);
      if (mounted) setState(() => _draft = next);
    } catch (_) {
      _showMessage('Das Suchmodell konnte nicht entfernt werden.');
    }
  }

  Future<void> _refreshMemory() async {
    setState(() => _updatingMemory = true);
    try {
      final current = _draft.copyWith(userMemorySummary: _memoryValue);
      await widget.controller.updateSettings(current);
      await widget.controller.refreshLocalMemory();
      if (!mounted) return;
      _draft = widget.controller.settings;
      if (_memoryUnlocked) _memoryController.text = _draft.userMemorySummary;
      _showMessage('Lokales Gedächtnis aktualisiert.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _updatingMemory = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = _draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        actions: [
          TextButton(onPressed: _saveSettings, child: const Text('Speichern')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Darstellung', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: settings.fontFamily,
            decoration: const InputDecoration(
              labelText: 'Schriftart',
              border: OutlineInputBorder(),
            ),
            items: FilterlosSettings.availableFonts
                .map((font) => DropdownMenuItem(value: font, child: Text(font)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _draft = settings.copyWith(fontFamily: value));
              }
            },
          ),
          const SizedBox(height: 16),
          Text('Schriftgröße: ${(settings.textScaleFactor * 100).round()} %'),
          Slider(
            value: settings.textScaleFactor,
            min: 0.5,
            max: 1.6,
            divisions: 22,
            label: '${(settings.textScaleFactor * 100).round()} %',
            onChanged: (value) => setState(
              () => _draft = settings.copyWith(textScaleFactor: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Helles Design'),
            value: settings.useLightTheme,
            onChanged: (value) => setState(
              () => _draft = settings.copyWith(useLightTheme: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stealth-Modus'),
            subtitle: const Text(
              'Schwarzer Hintergrund und reduzierte Helligkeit.',
            ),
            value: settings.stealthMode,
            onChanged: (value) =>
                setState(() => _draft = settings.copyWith(stealthMode: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Emoji-Tasten'),
            subtitle: const Text(
              'Kategorien als Emoji statt Farbfelder hervorheben.',
            ),
            value: settings.emojiButtons,
            onChanged: (value) =>
                setState(() => _draft = settings.copyWith(emojiButtons: value)),
          ),
          const SizedBox(height: 8),
          _ColorDropdown(
            label: 'Akzentfarbe',
            value: settings.accentColorValue,
            stealth: settings.stealthMode,
            onChanged: (value) => setState(
              () => _draft = settings.copyWith(accentColorValue: value),
            ),
          ),
          const SizedBox(height: 12),
          _ColorDropdown(
            label: 'Highlight-Farbe',
            value: settings.highlightColorValue,
            stealth: settings.stealthMode,
            onChanged: (value) => setState(
              () => _draft = settings.copyWith(highlightColorValue: value),
            ),
          ),
          const Divider(height: 36),
          Text('Lokale KI', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Modelle werden nur auf ausdrücklichen Wunsch geladen. Die '
            'Tagebuchdaten verlassen das Gerät nicht.',
          ),
          const SizedBox(height: 8),
          if (settings.localModelPath.isEmpty)
            const Text('Kein lokales GGUF-Modell ausgewählt.')
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_outlined),
              title: Text(p.basename(settings.localModelPath)),
              subtitle: const Text('Lokal gespeichert · llama.cpp'),
              trailing: IconButton(
                tooltip: 'Modell entfernen',
                onPressed: _removeModel,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          for (final model in LocalModelCatalogEntry.officialModels)
            _modelDownloadOption(model, settings),
          OutlinedButton.icon(
            onPressed: _copyingModel || _downloadingModelId != null
                ? null
                : _chooseModel,
            icon: _copyingModel
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined),
            label: Text(
              _copyingModel ? 'Kopiere Modell…' : 'GGUF-Modell importieren',
            ),
          ),
          const SizedBox(height: 20),
          Text('Tagebuchsuche', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Mit diesem kleinen Zusatzmodell findet fi passende Einträge auch '
            'dann, wenn du andere Wörter benutzt als im Eintrag. Ohne das '
            'Modell wird nach Stichwörtern gesucht.',
          ),
          if (settings.embeddingModelPath.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.travel_explore_outlined),
              title: Text(p.basename(settings.embeddingModelPath)),
              subtitle: const Text('Aktiv für die Tagebuchsuche'),
              trailing: IconButton(
                tooltip: 'Suchmodell entfernen',
                onPressed: _removeEmbeddingModel,
                icon: const Icon(Icons.delete_outline),
              ),
            )
          else
            _modelDownloadOption(
              LocalModelCatalogEntry.embeddingModel,
              settings,
              asEmbeddingModel: true,
            ),
          const SizedBox(height: 16),
          if (_memoryUnlocked) ...[
            TextField(
              key: const ValueKey('user-memory-summary-input'),
              controller: _memoryController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Was fi über deine Vorlieben wissen soll',
                hintText: 'Nur lokal gespeichert. Du kannst den Text ansehen, ändern oder löschen.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: settings.localModelPath.isEmpty || _updatingMemory
                  ? null
                  : _refreshMemory,
              icon: _updatingMemory
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _updatingMemory
                    ? 'Aktualisiere lokal…'
                    : 'Memory aus letzten Einträgen aktualisieren',
              ),
            ),
          ] else
            OutlinedButton.icon(
              key: const ValueKey('unlock-user-memory-button'),
              onPressed: _unlockMemory,
              icon: Icon(
                widget.controller.hasTimelinePin
                    ? Icons.lock_open_outlined
                    : Icons.pin_outlined,
              ),
              label: Text(
                widget.controller.hasTimelinePin
                    ? 'Vorlieben mit App-PIN entsperren'
                    : 'App-PIN einrichten, um Vorlieben zu schützen',
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Quelle: Qwen-Team auf Hugging Face. Die angebotenen Gewichte '
            'stehen unter Apache 2.0. Modelle werden nicht mit der App '
            'gebündelt; ein Download benötigt eine Internetverbindung.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text(
            'Datensicherung',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Backups werden mit einem Masterpasswort verschlüsselt. Das '
            'Masterpasswort wird nicht gespeichert. Bewahre es getrennt vom '
            'Backup auf.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _exportBackup,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Backup mit Masterpasswort speichern'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _importBackup,
            icon: const Icon(Icons.restore_outlined),
            label: const Text('Backup wiederherstellen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('daily-text-zip-export-button'),
            onPressed: _exportDailyTextZip,
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('Tageweise als PIN-geschütztes ZIP exportieren'),
          ),
          const Divider(height: 32),
          Text(
            'Zugriffsschutz',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.pin_outlined),
            title: Text(
              widget.controller.hasTimelinePin
                  ? 'Timeline-PIN ändern'
                  : 'Timeline-PIN einrichten',
            ),
            subtitle: const Text(
              'Mindestens sechs Ziffern. Die PIN wird nicht gespeichert.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _managePin,
          ),
          if (Platform.isAndroid)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Biometrie für Timeline anbieten'),
              subtitle: const Text('PIN bleibt als Fallback verfügbar.'),
              value: settings.biometricTimeline,
              onChanged: (value) => setState(
                () => _draft = settings.copyWith(biometricTimeline: value),
              ),
            )
          else
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.fingerprint),
              title: Text(
                'Biometrie ist auf dieser Plattform nicht verfügbar.',
              ),
              subtitle: Text('Die Timeline wird mit der App-PIN geschützt.'),
            ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Einträge werden lokal mit AES-256-GCM verschlüsselt. '
                'Der Datenschlüssel liegt im Geräte-Schlüsselbund. Es gibt keinen Cloud-Sync.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _modelDownloadService.cancel();
    _memoryController.dispose();
    super.dispose();
  }

  Widget _modelDownloadOption(
    LocalModelCatalogEntry model,
    FilterlosSettings settings, {
    bool asEmbeddingModel = false,
  }) {
    final isDownloading = _downloadingModelId == model.id;
    final activePath = asEmbeddingModel
        ? settings.embeddingModelPath
        : settings.localModelPath;
    final isActive = p.basename(activePath) == model.filename;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(model.name),
          subtitle: Text(
            '${model.description}\n'
            '${formatModelSize(model.sizeBytes)} · ${model.licenseLabel}',
          ),
          trailing: isDownloading
              ? IconButton(
                  tooltip: 'Download abbrechen',
                  onPressed: _cancelModelDownload,
                  icon: const Icon(Icons.close),
                )
              : isActive
              ? const Icon(Icons.check_circle_outline)
              : IconButton(
                  tooltip: 'Modell herunterladen und aktivieren',
                  onPressed: _downloadingModelId != null || _copyingModel
                      ? null
                      : () => _downloadModel(
                          model,
                          asEmbeddingModel: asEmbeddingModel,
                        ),
                  icon: const Icon(Icons.download_outlined),
                ),
        ),
        if (isDownloading) ...[
          LinearProgressIndicator(
            value: _downloadedModelBytes / model.sizeBytes,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatModelSize(_downloadedModelBytes)} / '
            '${formatModelSize(model.sizeBytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _ColorDropdown extends StatelessWidget {
  const _ColorDropdown({
    required this.label,
    required this.value,
    required this.stealth,
    required this.onChanged,
  });

  final String label;
  final int value;
  final bool stealth;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = FilterlosSettings.colors.entries.toList();
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: colors
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: stealth
                          ? const Color(0xFF777777)
                          : Color(entry.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(entry.value),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _PinChange {
  const _PinChange({required this.newPin, this.currentPin = ''});

  final String currentPin;
  final String newPin;
}

class _MasterPasswordDialog extends StatefulWidget {
  const _MasterPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<_MasterPasswordDialog> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  void _submit() {
    if (_password.text.trim().length < 8) {
      setState(() => _error = 'Mindestens 8 Zeichen verwenden.');
      return;
    }
    if (widget.confirm && _password.text != _confirmation.text) {
      setState(() => _error = 'Die Masterpasswörter stimmen nicht überein.');
      return;
    }
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.confirm ? 'Masterpasswort festlegen' : 'Masterpasswort eingeben',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Masterpasswort'),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Wiederholen'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Weiter')),
      ],
    );
  }

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.hasPin});

  final bool hasPin;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _current = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  void _submit() {
    if (_pin.text.length < 6 || !RegExp(r'^\d+$').hasMatch(_pin.text)) {
      setState(() => _error = 'Verwende mindestens sechs Ziffern.');
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = 'Die PINs stimmen nicht überein.');
      return;
    }
    Navigator.of(context)
        .pop(_PinChange(currentPin: _current.text, newPin: _pin.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.hasPin ? 'PIN ändern' : 'Timeline-PIN einrichten'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.hasPin) ...[
              TextField(
                controller: _current,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Aktuelle PIN'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Neue PIN'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN wiederholen'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Speichern')),
      ],
    );
  }

  @override
  void dispose() {
    _current.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }
}
