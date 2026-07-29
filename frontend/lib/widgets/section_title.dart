import 'package:flutter/material.dart';
import '../theme/theme_extensions.dart';

class SectionTitle extends StatelessWidget {
  final String title;

  const SectionTitle({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final dockerColors = Theme.of(context).extension<DockerColors>();
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          color: dockerColors?.sectionTitle ?? Colors.blue,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
