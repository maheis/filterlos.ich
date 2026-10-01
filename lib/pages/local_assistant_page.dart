import 'package:flutter/material.dart';

import '../ai_progress_view.dart';
import '../app_controller.dart';
import '../models.dart';

class LocalAssistantPage extends StatefulWidget {
  const LocalAssistantPage({
    super.key,
    required this.controller,
    this.contextEntry,
    this.existingChat,
  });

  final AppController controller;
  final JournalEntry? contextEntry;
  final JournalChat? existingChat;

  @override
  State<LocalAssistantPage> createState() => _LocalAssistantPageState();
}

class _LocalAssistantPageState extends State<LocalAssistantPage> {
  final _questionController = TextEditingController();
  final List<ChatMessage> _lines = [];
  late final JournalEntry? _contextEntry;
  String? _chatId;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _contextEntry = widget.contextEntry ?? _entryForChat(widget.existingChat);
    _chatId = widget.existingChat?.id;
    if (widget.existingChat != null) {
      _lines.addAll(widget.existingChat!.messages);
    }
  }

  JournalEntry? _entryForChat(JournalChat? chat) {
    final entryId = chat?.contextEntryId;
    if (entryId == null) return null;
    for (final entry in widget.controller.entries) {
      if (entry.id == entryId) return entry;
    }
    return null;
  }

  Future<String> _ensureChat() async {
    final current = _chatId;
    if (current != null) return current;
    final chat = await widget.controller.createChat(
      contextEntry: _contextEntry,
    );
    _chatId = chat.id;
    return chat.id;
  }

  Future<void> _saveMessage(ChatMessage message) async {
    await widget.controller.addChatMessage(await _ensureChat(), message);
  }

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _working) return;
    final history = List<ChatMessage>.from(_lines);
    final userMessage = ChatMessage(
      text: question,
      isUser: true,
      createdAt: DateTime.now(),
    );
    setState(() {
      _lines.add(userMessage);
      _questionController.clear();
      _working = true;
    });
    await _saveMessage(userMessage);
    try {
      final answer = await widget.controller.chatReply(
        question,
        contextEntry: _contextEntry,
        history: history,
      );
      if (!mounted) return;
      final answerMessage = ChatMessage(
        text: answer,
        isUser: false,
        createdAt: DateTime.now(),
      );
      await _saveMessage(answerMessage);
      if (mounted) setState(() => _lines.add(answerMessage));
    } catch (error) {
      if (!mounted) return;
      final errorMessage = ChatMessage(
        text: error.toString().replaceFirst('Bad state: ', ''),
        isUser: false,
        createdAt: DateTime.now(),
      );
      setState(() {
        _lines.add(errorMessage);
      });
      await _saveMessage(errorMessage);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _dailyRecap() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final recap = await widget.controller.dailyRecap();
      if (!mounted) return;
      final recapMessage = ChatMessage(
        text: recap,
        isUser: false,
        createdAt: DateTime.now(),
      );
      await _saveMessage(recapMessage);
      if (mounted) setState(() => _lines.add(recapMessage));
    } catch (error) {
      if (!mounted) return;
      final errorMessage = ChatMessage(
        text: error.toString().replaceFirst('Bad state: ', ''),
        isUser: false,
        createdAt: DateTime.now(),
      );
      setState(() {
        _lines.add(errorMessage);
      });
      await _saveMessage(errorMessage);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _contextEntry == null
              ? 'fi · lokal'
              : 'fi · ${_contextEntry.category.name}',
        ),
        actions: [
          IconButton(
            tooltip: 'Tagesrückblick erstellen',
            onPressed: _working ? null : _dailyRecap,
            icon: const Icon(Icons.today_outlined),
          ),
          IconButton(
            tooltip: 'Chat leeren',
            onPressed: _lines.isEmpty || _working
                ? null
                : () => setState(_lines.clear),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                _contextEntry == null
                    ? 'Antworten werden mit deinem ausgewählten Modell lokal erzeugt. Für Tagebuchfragen nutzt fi passende Einträge aus der verschlüsselten Timeline.'
                    : 'Dieser Chat bezieht sich auf den ausgewählten Tagebucheintrag und wird verschlüsselt in deiner Timeline gespeichert.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: _lines.isEmpty
                  ? Center(
                      child: Text(
                        'Frag dein Tagebuch oder erstelle einen Tagesrückblick.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _lines.length,
                      itemBuilder: (context, index) {
                        final line = _lines[index];
                        return Align(
                          alignment: line.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Card(
                              color: line.isUser
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerLow,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: SelectableText(line.text),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_working) ...[
              const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AiProgressView(
                  progress: widget.controller.aiProgress,
                  showSpinner: false,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _questionController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      decoration: const InputDecoration(
                        labelText: 'Frage an dein Tagebuch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Frage lokal beantworten',
                    onPressed: _working ? null : _ask,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }
}
