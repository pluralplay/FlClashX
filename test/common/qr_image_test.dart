import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fl_clash/common/link.dart';
import 'package:fl_clash/common/qr_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

Future<Uint8List> renderQr(String text, {bool transparent = false}) async {
  final code = QrImage(QrCode(payload: QrPayload.fromString(text)));
  const scale = 8;
  const quietZone = 4;
  final dimension = (code.moduleCount + 2 * quietZone) * scale;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(
    transparent ? const ui.Color(0x00000000) : const ui.Color(0xffffffff),
    ui.BlendMode.src,
  );
  final paint = ui.Paint()..color = const ui.Color(0xff000000);
  for (var y = 0; y < code.moduleCount; y++) {
    for (var x = 0; x < code.moduleCount; x++) {
      if (!code.isDark(y, x)) continue;
      canvas.drawRect(
        ui.Rect.fromLTWH(
          (x + quietZone) * scale.toDouble(),
          (y + quietZone) * scale.toDouble(),
          scale.toDouble(),
          scale.toDouble(),
        ),
        paint,
      );
    }
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(dimension, dimension);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('читает ссылку подписки из PNG', () async {
    const url = 'https://example.org/subscription?id=12345';
    final image = await renderQr(url);

    expect(await decodeQrImage(image), url);
    expect(profileUrlFromQrCodes([await decodeQrImage(image)]), url);
  });

  test('читает QR с прозрачным фоном', () async {
    const url = 'https://example.org/subscription';
    expect(await decodeQrImage(await renderQr(url, transparent: true)), url);
  });

  test('отклоняет изображение без QR', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(256, 256);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(await decodeQrImage(bytes!.buffer.asUint8List()), isNull);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  });

  test('не выбрасывает ошибку на повреждённом файле', () async {
    expect(await decodeQrImage(Uint8List.fromList([1, 2, 3])), isNull);
    expect(await decodeQrImage(Uint8List(0)), isNull);
  });

  test('отклоняет файл больше установленного лимита', () async {
    expect(await decodeQrImage(Uint8List(20 * 1024 * 1024 + 1)), isNull);
  });
}
