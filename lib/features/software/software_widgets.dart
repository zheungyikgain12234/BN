import 'package:flutter/material.dart';

import '../../core/icon_registry.dart';
import '../../core/theme.dart';
import '../../data/models.dart';

/// App icon: the uploaded image, or the category icon on a green tile when there is none.
class AppIconTile extends StatelessWidget {
  const AppIconTile({super.key, required this.product, this.size = 56});
  final Product product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [C.primary, C.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Icon(categoryIcon(product.categoryIcon), size: size * 0.5, color: Colors.white),
    );
    final url = product.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

/// "2 hr ago" style timestamp.
String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} hr ago';
  if (d.inDays < 7) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  if (d.inDays < 30) return '${d.inDays ~/ 7} week${d.inDays ~/ 7 == 1 ? '' : 's'} ago';
  return '${d.inDays ~/ 30} month${d.inDays ~/ 30 == 1 ? '' : 's'} ago';
}

/// Full-size image viewer with pinch/scroll zoom.
void showImageViewer(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(children: [
        InteractiveViewer(child: Center(child: Image.network(url, fit: BoxFit.contain))),
        Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx))),
      ]),
    ),
  );
}
