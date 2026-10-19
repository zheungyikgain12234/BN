import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/icon_registry.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/catalog_repository.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'software_widgets.dart';

/// Pop-up with the app description, Add to cart, screenshots and the comment section.
Future<void> showSoftwareDetail(BuildContext context, Product product) => showDialog<void>(
      context: context,
      builder: (_) => SoftwareDetailDialog(product: product),
    );

class SoftwareDetailDialog extends StatefulWidget {
  const SoftwareDetailDialog({super.key, required this.product});
  final Product product;

  @override
  State<SoftwareDetailDialog> createState() => _SoftwareDetailDialogState();
}

class _SoftwareDetailDialogState extends State<SoftwareDetailDialog> {
  late final Future<List<ProductScreenshot>> _shots = catalogRepo.screenshots(widget.product.id);
  late Future<List<ProductComment>> _comments = catalogRepo.comments(widget.product.id);
  final _input = TextEditingController();
  UploadedFile? _attachment;
  bool _posting = false;
  bool _uploading = false;
  bool _adding = false;
  int _added = 0; // times added from this pop-up

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _addToCart() async {
    setState(() => _adding = true);
    try {
      await cartRepo.add(widget.product.id);
      if (mounted) setState(() => _added++);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _viewCart() {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.go(Routes.cart);
  }

  Future<void> _pickImage() async {
    setState(() => _uploading = true);
    try {
      final f = await catalogRepo.pickAndUploadImage('comments');
      if (f != null && mounted) setState(() => _attachment = f);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _post() async {
    final text = _input.text.trim();
    if ((text.isEmpty && _attachment == null) || _posting) return;
    setState(() => _posting = true);
    try {
      await catalogRepo.postComment(widget.product.id, text, attachment: _attachment);
      _input.clear();
      setState(() {
        _attachment = null;
        _comments = catalogRepo.comments(widget.product.id);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _deleteComment(ProductComment c) async {
    try {
      await catalogRepo.deleteComment(c.id);
      if (mounted) setState(() => _comments = catalogRepo.comments(widget.product.id));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Dialog(
      backgroundColor: C.surface,
      insetPadding: wide ? const EdgeInsets.symmetric(horizontal: 40, vertical: 32) : EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(wide ? 16 : 0)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _header(wide),
                const SizedBox(height: 20),
                _screenshots(),
                _about(),
                const SizedBox(height: 20),
                _discussion(),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header(bool wide) {
    final p = widget.product;
    final info = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      AppIconTile(product: p, size: wide ? 80 : 64),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: T.headlineLg),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (p.categoryName.isNotEmpty) Pill(p.categoryName, icon: categoryIcon(p.categoryIcon), bg: C.primaryFixed, fg: C.onPrimaryFixed, radius: 6),
            if (p.version.isNotEmpty) Pill('v${p.version}', radius: 6),
            for (final t in p.tags) Pill(t, bg: C.surfaceContainer, radius: 6),
          ]),
        ]),
      ),
    ]);
    final buy = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p.price != null) ...[
        Text(p.priceLabel, style: T.headlineLg.copyWith(color: C.primary)),
        if (p.priceUnit.isNotEmpty) Text(p.priceUnit, style: T.labelSm.copyWith(color: C.secondary)),
        const SizedBox(height: 8),
      ],
      PrimaryButton(label: 'Add to cart', icon: Icons.add_shopping_cart, loading: _adding, onPressed: _addToCart),
      if (_added > 0) TextButton.icon(onPressed: _viewCart, icon: const Icon(Icons.check_circle, size: 16, color: C.tertiary), label: Text('Added ($_added) • View cart')),
    ]);
    return AppCard(
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: info), const SizedBox(width: 24), SizedBox(width: 240, child: buy)])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 16), buy]),
    );
  }

  Widget _screenshots() => FutureBuilder<List<ProductScreenshot>>(
        future: _shots,
        builder: (context, snap) {
          final shots = snap.data;
          if (shots == null || shots.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Screenshots', style: T.headlineSm),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: shots.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final s = shots[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => showImageViewer(context, s.url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 320,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Expanded(child: Image.network(s.url, fit: BoxFit.cover, errorBuilder: (_, _, _) => const ColoredBox(color: C.surfaceContainer, child: Icon(Icons.broken_image_outlined)))),
                              if (s.title.isNotEmpty || s.caption.isNotEmpty)
                                Container(
                                  color: C.surfaceLow,
                                  padding: const EdgeInsets.all(8),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    if (s.title.isNotEmpty) Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.labelMd),
                                    if (s.caption.isNotEmpty) Text(s.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.secondary)),
                                  ]),
                                ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      );

  Widget _about() {
    final p = widget.product;
    final specs = <(String, String)>[
      ('Version', p.version),
      ('SKU', p.sku),
      ('Pricing model', p.pricingModel),
      ('Company', p.tenantName),
    ].where((s) => s.$2.isNotEmpty).toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('About this app', style: T.headlineMd),
        const SizedBox(height: 8),
        Text(p.about.isEmpty ? p.description : p.about, style: T.bodyMd.copyWith(color: C.onSurfaceVariant, height: 1.6)),
        if (specs.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final s in specs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 130, child: Text(s.$1, style: T.labelSm.copyWith(color: C.secondary))),
                Expanded(child: Text(s.$2, style: T.labelMd)),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _discussion() {
    final state = AppState.instance;
    return AppCard(
      child: FutureBuilder<List<ProductComment>>(
        future: _comments,
        builder: (context, snap) {
          final list = snap.data;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('Comments', style: T.headlineMd),
              if (list != null) Pill('${list.length}', bg: C.secondaryContainer, radius: 999),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Avatar(url: state.avatarUrl, name: state.displayName, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 2,
                      maxLines: 6,
                      decoration: fieldDecoration(hint: 'Write a comment...').copyWith(fillColor: C.surfaceLowest),
                    ),
                  ),
                ]),
                if (_attachment != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.image_outlined, size: 16),
                      label: Text(_attachment!.name, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() => _attachment = null),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
                  TextButton.icon(
                    onPressed: _uploading ? null : _pickImage,
                    icon: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined, size: 18),
                    label: Text(_attachment == null ? 'Add image' : 'Change image'),
                  ),
                  SizedBox(width: 140, child: PrimaryButton(label: 'Post', height: 38, loading: _posting, onPressed: _post)),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            if (snap.hasError)
              ErrorRetry(error: snap.error!, onRetry: () => setState(() => _comments = catalogRepo.comments(widget.product.id)))
            else if (list == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              Padding(padding: const EdgeInsets.all(16), child: Center(child: Text('No comments yet. Be the first.', style: T.bodyMd.copyWith(color: C.secondary))))
            else
              for (final c in list) ...[_commentTile(c), const SizedBox(height: 12)],
          ]);
        },
      ),
    );
  }

  Widget _commentTile(ProductComment c) {
    final canDelete = c.userId == sb.auth.currentUser?.id || AppState.instance.canManageCatalog;
    final name = c.authorName.isEmpty ? 'Unknown user' : c.authorName;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(url: c.avatarUrl, name: name, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: T.labelLg, overflow: TextOverflow.ellipsis)),
              Text(timeAgo(c.createdAt), style: T.labelSm.copyWith(color: C.secondary)),
              if (canDelete)
                IconButton(
                  tooltip: 'Delete comment',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18, color: C.error),
                  onPressed: () => _deleteComment(c),
                ),
            ]),
            if (c.authorTitle.isNotEmpty) Text(c.authorTitle, style: T.labelSm.copyWith(color: C.secondary)),
            if (c.body.isNotEmpty) ...[const SizedBox(height: 4), Text(c.body, style: T.bodyMd.copyWith(height: 1.5))],
            if (c.hasImage) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => showImageViewer(context, c.attachmentUrl!),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360, maxHeight: 240),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(c.attachmentUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
