import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 上一版（2.3.0）随包清单里登记的全部条目。
///
/// 2.4.0 只是往里加眼睑姿态图，**一条都不能丢** —— 丢一条的表现是
/// 某个页面静默变成空白/纯色，日志里没有任何报错（资源缺失只在
/// `rootBundle.load()` 抛异常时才可见，而底衬加载失败是降级的）。
const _kPreviousReleaseAssets = <String>[
  'assets/Lato-Regular.ttf',
  'assets/images/Icon-app.ico',
  'assets/images/Icon-app.png',
  'assets/images/main_bg_muse.jpg',
  'assets/images/main_bg_muse_ambient.jpg',
  'assets/images/main_bg_muse_anim.webp',
  'assets/images/main_bg_muse_front_full.png',
  'assets/release.txt',
  'assets/splash/girl_closed.jpg',
  'assets/splash/girl_closed_wire.png',
  'assets/splash/girl_closed_wire_extended.png',
  'assets/splash/girl_corner_repair.png',
  'assets/splash/girl_open.jpg',
  'assets/splash/girl_open_wire.png',
  'assets/splash/girl_open_wire_extended.png',
  'packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'packages/font_awesome_flutter/lib/fonts/fa-brands-400.ttf',
  'packages/font_awesome_flutter/lib/fonts/fa-regular-400.ttf',
  'packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf',
];

void main() {
  test('release manifest preserves all existing assets and eye poses', () {
    const codec = StandardMessageCodec();
    Map<Object?, Object?> read(String path) =>
        codec.decodeMessage(ByteData.sublistView(File(path).readAsBytesSync()))
            as Map<Object?, Object?>;
    // 随包目录就是「发布出去的那一份」，钉它而不是某个临时构建目录。
    const root = '../data/flutter_assets';
    final after = read('$root/AssetManifest.bin');
    for (final path in _kPreviousReleaseAssets) {
      expect(
        after[path],
        [
          {'asset': path},
        ],
        reason: path,
      );
    }
    final additions = <String>[
      'assets/images/main_bg_muse_front_closed.png',
      for (final name in ['quarter', 'half', 'three_quarter']) ...[
        'assets/splash/girl_eye_$name.png',
        'assets/images/main_bg_muse_front_eye_$name.png',
      ],
    ];
    // .json 是历史遗留格式（引擎只读 .bin），旧条目并不齐全，
    // 只要求本版新增的条目在里面 —— 保证两份清单同步生长。
    final json =
        jsonDecode(File('$root/AssetManifest.json').readAsStringSync()) as Map;
    for (final path in additions) {
      expect(
        after[path],
        [
          {'asset': path},
        ],
        reason: path,
      );
      expect(json[path], [path], reason: path);
      expect(File('$root/$path').lengthSync(), greaterThan(0), reason: path);
    }
  });
}
