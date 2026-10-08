import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../category_icon.dart';
import '../models.dart';
import 'capture_page.dart';
import 'demo_page.dart';
import 'settings_page.dart';
import 'timeline_page.dart';

class FilterlosHomePage extends StatelessWidget {
  const FilterlosHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width > 700 ? 660.0 : double.infinity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('filterlos.ich'),
        actions: [
          IconButton(
            tooltip: settings.stealthMode
                ? 'Stealth-Modus aus'
                : 'Stealth-Modus an',
            onPressed: () => controller.updateSettings(
              settings.copyWith(stealthMode: !settings.stealthMode),
            ),
            icon: Icon(
              settings.stealthMode ? Icons.visibility_off : Icons.visibility,
            ),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SettingsPage(controller: controller),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              children: [
                Text(
                  'Was ist gerade in dir?',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ein Moment reicht. Schreib es raus.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                GridView.builder(
                  itemCount: EmotionCategory.all.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.18,
                  ),
                  itemBuilder: (context, index) {
                    final category = EmotionCategory.all[index];
                    return _EmotionTile(
                      category: category,
                      emojiStyle: settings.emojiButtons,
                      stealth: settings.stealthMode,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => CapturePage(
                            controller: controller,
                            category: category,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TimelinePage(controller: controller),
                    ),
                  ),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Timeline'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('open-demo-button'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(builder: (_) => const DemoPage()),
                  ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Demo zeigen'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Deine Gedanken bleiben auf diesem Gerät.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmotionTile extends StatelessWidget {
  const _EmotionTile({
    required this.category,
    required this.emojiStyle,
    required this.stealth,
    required this.onTap,
  });

  final EmotionCategory category;
  final bool emojiStyle;
  final bool stealth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '${category.name}: ${category.description}',
      child: Card(
        color: stealth
            ? const Color(0xFF080808)
            : category.id == 'thought' && scheme.brightness == Brightness.light
            ? const Color(0xFF414650)
            : emojiStyle
            ? scheme.surfaceContainerLow
            : color.withAlpha(38),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: CategoryIcon(
              category: category,
              size: 112,
              stealth: stealth,
            ),
          ),
        ),
      ),
    );
  }
}
