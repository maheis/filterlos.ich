import 'package:flutter/material.dart';

import '../app_controller.dart';

class LocalAssistantPage extends StatefulWidget {
  const LocalAssistantPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<LocalAssistantPage> createState() => _LocalAssistantPageState();
}

class _LocalAssistantPageState extends State<LocalAssistantPage> {
  final _questionController = TextEditingController();
  final List<_ChatLine> _lines = [];
  bool _working = false;

  Future<void> _ask() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _working) return;
    setState(() {
      _lines.add(_ChatLine(text: question, isUser: true));
      _questionController.clear();
      _working = true;
    });
    try {
      final answer = await widget.controller.askDiary(question);
      if (!mounted) return;
      setState(() => _lines.add(_ChatLine(text: answer, isUser: false)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lines.add(
          _ChatLine(
            text: error.toString().replaceFirst('Bad state: ', ''),
            isUser: false,
          ),
        );
      });
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
      setState(() => _lines.add(_ChatLine(text: recap, isUser: false)));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lines.add(
          _ChatLine(
            text: error.toString().replaceFirst('Bad state: ', ''),
            isUser: false,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('fi · lokal'),
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
                'Antworten werden mit deinem ausgewählten Modell lokal erzeugt. '
                'Für Tagebuchfragen nutzt fi passende Einträge aus der verschlüsselten Timeline.',
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
            if (_working) const LinearProgressIndicator(minHeight: 2),
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

class _ChatLine {
  const _ChatLine({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}
