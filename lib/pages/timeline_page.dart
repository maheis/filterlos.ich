import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai_progress_view.dart';
import '../app_controller.dart';
import '../category_icon.dart';
import '../models.dart';
import 'local_assistant_page.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage>
    with WidgetsBindingObserver {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  String? _categoryId;
  String? _error;
  bool _busy = false;
  bool _setupMode = false;
  bool _unlockedHere = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupMode = !widget.controller.hasTimelinePin;
    _unlockedHere = widget.controller.timelineUnlocked;
    if (Platform.isAndroid &&
        widget.controller.settings.biometricTimeline &&
        widget.controller.hasTimelinePin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_unlockedHere) {
          _unlockBiometrics(automatic: true);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _unlockedHere) {
      widget.controller.lockTimeline();
      if (mounted) setState(() => _unlockedHere = false);
    }
  }

  Future<void> _submitPin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_setupMode) {
        if (_pinController.text.length < 6 ||
            !RegExp(r'^\d+$').hasMatch(_pinController.text)) {
          setState(
            () => _error = 'Die PIN muss mindestens 6 Ziffern enthalten.',
          );
          return;
        }
        if (_pinController.text != _confirmPinController.text) {
          setState(() => _error = 'Die PINs stimmen nicht überein.');
          return;
        }
        await widget.controller.configurePin(_pinController.text);
      }

      final unlocked = await widget.controller.unlockWithPin(
        _pinController.text,
      );
      if (!unlocked) {
        setState(() => _error = 'PIN falsch oder Zugriff kurzzeitig gesperrt.');
        return;
      }
      setState(() {
        _unlockedHere = true;
        _setupMode = false;
        _pinController.clear();
        _confirmPinController.clear();
      });
    } catch (_) {
      setState(() => _error = 'Die Timeline konnte nicht entsperrt werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockBiometrics({bool automatic = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final unlocked = await widget.controller.unlockWithBiometrics();
    if (mounted) {
      setState(() {
        _busy = false;
        _unlockedHere = unlocked;
        if (!unlocked) {
          _error = automatic
              ? null
              : 'Biometrische Entsperrung nicht verfügbar. Nutze deine PIN.';
        }
      });
    }
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text(
          'Der verschlüsselte Eintrag wird dauerhaft entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await widget.controller.deleteEntry(entry.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showAiResult(
    String title,
    Future<String> Function() generate,
  ) async {
    final navigator = Navigator.of(context);
    final loadingDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: AiProgressView(progress: widget.controller.aiProgress),
      ),
    );

    String result;
    try {
      result = await generate();
    } catch (error) {
      result = error.toString().replaceFirst('Bad state: ', '');
    }
    if (!mounted) return;
    navigator.pop();
    await loadingDialog;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(result)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlockedHere || !widget.controller.timelineUnlocked) {
      return _buildLockedView(context);
    }
    final entries = widget.controller.entriesFor(categoryId: _categoryId);
    final groupedEntries = groupEntriesByDay(entries);
    final timelineRows = <_TimelineRow>[];
    for (final group in groupedEntries.entries) {
      timelineRows.add(_TimelineRow.header(group.key, group.value.length));
      timelineRows.addAll(group.value.map(_TimelineRow.entry));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deine Timeline'),
        actions: [
          if (widget.controller.settings.localModelPath.isNotEmpty)
            IconButton(
              tooltip: 'Lokal mit fi über dein Tagebuch sprechen',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LocalAssistantPage(controller: widget.controller),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
          if (widget.controller.settings.localModelPath.isNotEmpty)
            IconButton(
              tooltip: 'Tagesrückblick lokal erstellen',
              onPressed: () => _showAiResult(
                'Tagesrückblick · fi',
                widget.controller.dailyRecap,
              ),
              icon: const Icon(Icons.today_outlined),
            ),
          IconButton(
            tooltip: 'Timeline sperren',
            onPressed: () {
              widget.controller.lockTimeline();
              setState(() => _unlockedHere = false);
            },
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Alle'),
                      selected: _categoryId == null,
                      onSelected: (_) => setState(() => _categoryId = null),
                    ),
                  ),
                  ...EmotionCategory.all.map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CategoryIcon(
                              category: category,
                              size: 18,
                              stealth: widget.controller.settings.stealthMode,
                            ),
                            const SizedBox(width: 6),
                            Text(category.name),
                          ],
                        ),
                        selected: _categoryId == category.id,
                        onSelected: (_) =>
                            setState(() => _categoryId = category.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Text('Noch keine Gedanken in dieser Timeline.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: timelineRows.length,
                      itemBuilder: (context, index) {
                        final row = timelineRows[index];
                        if (row.day != null) {
                          return _TimelineDayHeader(
                            day: row.day!,
                            entryCount: row.entryCount,
                          );
                        }
                        final entry = row.entry!;
                        return _EntryCard(
                          entry: entry,
                          stealth: widget.controller.settings.stealthMode,
                          onDelete: () => _deleteEntry(entry),
                          onCompanion:
                              widget.controller.settings.localModelPath.isEmpty
                              ? null
                              : () => _showAiResult(
                                  'fi · ${entry.category.name}',
                                  () => widget.controller.companionReply(entry),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedView(BuildContext context) {
    final hasPin = widget.controller.hasTimelinePin;
    final biometricAvailable =
        Platform.isAndroid &&
        widget.controller.settings.biometricTimeline &&
        hasPin;
    return Scaffold(
      appBar: AppBar(title: const Text('Geschützte Timeline')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  hasPin ? Icons.lock_outline : Icons.shield_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(height: 20),
                Text(
                  hasPin ? 'Nur für dich' : 'Richte deinen Schutz ein',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  hasPin ? 'Gib deine App-PIN ein, um die Timeline zu öffnen.' : 'Lege eine App-PIN mit mindestens sechs Ziffern fest. Sie wird gehasht im Geräte-Schlüsselbund hinterlegt.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textInputAction: _setupMode
                      ? TextInputAction.next
                      : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: hasPin ? 'App-PIN' : 'Neue App-PIN',
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) {
                    if (!_setupMode) _submitPin();
                  },
                ),
                if (_setupMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmPinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'App-PIN wiederholen',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPin(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submitPin,
                  icon: const Icon(Icons.lock_open),
                  label: Text(_setupMode ? 'PIN einrichten' : 'Entsperren'),
                ),
                if (biometricAvailable) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _unlockBiometrics(),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Mit Biometrie entsperren'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_unlockedHere) widget.controller.lockTimeline();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}

class _TimelineRow {
  const _TimelineRow.header(this.day, this.entryCount) : entry = null;
  const _TimelineRow.entry(this.entry) : day = null, entryCount = 0;

  final DateTime? day;
  final int entryCount;
  final JournalEntry? entry;
}

class _TimelineDayHeader extends StatelessWidget {
  const _TimelineDayHeader({required this.day, required this.entryCount});

  final DateTime day;
  final int entryCount;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final yesterday = normalizedToday.subtract(const Duration(days: 1));
    final fullDate = DateFormat('EEEE, d. MMMM yyyy', 'de_DE').format(day);
    final title = day == normalizedToday
        ? 'Heute · $fullDate'
        : day == yesterday
        ? 'Gestern · $fullDate'
        : fullDate;
    final accent = Theme.of(context).colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accent.withAlpha(32),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.calendar_today_outlined, size: 14, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$entryCount ${entryCount == 1 ? 'Eintrag' : 'Einträge'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.stealth,
    required this.onDelete,
    this.onCompanion,
  });

  final JournalEntry entry;
  final bool stealth;
  final VoidCallback onDelete;
  final VoidCallback? onCompanion;

  @override
  Widget build(BuildContext context) {
    final category = entry.category;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryIcon(category: category, size: 26, stealth: stealth),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        formatEntryDate(entry.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Eintrag löschen',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
                if (onCompanion != null)
                  IconButton(
                    tooltip: 'fi um Resonanz bitten',
                    onPressed: onCompanion,
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
              ],
            ),
            if (entry.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(entry.text),
            ],
            if (entry.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...entry.attachments.map(
                (attachment) => _AttachmentView(attachment: attachment),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentView extends StatefulWidget {
  const _AttachmentView({required this.attachment});

  final JournalAttachment attachment;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  final _player = AudioPlayer();
  bool _playing = false;

  Future<void> _togglePlayback() async {
    final attachment = widget.attachment;
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.play(BytesSource(base64Decode(attachment.base64Data)));
      if (mounted) setState(() => _playing = true);
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio konnte nicht abgespielt werden.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    if (attachment.mimeType.startsWith('image/')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            base64Decode(attachment.base64Data),
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 80,
              child: Center(child: Text('Bild konnte nicht angezeigt werden.')),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: IconButton(
          tooltip: _playing ? 'Audio stoppen' : 'Audio abspielen',
          onPressed: _togglePlayback,
          icon: Icon(
            _playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          ),
        ),
        title: Text(attachment.name),
        subtitle: const Text('Verschlüsselter Audioanhang'),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
