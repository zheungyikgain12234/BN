import 'package:flutter/material.dart';

import 'theme.dart';

/// White rounded surface used everywhere (the `bg-surface-container-lowest rounded-xl shadow-sm` pattern).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = C.surfaceLowest, this.onTap, this.clip = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final deco = BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: C.outlineVariant.withValues(alpha: 0.6)),
      boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
    );
    final inner = Padding(padding: padding, child: child);
    return Container(
      decoration: deco,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: onTap == null
          ? inner
          : Material(color: Colors.transparent, child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: inner)),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false, this.color = C.primary, this.height = 40, this.expand = true});
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Color color;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        minimumSize: Size(expand ? double.infinity : 0, height),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          else ...[
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: T.labelLg.copyWith(color: Colors.white))),
            if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 16)],
          ],
        ],
      ),
    );
    return btn;
  }
}

/// Small rounded label (badges, tags, status chips).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.bg = C.surfaceHigh, this.fg = C.onSurfaceVariant, this.radius = 999, this.style});
  final String text;
  final IconData? icon;
  final Color bg, fg;
  final double radius;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: (style ?? T.labelSm).copyWith(color: fg))),
        ]),
      );
}

class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.height, this.width, this.fit = BoxFit.cover});
  final String? url;
  final double? height, width;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      width: width,
      color: C.surfaceContainer,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: C.outline),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(url!, height: height, width: width, fit: fit, errorBuilder: (_, _, _) => placeholder);
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, this.name = '', this.size = 32});
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: (url == null || url!.isEmpty)
            ? Container(color: C.primaryFixed, alignment: Alignment.center, child: Text(initial, style: T.labelLg.copyWith(color: C.primary)))
            : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: C.primaryFixed)),
      ),
    );
  }
}

/// Centered card page used by login / MFA / tenant select (max-w-lg on a soft surface).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child, this.maxWidth = 512});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: C.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AppCard(padding: const EdgeInsets.all(24), child: child),
              ),
            ),
          ),
        ),
      );
}

/// Bordered input: light fill, 1px border, italic placeholder (dropdown hints stay upright, see [dropdownHint]).
InputDecoration fieldDecoration({String? hint, IconData? prefix, Widget? suffix}) {
  OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    hintStyle: T.bodyMd.copyWith(color: C.outline.withValues(alpha: 0.75), fontStyle: FontStyle.italic),
    prefixIcon: prefix == null ? null : Icon(prefix, size: 18, color: C.secondary),
    suffixIcon: suffix,
    filled: true,
    // Active boxes are white; disabled ones are flat grey with a faint border, so the two are easy to tell apart.
    fillColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.disabled) ? const Color(0xFFDCE0DD) : C.surfaceLowest),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: b(C.outlineVariant),
    enabledBorder: b(C.outline),
    disabledBorder: b(const Color(0xFFC9CFCB)),
    focusedBorder: b(C.primary, 1.5),
    errorBorder: b(C.error),
    focusedErrorBorder: b(C.error, 1.5),
  );
}

/// Placeholder for dropdowns: regular (non-italic) text like "Select a department".
Widget dropdownHint(String text) => Text(text, style: T.bodyMd.copyWith(color: C.outline.withValues(alpha: 0.85)));

/// Form row: bold label (red * when required) above the field.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.required = false, this.helper});
  final String label;
  final Widget child;
  final bool required;
  final String? helper;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(TextSpan(text: label, style: T.labelMd, children: [
          if (required) const TextSpan(text: ' *', style: TextStyle(color: C.error)),
        ])),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[const SizedBox(height: 4), Text(helper!, style: T.labelSm.copyWith(color: C.secondary))],
      ]);
}

void showError(BuildContext context, Object e) {
  final msg = e.toString().replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: C.error, behavior: SnackBarBehavior.floating));
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: C.error, size: 32),
            const SizedBox(height: 8),
            Text('Something went wrong', style: T.headlineSm),
            const SizedBox(height: 4),
            Text('$error', style: T.bodySm, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ]),
        ),
      );
}

/// Runs [task] with a centred spinner box over the whole screen, so nobody clicks again while it is working.
/// Use it around anything slow, such as a call to 20i.
Future<R> withLoader<R>(BuildContext context, Future<R> Function() task, {String message = 'Please wait...'}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black38,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          borderRadius: BorderRadius.circular(12),
          color: C.surfaceLowest,
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(height: 16),
              Text(message, style: T.bodyMd),
            ]),
          ),
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (nav.mounted) nav.pop();
  }
}
