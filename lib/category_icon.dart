import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'models.dart';

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.category, required this.size});

  final EmotionCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (asset, color) = switch (category.id) {
      'vent' => ('angry.svg', Color(category.colorValue)),
      'joy' => ('grin-beam.svg', Color(category.colorValue)),
      'sadness' => ('sad-tear.svg', Color(category.colorValue)),
      'thought' => ('surprise.svg', Colors.white),
      'spark' => ('lightbulb-on.svg', const Color(0xFFFFF176)),
      'chaos' => ('dizzy.svg', Color(category.colorValue)),
      _ => ('surprise.svg', Colors.white),
    };

    return SvgPicture.asset(
      'assets/icons/$asset',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
