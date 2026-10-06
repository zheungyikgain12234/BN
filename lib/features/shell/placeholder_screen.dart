import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Stand-in for sidebar sections that have no design yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context) {
    final title = slug.split('-').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.construction, size: 36, color: C.outline),
        const SizedBox(height: 12),
        Text(title, style: T.headlineLg),
        const SizedBox(height: 4),
        Text('This section is coming soon.', style: T.bodyMd.copyWith(color: C.secondary)),
      ]),
    );
  }
}
