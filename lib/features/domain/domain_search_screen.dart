import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme.dart';

/// Embeds the white-labelled 20i control panel (StackCP) in an iframe.
/// Set [_panelUrl] to your brand domain once configured (e.g. https://cp.yourdomain.com/).
/// If the frame is blank, the panel is blocking framing — use the new-tab button.
class DomainSearchScreen extends StatefulWidget {
  const DomainSearchScreen({super.key});

  @override
  State<DomainSearchScreen> createState() => _DomainSearchScreenState();
}

class _DomainSearchScreenState extends State<DomainSearchScreen> {
  // Local proxy (run: node tools/stackcp_proxy.js) that strips X-Frame-Options from stackcp.com.
  // Override at build time: flutter build web --dart-define=PANEL_URL=https://cp.yourdomain.com/
  static const _panelUrl = String.fromEnvironment('PANEL_URL', defaultValue: 'https://stackcp.zackloh.dev/');
  static const _viewType = 'stackcp-domain-frame';
  static bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
        return web.HTMLIFrameElement()
          ..src = _panelUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
      });
      _registered = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Domains & Hosting', style: T.headlineLg)),
          OutlinedButton.icon(
            onPressed: () => web.window.open(_panelUrl, '_blank'),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open in new tab'),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: C.outline)),
            child: const HtmlElementView(viewType: _viewType),
          ),
        ),
      ]),
    );
  }
}
