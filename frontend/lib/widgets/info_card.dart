import 'package:flutter/material.dart';
import 'section_title.dart';

class InfoCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const InfoCard({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) SectionTitle(title: title!),
            ...children,
          ],
        ),
      ),
    );
  }
}
