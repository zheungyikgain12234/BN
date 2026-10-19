import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme.dart';
import '../../data/stackcp_sso.dart';

/// Embeds the white-labelled 20i control panel (StackCP) in an iframe.
/// Each sidebar entry passes its own panel [url].
/// If the frame is blank, the panel is blocking framing — use the new-tab button.
class PanelEmbedScreen extends StatefulWidget {
  const PanelEmbedScreen({super.key, required this.title, required this.url, this.embedded = false});
  final String title;
  final String url;

  /// Just the frame, with no heading, for use inside another page.
  final bool embedded;

  @override
  State<PanelEmbedScreen> createState() => _PanelEmbedScreenState();
}

class _PanelEmbedScreenState extends State<PanelEmbedScreen> {
  static int _counter = 0;
  String? _viewType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Signs the user into the panel (session cookie) before the frame or a new tab opens it.
  Future<String> _ssoUrl() => stackcpUrl(widget.url);

  Future<void> _load() async {
    final url = await _ssoUrl();
    if (!mounted) return;
    final type = 'stackcp-domain-frame-${_counter++}';
    ui_web.platformViewRegistry.registerViewFactory(type, (int _) {
      return web.HTMLIFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
    });
    setState(() => _viewType = type);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(
        decoration: BoxDecoration(border: Border.all(color: C.outlineVariant)),
        child: _viewType == null ? const Center(child: CircularProgressIndicator()) : HtmlElementView(key: ValueKey(_viewType), viewType: _viewType!),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(widget.title, style: T.headlineLg)),
          OutlinedButton.icon(
            onPressed: () async => web.window.open(await _ssoUrl(), '_blank'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in new tab'),
          ),
        ]),
        ValueListenableBuilder<String>(
          valueListenable: ssoStatus,
          builder: (_, v, _) => Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(v, style: T.bodySm)),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: C.outline)),
            child: _viewType == null
                ? const Center(child: CircularProgressIndicator())
                : HtmlElementView(key: ValueKey(_viewType), viewType: _viewType!),
          ),
        ),
      ]),
    );
  }
}
