import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'services/local_ai_service.dart';

class AiProgressView extends StatelessWidget {
  const AiProgressView({
    super.key,
    required this.progress,
    this.showSpinner = true,
  });

  final ValueListenable<AiProgress?> progress;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<AiProgress?>(
      valueListenable: progress,
      builder: (context, value, _) {
        final status = value?.status ?? 'Fi denkt lokal nach…';
        final partial = value?.partialText ?? '';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showSpinner) ...[
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (partial.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(partial),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
