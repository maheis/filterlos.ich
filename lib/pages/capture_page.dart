import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_controller.dart';
import '../category_icon.dart';
import '../models.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.controller,
    required this.category,
  });

  final AppController controller;
  final EmotionCategory category;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  static const _maxImageBytes = 8 * 1024 * 1024;
  static const _maxAudioBytes = 12 * 1024 * 1024;

  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  final _speech = SpeechToText();
  final List<JournalAttachment> _attachments = [];
  bool _isRecording = false;
  bool _isListening = false;
  bool _isSaving = false;
  String? _audioPath;
  String _speechBase = '';
  Timer? _recordingLimitTimer;

  bool get _canUseSpeech => Platform.isAndroid;

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      if (result.isEmpty) return;
      final picked = result.single;
      final selectedSize = await picked.length();
      if (selectedSize != null && selectedSize > _maxImageBytes) {
        _showMessage('Bilder dürfen höchstens 8 MB groß sein.');
        return;
      }
      final bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        _showMessage('Bilder dürfen höchstens 8 MB groß sein.');
        return;
      }
      final extension = (picked.extension ?? '').toLowerCase();
      final mime = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      setState(() {
        _attachments.add(
          JournalAttachment(
            name: picked.name,
            mimeType: mime,
            base64Data: base64Encode(bytes),
          ),
        );
      });
    } catch (_) {
      _showMessage('Das Bild konnte nicht hinzugefügt werden.');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _finishRecording();
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('Mikrofonzugriff wurde nicht erteilt.');
        return;
      }
      final directory = await getTemporaryDirectory();
      _audioPath = p.join(
        directory.path,
        'filterlos-${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: _audioPath!,
      );
      if (mounted) {
        setState(() => _isRecording = true);
        _recordingLimitTimer = Timer(
          const Duration(minutes: 1),
          _finishRecording,
        );
      }
    } catch (_) {
      _showMessage('Die Audioaufnahme konnte nicht gestartet werden.');
    }
  }

  Future<void> _finishRecording() async {
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = null;
    try {
      final path = await _recorder.stop();
      if (mounted) setState(() => _isRecording = false);
      final filePath = path ?? _audioPath;
      if (filePath == null) return;
      final file = File(filePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      await file.delete();
      if (bytes.length > _maxAudioBytes) {
        _showMessage('Audioanhänge dürfen höchstens 12 MB groß sein.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _attachments.add(
          JournalAttachment(
            name: 'Sprachnotiz.m4a',
            mimeType: 'audio/mp4',
            base64Data: base64Encode(bytes),
          ),
        );
      });
    } catch (_) {
      _showMessage('Die Audioaufnahme konnte nicht gespeichert werden.');
    } finally {
      _audioPath = null;
    }
  }

  Future<void> _toggleSpeech() async {
    if (!_canUseSpeech) {
      _showMessage(
        'On-Device-Spracherkennung ist derzeit nur unter Android verfügbar.',
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (!available) {
        _showMessage('Auf diesem Gerät ist keine Spracherkennung verfügbar.');
        return;
      }
      _speechBase = _textController.text.trim();
      if (mounted) setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          final recognized = result.recognizedWords.trim();
          if (recognized.isEmpty || !mounted) return;
          setState(() {
            _textController.text = _speechBase.isEmpty
                ? recognized
                : '$_speechBase\n$recognized';
            _textController.selection = TextSelection.collapsed(
              offset: _textController.text.length,
            );
          });
        },
        listenOptions: SpeechListenOptions(
          onDevice: true,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _isListening = false);
      _showMessage(
        'Offline-Spracherkennung nicht verfügbar. Es wurde kein Cloud-Fallback verwendet.',
      );
    }
  }

  Future<void> _saveEntry() async {
    if (_isSaving) return;
    if (_textController.text.trim().isEmpty && _attachments.isEmpty) {
      _showMessage('Schreib einen Gedanken oder füge einen Anhang hinzu.');
      return;
    }
    if (_isRecording) await _finishRecording();
    setState(() => _isSaving = true);
    try {
      await widget.controller.addEntry(
        JournalEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          categoryId: widget.category.id,
          createdAt: DateTime.now(),
          text: _textController.text.trim(),
          attachments: List<JournalAttachment>.unmodifiable(_attachments),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lokal und verschlüsselt gespeichert.')),
      );
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Speichern fehlgeschlagen. Der Eintrag wurde nicht gesendet.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryIcon(category: category, size: 28),
            const SizedBox(width: 10),
            Flexible(child: Text(category.name)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveEntry,
            child: const Text('Sichern'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  category.description,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _textController,
                  autofocus: true,
                  minLines: 8,
                  maxLines: 18,
                  maxLength: 12000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Was geht dir gerade durch den Kopf?',
                    hintText: 'Ungefiltert. Nur für dich.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Bild'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _toggleRecording,
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic_none),
                      label: Text(
                        _isRecording ? 'Aufnahme stoppen' : 'Audio aufnehmen',
                      ),
                    ),
                    if (_canUseSpeech)
                      FilledButton.tonalIcon(
                        onPressed: _toggleSpeech,
                        icon: Icon(
                          _isListening ? Icons.stop : Icons.graphic_eq,
                        ),
                        label: Text(
                          _isListening ? 'Diktat stoppen' : 'Offline diktieren',
                        ),
                      ),
                  ],
                ),
                if (_isRecording || _isListening) ...[
                  const SizedBox(height: 12),
                  Text(
                    _isRecording
                        ? 'Audioaufnahme läuft…'
                        : 'Offline-Diktat läuft…',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Anhänge',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._attachments.asMap().entries.map((item) {
                    final attachment = item.value;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          attachment.mimeType.startsWith('image/')
                              ? Icons.image_outlined
                              : Icons.audio_file_outlined,
                        ),
                        title: Text(attachment.name),
                        subtitle: Text(
                          attachment.mimeType.startsWith('image/')
                              ? 'Wird mit dem Eintrag verschlüsselt.'
                              : 'Audio wird mit dem Eintrag verschlüsselt.',
                        ),
                        trailing: IconButton(
                          tooltip: 'Anhang entfernen',
                          onPressed: () =>
                              setState(() => _attachments.removeAt(item.key)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveEntry,
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: Text(_isSaving ? 'Sichere…' : 'Verschlüsselt sichern'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recordingLimitTimer?.cancel();
    if (_isListening) _speech.cancel();
    if (_isRecording) _discardTemporaryRecording();
    _textController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _discardTemporaryRecording() async {
    await _recorder.cancel();
    final path = _audioPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }
}
