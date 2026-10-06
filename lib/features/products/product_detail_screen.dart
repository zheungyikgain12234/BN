import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Product> _product;
  late Future<List<ProductScreenshot>> _shots;
  late Future<List<ProductComment>> _comments;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId) _load();
  }

  void _load() {
    _product = catalogRepo.product(widget.productId);
    _shots = catalogRepo.screenshots(widget.productId);
    _reloadComments();
  }

  void _reloadComments() => _comments = catalogRepo.comments(widget.productId);

  void _soon(String what) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what is not available yet.')));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Product>(
      future: _product,
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(error: snap.error!, onRetry: () => setState(_load));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final p = snap.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Breadcrumb(name: p.name),
                _Header(product: p, onProcure: () => _soon('Procurement'), onTrial: () => _soon('Free trial')),
                const SizedBox(height: 24),
                LayoutBuilder(builder: (context, c) {
                  final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FutureBuilder<List<ProductScreenshot>>(
                      future: _shots,
                      builder: (_, s) => s.hasData && s.data!.isNotEmpty ? _Screenshots(shots: s.data!) : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 24),
                    _About(product: p),
                  ]);
                  final right = _BundleCard(onConfigure: () => _soon('Bundle configuration'));
                  if (c.maxWidth >= 1024) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 8, child: left),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: right),
                    ]);
                  }
                  return Column(children: [left, const SizedBox(height: 24), right]);
                }),
                const SizedBox(height: 24),
                _Discussion(
                  productId: p.id,
                  comments: _comments,
                  onPosted: () => setState(_reloadComments),
                  onRetry: () => setState(_reloadComments),
                  onUnsupported: _soon,
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    Widget link(String t, VoidCallback onTap, {IconData? icon}) => InkWell(
          onTap: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: C.secondary), const SizedBox(width: 4)],
            Text(t, style: T.labelSm.copyWith(color: C.secondary)),
          ]),
        );
    const sep = Icon(Icons.chevron_right, size: 14, color: C.outline);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        link('Home', () => context.go(Routes.home), icon: Icons.home_outlined),
        sep,
        link('Products', () => context.go(Routes.software)),
        sep,
        link('Software', () => context.go(Routes.software)),
        sep,
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(name, overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product, required this.onProcure, required this.onTrial});
  final Product product;
  final VoidCallback onProcure, onTrial;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final info = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [C.primary, C.primaryContainer, Color(0xFF006398)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 8, offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.psychology_outlined, size: 48, color: Colors.white),
        ),
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.verified, size: 20, color: C.primary),
          ),
        ),
      ]),
      const SizedBox(width: 24),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(p.name, style: T.headlineLg),
            const Pill('Enterprise Verified', icon: Icons.verified_user_outlined, bg: C.tertiaryFixed, fg: C.onTertiaryFixed),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (p.publisher.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.apartment, size: 14, color: C.primary),
                const SizedBox(width: 4),
                Flexible(child: Text(p.publisher, style: T.labelMd.copyWith(color: C.primary, fontWeight: FontWeight.w500))),
              ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, size: 14, color: C.amber),
              const SizedBox(width: 4),
              Text(p.rating.toStringAsFixed(1), style: T.labelMd),
              Text(' (${p.ratingCount} verified enterprise reviews)', style: T.labelMd.copyWith(color: C.secondary, fontWeight: FontWeight.w500)),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < p.tags.length; i++)
              Pill(p.tags[i], bg: i == 0 ? C.secondaryContainer : C.surfaceContainer, fg: i == 0 ? const Color(0xFF131B2E) : C.onSurfaceVariant, radius: 6),
            if (p.version.isNotEmpty) Pill(p.version, bg: C.surfaceContainer, radius: 6),
          ]),
        ]),
      ),
    ]);

    final price = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('LICENSING STARTING FROM', style: T.labelSm.copyWith(color: C.secondary, letterSpacing: 0.9)),
        const SizedBox(height: 2),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
          Text(p.priceLabel, style: T.headlineXl.copyWith(color: C.primary)),
          Text('/ ${p.pricingModel.toLowerCase()}', style: T.bodySm.copyWith(color: C.secondary)),
        ]),
        if (p.seatPrice.isNotEmpty) Text(p.seatPrice, style: T.labelSm.copyWith(color: C.outline)),
        const SizedBox(height: 12),
        PrimaryButton(label: 'Procure License', icon: Icons.shopping_cart_checkout, onPressed: onProcure),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onTrial,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: BorderSide.none,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.hourglass_top, size: 16, color: C.primary),
              label: Text('30-Day Free Trial', style: T.labelMd.copyWith(color: C.primary)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Add to Multi-Tenant Bundle',
            onPressed: onTrial,
            style: IconButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(44, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            icon: const Icon(Icons.library_add_outlined, size: 20, color: C.secondary),
          ),
        ]),
      ]),
    );

    return AppCard(
      clip: true,
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 1024) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: info), const SizedBox(width: 24), SizedBox(width: 360, child: price)]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 24), price]);
      }),
    );
  }
}

class _Screenshots extends StatefulWidget {
  const _Screenshots({required this.shots});
  final List<ProductScreenshot> shots;

  @override
  State<_Screenshots> createState() => _ScreenshotsState();
}

class _ScreenshotsState extends State<_Screenshots> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _by(double dx) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + dx).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData i, String tip, VoidCallback f) => IconButton(
          tooltip: tip,
          onPressed: f,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(backgroundColor: C.surfaceContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          icon: Icon(i, size: 16, color: C.secondary),
        );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.screenshot_monitor, color: C.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Product Interface & Live Telemetry', style: T.headlineSm)),
          arrow(Icons.arrow_back, 'Previous screenshot', () => _by(-320)),
          const SizedBox(width: 6),
          arrow(Icons.arrow_forward, 'Next screenshot', () => _by(320)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 300,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemCount: widget.shots.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final s = widget.shots[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 352,
                  color: C.surfaceLowest,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    NetImage(s.url, height: 208),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CORE SCREEN ${(i + 1).toString().padLeft(2, '0')}', style: T.labelSm.copyWith(color: C.primary, fontWeight: FontWeight.w700)),
                        Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.headlineSm),
                        Text(s.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.bodySm.copyWith(color: C.secondary)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final specs = <(String, String, bool)>[
      ('Product SKU / ID', p.sku, true),
      ('Default Billing Cycle', p.billingCycle, false),
      ('Minimum Commitment', p.minCommitment, false),
      ('Supported Cloud Targets', p.cloudTargets, false),
      ('Publisher Code', p.publisherCode, false),
      ('Multi-Tenant Capable', p.multiTenant ? 'Yes (Cross-Tenant Sync)' : 'No', false),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('About This Enterprise Application', style: T.headlineMd),
        const SizedBox(height: 8),
        Text(p.about.isEmpty ? p.description : p.about, style: T.bodyMd.copyWith(color: C.onSurfaceVariant, height: 1.6)),
        const SizedBox(height: 24),
        Row(children: [
          const Icon(Icons.table_chart_outlined, color: C.secondary),
          const SizedBox(width: 8),
          Text('Product Specifications & Licensing Details', style: T.headlineSm),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth >= 560 ? (c.maxWidth - 2) / 2 : c.maxWidth;
            return Wrap(spacing: 2, runSpacing: 2, children: [
              for (var i = 0; i < specs.length; i++)
                Container(
                  width: w,
                  padding: const EdgeInsets.all(12),
                  color: C.surfaceLowest,
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(specs[i].$1, style: T.labelSm.copyWith(color: C.secondary)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        specs[i].$2.isEmpty ? '—' : specs[i].$2,
                        textAlign: TextAlign.right,
                        style: T.labelMd.copyWith(
                          fontFamily: specs[i].$3 ? 'monospace' : null,
                          color: specs[i].$1 == 'Publisher Code' ? C.primary : specs[i].$1 == 'Multi-Tenant Capable' && p.multiTenant ? C.tertiary : C.onSurface,
                        ),
                      ),
                    ),
                  ]),
                ),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({required this.onConfigure});
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [C.primaryFixed.withValues(alpha: 0.3), C.surfaceLowest, C.surfaceLow], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Pill('Recommended Pair', bg: C.primary, fg: Colors.white, radius: 4, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          Text('Save 18%', style: T.labelSm.copyWith(color: C.secondary)),
        ]),
        const SizedBox(height: 8),
        Text('M365 Copilot + Gain City AI Co-Pilot Bridge', style: T.headlineSm),
        const SizedBox(height: 4),
        Text('Combine enterprise document search with native Microsoft Teams and Outlook field workflows.', style: T.bodySm.copyWith(color: C.secondary)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bundle Total', style: T.labelSm.copyWith(color: C.secondary)),
            Text('SGD \$210 / mo', style: T.headlineSm.copyWith(color: C.primary, fontWeight: FontWeight.w700)),
          ]),
          TextButton(
            onPressed: onConfigure,
            style: TextButton.styleFrom(backgroundColor: C.surfaceHighest, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text('Configure Bundle', style: T.labelSm.copyWith(color: C.onSurface)),
          ),
        ]),
      ]),
    );
  }
}

class _Discussion extends StatefulWidget {
  const _Discussion({required this.productId, required this.comments, required this.onPosted, required this.onRetry, required this.onUnsupported});
  final String productId;
  final Future<List<ProductComment>> comments;
  final VoidCallback onPosted, onRetry;
  final void Function(String) onUnsupported;

  @override
  State<_Discussion> createState() => _DiscussionState();
}

class _DiscussionState extends State<_Discussion> {
  final _input = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _input.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await catalogRepo.postComment(widget.productId, text);
      _input.clear();
      widget.onPosted();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: FutureBuilder<List<ProductComment>>(
        future: widget.comments,
        builder: (context, snap) {
          final count = snap.data?.length;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Discussions & Enterprise Feedback', style: T.headlineMd),
                  if (count != null) Pill('$count Comments', bg: C.secondaryContainer, fg: const Color(0xFF131B2E), style: T.labelSm.copyWith(fontWeight: FontWeight.w700)),
                ]),
                Text('Verified procurement discussions, deployment insights, and peer architectural evaluations.', style: T.bodySm.copyWith(color: C.secondary)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Sort by: ', style: T.labelSm.copyWith(color: C.secondary)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [Text('Most Relevant & Endorsed', style: T.labelSm), const Icon(Icons.expand_more, size: 16)]),
                ),
              ]),
            ]),
            const SizedBox(height: 16),
            _composer(),
            const SizedBox(height: 24),
            if (snap.hasError)
              ErrorRetry(error: snap.error!, onRetry: widget.onRetry)
            else if (!snap.hasData)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (snap.data!.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('No discussions yet. Be the first to share feedback.', style: T.bodyMd.copyWith(color: C.secondary))))
            else
              for (final c in snap.data!) ...[_CommentTile(comment: c), const SizedBox(height: 24)],
          ]);
        },
      ),
    );
  }

  Widget _composer() {
    final state = AppState.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(url: state.avatarUrl, name: state.displayName, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            TextField(
              controller: _input,
              minLines: 3,
              maxLines: 6,
              style: T.bodySm,
              decoration: fieldDecoration(hint: 'Share your feedback, deployment question, or review for this app...').copyWith(
                fillColor: Colors.white,
                hintStyle: T.bodySm.copyWith(color: C.secondary),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, children: [
              Wrap(children: [
                _ComposerAction(Icons.image_outlined, C.primary, 'Add Photo', () => widget.onUnsupported('Photo attachments')),
                _ComposerAction(Icons.attach_file, C.tertiary, 'Attach Document / Log', () => widget.onUnsupported('Document attachments')),
                _ComposerAction(Icons.alternate_email, C.secondary, 'Mention Colleague', () => widget.onUnsupported('Mentions')),
              ]),
              SizedBox(
                width: 140,
                child: PrimaryButton(label: 'Post Comment', height: 38, loading: _posting, onPressed: _post),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _ComposerAction extends StatelessWidget {
  const _ComposerAction(this.icon, this.color, this.label, this.onTap);
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: T.labelSm.copyWith(color: C.secondary)),
      );
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final ProductComment comment;

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} hr ago';
    if (d.inDays < 7) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
    if (d.inDays < 30) return '${d.inDays ~/ 7} week${d.inDays ~/ 7 == 1 ? '' : 's'} ago';
    return '${d.inDays ~/ 30} month${d.inDays ~/ 30 == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final isImage = c.attachmentType == 'image';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: C.surfaceLow, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Avatar(url: c.avatarUrl, name: c.authorName, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.authorName, style: T.headlineSm),
                  if (c.authorTitle.isNotEmpty) Text(c.authorTitle, style: T.labelSm.copyWith(color: C.secondary)),
                ]),
              ),
              Text(_ago(c.createdAt), style: T.labelSm.copyWith(color: C.secondary)),
            ]),
            if (c.badge.isNotEmpty) ...[
              const SizedBox(height: 6),
              Pill(c.badge, icon: Icons.verified, bg: C.tertiaryFixed, fg: C.onTertiaryFixed, radius: 4),
            ],
            const SizedBox(height: 8),
            Text(c.body, style: T.bodyMd.copyWith(height: 1.6)),
            if (c.attachmentUrl != null && isImage) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    color: Colors.white,
                    child: Column(children: [
                      NetImage(c.attachmentUrl, height: 176, width: double.infinity),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          Expanded(child: Text(c.attachmentName ?? '', overflow: TextOverflow.ellipsis, style: T.labelSm.copyWith(color: C.secondary, fontFamily: 'monospace'))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ] else if (c.attachmentName != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: C.errorContainer, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.picture_as_pdf_outlined, color: C.error),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.attachmentName!, overflow: TextOverflow.ellipsis, style: T.labelMd)),
                    const Icon(Icons.download, size: 20, color: C.primary),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _Action(Icons.thumb_up, '${c.endorsements} Endorsements', active: true),
              _Action(Icons.chat_bubble_outline, '${c.replies} Replies'),
              const _Action(Icons.repeat, 'Share Review'),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, {this.active = false});
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: active ? C.primary : C.secondary),
        const SizedBox(width: 4),
        Text(label, style: T.labelSm.copyWith(color: active ? C.onSurface : C.secondary, fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
      ]);
}
