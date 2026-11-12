import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/qr_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

const _link = 'flclashx://install-config?url=https%3A%2F%2Fexample.com%2Fsub';

RgbaImage _render(String text, {bool inverted = false, int scale = 6}) {
  final qr = QrImage(QrCode(payload: QrPayload.fromString(text)));
  const quiet = 4;
  final side = (qr.moduleCount + quiet * 2) * scale;
  final rgba = Uint8List(side * side * 4);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final row = y ~/ scale - quiet;
      final col = x ~/ scale - quiet;
      final inside =
          row >= 0 && col >= 0 && row < qr.moduleCount && col < qr.moduleCount;
      final dark = inside && qr.isDark(row, col);
      final value = dark != inverted ? 0 : 255;
      final o = (y * side + x) * 4;
      rgba
        ..[o] = value
        ..[o + 1] = value
        ..[o + 2] = value
        ..[o + 3] = 255;
    }
  }
  return (rgba: rgba, width: side, height: side);
}

void main() {
  test('reads a QR code from raw pixels', () {
    expect(qrCodesInRgba(_render(_link)), [_link]);
  });

  test('reads a light QR code on a dark background', () {
    expect(qrCodesInRgba(_render(_link, inverted: true)), [_link]);
  });

  testWidgets('reads a QR code from a photo larger than it decodes', (
    tester,
  ) async {
    final codes = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('qr_image_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/code.png');
      await file.writeAsBytes(await _png(_render(_link, scale: 64)));
      return qrCodesInImageFile(file.path);
    });
    expect(codes, [_link]);
  });

  test('finds nothing in a picture without a code', () {
    final blank = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 255);
    expect(qrCodesInRgba((rgba: blank, width: 64, height: 64)), isEmpty);
  });
}

Future<Uint8List> _png(RgbaImage image) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    image.rgba,
    image.width,
    image.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final decoded = await completer.future;
  final png = await decoded.toByteData(format: ui.ImageByteFormat.png);
  decoded.dispose();
  return png!.buffer.asUint8List();
}
