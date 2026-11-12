import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = Size(200, 120);

Future<ui.Image> _backdrop() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(7);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      canvas.drawRect(
        Rect.fromLTWH(x * 2.0, y * 2.0, 2, 2),
        Paint()
          ..color = Color.fromARGB(
            255,
            random.nextInt(256),
            random.nextInt(256),
            random.nextInt(256),
          ),
      );
    }
  }
  return recorder.endRecording().toImage(128, 128);
}

Future<Uint8List> _draw(
  ui.FragmentProgram program,
  ui.Image backdrop,
  List<double> uniforms,
) async {
  final shader = program.fragmentShader()..setImageSampler(0, backdrop);
  for (final (index, value) in uniforms.indexed) {
    shader.setFloat(index, value);
  }
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & _size, Paint()..shader = shader);
  final image = await recorder.endRecording().toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final bytes = await image.toByteData();
  image.dispose();
  shader.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the flat shader draws a pane that only frosts as the full one does',
    () async {
      final full = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      final flat = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass_flat.frag',
      );
      final backdrop = await _backdrop();
      for (final (frost, held, contrast, glow) in [
        (24.0, 14.0, -0.4, 0.0),
        (24.0, 14.0, 0.4, 0.16),
        (3.0, 0.5, -0.4, 0.0),
        (6.0, 2.0, 0.0, 0.0),
      ]) {
        final reading = <double>[
          128, 128, 0, 0, 1, 1, // uSize, uFrame
          -10, -6, 1.6, 1.6, 0.5, 0.5, 127.5, 127.5, // uSample, uClamp
          1 / 2.75, held, // uTexels
        ];
        const veil = <double>[0.1, 0.12, 0.15, 0.2];
        final shape = <double>[_size.width, _size.height, 0, frost];
        const optics = <double>[0, 1.6, 1];
        const tint = <double>[0.12, 0.13, 0.16, 0.45];
        final glowing = <double>[100, 60, glow, contrast, 30, 0];
        final expected = await _draw(full, backdrop, [
          ...reading,
          ...List.filled(9, 0.0), // haze
          ...veil,
          ...shape,
          ...List.filled(52, 0.0), // corners and their curves
          ...optics,
          ...tint,
          0, 1.3, 0, // light
          ...glowing,
          ...List.filled(180, 0.0), // edge, rim, outline, shine, pills
        ]);
        final actual = await _draw(flat, backdrop, [
          ...reading,
          ...veil,
          ...shape,
          ...optics,
          ...tint,
          ...glowing,
        ]);

        expect(actual, expected, reason: 'frost $frost, contrast $contrast');
      }
      backdrop.dispose();
    },
  );
}
