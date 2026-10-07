import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme.dart';

/// Test page: loads a URL (e.g. the white-labelled StackCP) in an iframe.
/// If the frame stays blank, the target site is blocking framing
/// (X-Frame-Options / CSP frame-ancestors) — check DevTools console.
class HostingEmbedTestScreen extends StatefulWidget {
  const HostingEmbedTestScreen({super.key});

  @override
  State<HostingEmbedTestScreen> createState() => _HostingEmbedTestScreenState();
}

class _HostingEmbedTestScreenState extends State<HostingEmbedTestScreen> {
  final _url = TextEditingController(text: 'https://cp.biznesthub.net/domain-search');
  String? _viewType;
  int _counter = 0;

  void _load() {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    final type = 'stackcp-frame-${_counter++}';
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
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hosting embed test', style: T.headlineLg),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'URL to embed', border: OutlineInputBorder()),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _load, child: const Text('Load')),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => web.window.open(_url.text.trim(), '_blank'),
            child: const Text('Open in new tab'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Blank frame or "refused to connect"? The site blocks iframes — use "Open in new tab" or the 20i API instead.',
          style: T.bodyMd.copyWith(color: C.secondary),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: C.outline)),
            child: _viewType == null
                ? const Center(child: Text('Press Load'))
                : HtmlElementView(key: ValueKey(_viewType), viewType: _viewType!),
          ),
        ),
      ]),
    );
  }
}
