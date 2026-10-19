import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class PickedImage {
  const PickedImage({required this.name, required this.bytes, required this.mimeType});
  final String name;
  final Uint8List bytes;
  final String mimeType;
}

/// Opens the browser's file dialog for images. Returns an empty list when the dialog is cancelled.
/// Uses a plain <input type="file">, so it needs no plugin and works the same on every browser.
Future<List<PickedImage>> pickImages({bool multiple = false}) {
  final done = Completer<List<PickedImage>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..multiple = multiple;

  Future<void> read() async {
    try {
      final files = input.files;
      final out = <PickedImage>[];
      if (files != null) {
        for (var i = 0; i < files.length; i++) {
          final f = files.item(i)!;
          final buffer = await f.arrayBuffer().toDart;
          out.add(PickedImage(name: f.name, bytes: buffer.toDart.asUint8List(), mimeType: f.type));
        }
      }
      if (!done.isCompleted) done.complete(out);
    } catch (e, st) {
      if (!done.isCompleted) done.completeError(e, st);
    }
  }

  // JS callbacks must be synchronous, so the async work lives in read().
  input.addEventListener('change', ((web.Event _) {
    read();
  }).toJS);
  input.addEventListener('cancel', ((web.Event _) {
    if (!done.isCompleted) done.complete(const []);
  }).toJS);

  input.click();
  return done.future;
}
