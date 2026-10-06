import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Upper eyelid landmarks, measured in the original artwork's coordinates.
class EyeLid {
  const EyeLid(this.patch, this.heights);
  final Rect patch;
  final List<double> heights;
}

/// Cropped, pre-rendered textures with eyelid-aligned interpolation.
/// The iris and lashes come from the artwork, rather than a drawn mask.
class EyeMotion {
  EyeMotion._(this._images, this._shaders, this.atlas, this.lids, this.stops);
  final List<ui.Image> _images;
  final List<ui.ImageShader> _shaders;
  final Rect atlas;
  final List<EyeLid> lids;
  final List<double> stops;
  int get frameCount => _images.length;

  static const homeLids = <EyeLid>[
    EyeLid(Rect.fromLTWH(1040, 340, 112, 82), [397, 385, 375, 370, 364]),
    EyeLid(Rect.fromLTWH(1200, 305, 112, 90), [366, 357, 350, 344, 340]),
  ];
  static const splashLids = <EyeLid>[
    // The old half-open asset is almost identical to the quarter-open pose.
    // Skip that duplicate so it cannot make the eyelid stop halfway through.
    EyeLid(Rect.fromLTWH(674, 245, 104, 98), [298, 293, 281, 274]),
  ];

  static Future<EyeMotion> prepareHome(List<ui.Image> images) {
    if (images.length != 5) {
      throw ArgumentError('Five home eye poses required');
    }
    return _prepare(images, const Size(1672, 941), homeLids, const [
      0.0,
      0.35,
      0.64,
      0.82,
      1.0,
    ]);
  }

  static Future<EyeMotion> prepareSplash(List<ui.Image> images) {
    if (images.length != 5) {
      throw ArgumentError('Five splash eye poses required');
    }
    return _prepare(
      [images[0], images[1], images[3], images[4]],
      const Size(1200, 800),
      splashLids,
      const [0.0, 0.20, 0.68, 1.0],
    );
  }

  static Future<EyeMotion> _prepare(
    List<ui.Image> sources,
    Size logical,
    List<EyeLid> lids,
    List<double> stops,
  ) async {
    final atlas = lids
        .map((l) => l.patch)
        .reduce((a, b) => a.expandToInclude(b));
    final images = <ui.Image>[];
    final shaders = <ui.ImageShader>[];
    try {
      for (final source in sources) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          source,
          Rect.fromLTWH(
            atlas.left * source.width / logical.width,
            atlas.top * source.height / logical.height,
            atlas.width * source.width / logical.width,
            atlas.height * source.height / logical.height,
          ),
          Rect.fromLTWH(0, 0, atlas.width, atlas.height),
          Paint()..filterQuality = FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        try {
          images.add(
            await picture.toImage(atlas.width.ceil(), atlas.height.ceil()),
          );
        } finally {
          picture.dispose();
        }
        shaders.add(
          ui.ImageShader(
            images.last,
            TileMode.clamp,
            TileMode.clamp,
            Float64List.fromList([
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
            ]),
            filterQuality: FilterQuality.medium,
          ),
        );
      }
      return EyeMotion._(images, shaders, atlas, lids, stops);
    } catch (_) {
      for (final shader in shaders) {
        shader.dispose();
      }
      for (final image in images) {
        image.dispose();
      }
      rethrow;
    }
  }

  /// One continuous lid location shared by both adjacent texture samples.
  double lidHeight(EyeLid lid, double opening) {
    final (index, mix) = _segment(opening);
    double slope(int i) =>
        (lid.heights[i + 1] - lid.heights[i]) / (stops[i + 1] - stops[i]);
    double tangent(int i) {
      if (i == 0) return slope(0);
      if (i == stops.length - 1) return slope(i - 1);
      final a = slope(i - 1);
      final b = slope(i);
      if (a * b <= 0) return 0;
      final prevWidth = stops[i] - stops[i - 1];
      final nextWidth = stops[i + 1] - stops[i];
      final w1 = 2 * nextWidth + prevWidth;
      final w2 = nextWidth + 2 * prevWidth;
      return (w1 + w2) / (w1 / a + w2 / b);
    }

    // Monotone Hermite interpolation: position AND velocity match at poses.
    final t2 = mix * mix;
    final t3 = t2 * mix;
    final width = stops[index + 1] - stops[index];
    return (2 * t3 - 3 * t2 + 1) * lid.heights[index] +
        (t3 - 2 * t2 + mix) * width * tangent(index) +
        (-2 * t3 + 3 * t2) * lid.heights[index + 1] +
        (t3 - t2) * width * tangent(index + 1);
  }

  (int, double) _segment(double opening) {
    final p = opening.clamp(0.0, 1.0);
    var i = 0;
    while (i < stops.length - 2 && p >= stops[i + 1]) {
      i++;
    }
    return (i, (p - stops[i]) / (stops[i + 1] - stops[i]));
  }

  void paint(Canvas canvas, double opening) {
    final (index, mix) = _segment(opening);
    for (final lid in lids) {
      final target = lidHeight(lid, opening);
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(lid.patch, const Radius.circular(12)),
      );
      _draw(canvas, lid, index, target, 1);
      if (mix > 0) {
        _draw(canvas, lid, index + 1, target, mix);
      }
      canvas.restore();
    }
  }

  void _draw(
    Canvas canvas,
    EyeLid lid,
    int frame,
    double target,
    double alpha,
  ) {
    final patch = lid.patch;
    final positions = <Offset>[];
    final tex = <Offset>[];
    const columns = 16;
    // Preserve the surrounding hair/skin and move the lash-bearing lid strip.
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col <= columns; col++) {
        final u = col / columns;
        final x = patch.left + patch.width * u;
        final edge = (4 * u * (1 - u));
        final from = lid.heights[frame];
        final to = from + (target - from) * edge;
        final sy = switch (row) {
          0 => patch.top,
          1 => from - 4,
          2 => from + 4,
          _ => patch.bottom,
        };
        final dy = switch (row) {
          0 => patch.top,
          1 => to - 4,
          2 => to + 4,
          _ => patch.bottom,
        };
        positions.add(Offset(x, dy));
        tex.add(Offset(x - atlas.left, sy - atlas.top));
      }
    }
    final indices = <int>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < columns; col++) {
        final a = row * (columns + 1) + col;
        final b = a + columns + 1;
        indices.addAll([a, a + 1, b, a + 1, b + 1, b]);
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: tex,
      indices: indices,
    );
    try {
      canvas.drawVertices(
        vertices,
        BlendMode.srcOver,
        Paint()
          ..shader = _shaders[frame]
          ..color = Color.fromRGBO(255, 255, 255, alpha)
          ..filterQuality = FilterQuality.medium,
      );
    } finally {
      vertices.dispose();
    }
  }

  void dispose() {
    for (final shader in _shaders) {
      shader.dispose();
    }
    for (final image in _images) {
      image.dispose();
    }
  }
}
