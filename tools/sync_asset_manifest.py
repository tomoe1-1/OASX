#!/usr/bin/env python
"""同步 flutter_assets 下的 AssetManifest.bin。

## 为什么需要这个脚本

`AssetManifest.bin` 是 `flutter build` 按 `pubspec.yaml` 的 `assets:` 段生成的。
本机因为全局禁止 Dart 创建子进程，走的是手工构建链（`tools/build_manual.sh`），
**没有这一步**。

⚠️ 两个关键事实（踩过坑）：

1. **Flutter 引擎只读 `AssetManifest.bin`**（见
   `flutter/lib/src/services/asset_manifest.dart` 的 `_kAssetManifestFilename`）。
   旁边的 `AssetManifest.json` 是**旧格式残留，引擎根本不看**。所以只补
   `.json` 是无效劳动 —— `Image.asset` 仍无法解析资源变体。
2. 找不到时本项目 `HomeBackdrop._load()` 走了静默降级（设计如此，底衬不该
   因为读不到图就阻塞界面），于是**画面上什么都不出现、也没有任何报错**。
   这是「改了代码看不到效果」最难查的一类。

## .bin 的字节格式

生成点在
`flutter_tools/lib/src/asset.dart` 的 `_assetManifestBin`：
`const StandardMessageCodec().encodeMessage(result)`。

格式必须与 `packages/flutter/lib/src/services/message_codecs.dart` 一致：
String/List/Map 使用 0x07/0x0c/0x0d 标签和独立长度，长长度按小端编码。
旧脚本误用了 MessagePack/hybrid 格式，导致 Image.asset 不显示。
同步时可读取旧格式并迁移；--verify 只接受标准格式。

## 本项目实际结构

    Map<String, List<Map<String, Object?>>>
      └─ 资源键 → 变体列表 → 每项 {'asset': <路径>}

## 用法

    python tools/sync_asset_manifest.py <flutter_assets 目录>
    python tools/sync_asset_manifest.py --verify <flutter_assets 目录>
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "src" / "pubspec.yaml"
SRC = ROOT / "src"


# ---------------------------------------------------------------- pubspec 解析


def parse_asset_entries(pubspec: Path) -> list[str]:
    """从 pubspec 的 `flutter: assets:` 段取出资源条目（原样，不展开目录）。"""
    entries: list[str] = []
    in_flutter = False
    in_assets = False
    for raw in pubspec.read_text(encoding="utf-8").splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())

        if indent == 0:
            in_flutter = line.startswith("flutter:")
            in_assets = False
            continue
        if not in_flutter:
            continue

        stripped = line.strip()
        if stripped.startswith("assets:"):
            in_assets = True
            continue
        if in_assets:
            if stripped.startswith("- "):
                entries.append(stripped[2:].strip())
            elif stripped.endswith(":") or indent <= 2:
                in_assets = False
    return entries


def expand(entries: list[str]) -> list[str]:
    """把 `assets/xxx/` 目录条目展开成实际文件列表。"""
    out: list[str] = []
    for e in entries:
        if e.endswith("/"):
            d = SRC / e
            if not d.is_dir():
                print(f"  跳过（目录不存在）：{e}", file=sys.stderr)
                continue
            for f in sorted(d.rglob("*")):
                if f.is_file():
                    out.append(str(f.relative_to(SRC)).replace("\\", "/"))
        else:
            if (SRC / e).is_file():
                out.append(e)
            else:
                print(f"  跳过（文件不存在）：{e}", file=sys.stderr)
    return out


# ------------------------------------------------------- StandardMessageCodec
#
# 以下旧格式 Reader 仅用于迁移此前误写的清单。

_TAG_MAP_BASE = 0x80
_TAG_LIST_BASE = 0x90
_TAG_STR_SHORT_BASE = 0xA0  # 长度内联，0..31
_TAG_STR_LEN8 = 0xD9        # 后跟 1 字节长度，32..255
_TAG_LIST_LARGE = 0x0C      # StandardMessageCodec 标准大 List：前面写 size
_TAG_MAP_LARGE = 0x0D       # StandardMessageCodec 标准大 Map：前面写 size


class _Reader:
    def __init__(self, data: bytes) -> None:
        self.d = data
        self.i = 0

    def _read_size(self) -> int:
        b = self.d[self.i]
        self.i += 1
        if b < 0xFE:
            return b
        if b == 0xFE:
            v = int.from_bytes(self.d[self.i:self.i + 2], "big")
            self.i += 2
            return v
        if b == 0xFF:
            v = int.from_bytes(self.d[self.i:self.i + 4], "big")
            self.i += 4
            return v
        raise ValueError(f"非法 size 前缀 0x{b:02x}")

    def value(self):
        if self.i >= len(self.d):
            raise ValueError("读到结尾但仍在解析")
        t = self.d[self.i]
        self.i += 1

        if _TAG_MAP_BASE <= t <= _TAG_MAP_BASE + 0x0F:
            return {self.value(): self.value() for _ in range(t & 0x0F)}

        if t == _TAG_MAP_LARGE:
            return {self.value(): self.value() for _ in range(self._read_size())}

        if _TAG_LIST_BASE <= t <= _TAG_LIST_BASE + 0x0F:
            return [self.value() for _ in range(t & 0x0F)]

        if t == _TAG_LIST_LARGE:
            return [self.value() for _ in range(self._read_size())]

        if _TAG_STR_SHORT_BASE <= t <= _TAG_STR_SHORT_BASE + 0x1F:
            n = t - _TAG_STR_SHORT_BASE
            s = self.d[self.i:self.i + n].decode("utf-8")
            self.i += n
            return s

        if t == _TAG_STR_LEN8:
            n = self.d[self.i]
            self.i += 1
            s = self.d[self.i:self.i + n].decode("utf-8")
            self.i += n
            return s

        raise ValueError(f"未支持的 tag 0x{t:02x} @ {self.i - 1}")


_LegacyReader = _Reader


class _Reader:
    """Flutter StandardMessageCodec, matching services/message_codecs.dart."""

    def __init__(self, data: bytes) -> None:
        self.d = data
        self.i = 0

    def take(self, n: int) -> bytes:
        end = self.i + n
        if end > len(self.d):
            raise ValueError("Truncated StandardMessageCodec value")
        value = self.d[self.i:end]
        self.i = end
        return value

    def size(self) -> int:
        first = self.take(1)[0]
        if first < 254:
            return first
        return int.from_bytes(self.take(2 if first == 254 else 4), "little")

    def value(self):
        tag = self.take(1)[0]
        if tag == 0:
            return None
        if tag in (1, 2):
            return tag == 1
        if tag in (3, 4):
            return int.from_bytes(self.take(4 if tag == 3 else 8), "little", signed=True)
        if tag == 6:
            self.take((-self.i) % 8)
            return struct.unpack("<d", self.take(8))[0]
        if tag == 7:
            return self.take(self.size()).decode("utf-8")
        if tag == 12:
            return [self.value() for _ in range(self.size())]
        if tag == 13:
            return {self.value(): self.value() for _ in range(self.size())}
        raise ValueError(f"Unsupported StandardMessageCodec tag {tag}")


class _Writer:
    def __init__(self) -> None:
        self.b = bytearray()

    def _write_size(self, n: int) -> None:
        if n < 0xFE:
            self.b.append(n)
        elif n <= 0xFFFF:
            self.b.append(0xFE)
            self.b.extend(n.to_bytes(2, "little"))
        else:
            self.b.append(0xFF)
            self.b.extend(n.to_bytes(4, "little"))

    def string(self, s: str) -> None:
        raw = s.encode("utf-8")
        n = len(raw)
        self.b.append(7)
        self._write_size(n)
        self.b.extend(raw)

    def list_(self, items: list) -> None:
        self.b.append(12)
        self._write_size(len(items))
        for v in items:
            self.value(v)

    def map_(self, m: dict) -> None:
        self.b.append(13)
        self._write_size(len(m))
        for k, v in m.items():
            self.value(k)
            self.value(v)

    def value(self, v) -> None:
        if v is None:
            self.b.append(0)
        elif isinstance(v, bool):
            self.b.append(1 if v else 2)
        elif isinstance(v, float):
            self.b.append(6)
            self.b.extend(b"\x00" * ((-len(self.b)) % 8))
            self.b.extend(struct.pack("<d", v))
        elif isinstance(v, int):
            width = 4 if -(2**31) <= v < 2**31 else 8
            self.b.append(3 if width == 4 else 4)
            self.b.extend(v.to_bytes(width, "little", signed=True))
        elif isinstance(v, str):
            self.string(v)
        elif isinstance(v, dict):
            self.map_(v)
        elif isinstance(v, list):
            self.list_(v)
        else:
            raise TypeError(f"未支持的类型 {type(v)}")


def encode(obj) -> bytes:
    w = _Writer()
    w.value(obj)
    return bytes(w.b)


def decode(data: bytes):
    r = _Reader(data)
    obj = r.value()
    if r.i != len(data):
        raise ValueError(f"解析后仍有 {len(data) - r.i} 字节未消费")
    return obj


# ------------------------------------------------------------------- 主流程


def sync_bin(assets_dir: Path, keys: list[str]) -> list[str]:
    p = assets_dir / "AssetManifest.bin"
    if not p.is_file():
        print(f"错误：{p} 不存在", file=sys.stderr)
        return []

    raw = p.read_bytes()
    try:
        data = decode(raw)
    except (ValueError, IndexError, UnicodeDecodeError):
        # 旧手工脚本曾误写 MessagePack/hybrid；仅用于一次性迁移。
        legacy = _LegacyReader(raw)
        data = legacy.value()
        if legacy.i != len(raw):
            raise ValueError("Legacy manifest contains trailing bytes")
        print("Migrating legacy asset manifest to Flutter StandardMessageCodec")
    if not isinstance(data, dict):
        raise ValueError("AssetManifest.bin 顶层不是 Map")

    added = [k for k in keys if k not in data]
    for k in added:
        # 变体结构：只有一个 {'asset': <同路径>} 的默认变体
        data[k] = [{"asset": k}]

    encoded = encode(data)
    if encoded != raw:
        p.write_bytes(encoded)
    return added


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verify_only = "--verify" in sys.argv

    if len(args) != 1:
        print(__doc__)
        return 2
    assets_dir = Path(args[0])
    if not assets_dir.is_dir():
        print(f"错误：{assets_dir} 不是目录", file=sys.stderr)
        return 1

    keys = expand(parse_asset_entries(PUBSPEC))
    if not keys:
        print("错误：pubspec 里没解析出任何资源条目", file=sys.stderr)
        return 1

    if verify_only:
        data = decode((assets_dir / "AssetManifest.bin").read_bytes())
        missing = [k for k in keys if k not in data]
        if missing:
            print(f"✗ AssetManifest.bin 缺少 {len(missing)} 条：")
            for k in missing:
                print(f"  - {k}")
            return 1
        # 注意区分两个数字：
        #   keys  = pubspec `assets:` 段显式声明的条目（资源图）
        #   len(data) = manifest 实际登记的全部条目（还含字体、包资源等
        #               由构建链接管写入的项，不是本脚本的职责）
        print(
            f"✓ AssetManifest.bin 已登记 pubspec 声明的全部 {len(keys)} 条资源"
            f"（文件共 {len(data)} 条，余下为字体/包资源）"
        )
        return 0

    added = sync_bin(assets_dir, keys)
    if not added:
        # 与 --verify 同样的口径：区分「pubspec 声明的条目」和「manifest 总条目」，
        # 避免「8 条」被误读成文件只有 8 条（实际含字体/包资源会更多）。
        total = len(decode((assets_dir / "AssetManifest.bin").read_bytes()))
        print(
            f"AssetManifest.bin 已是最新"
            f"（pubspec 声明 {len(keys)} 条全部登记，文件共 {total} 条）"
        )
    else:
        print(f"AssetManifest.bin 新增 {len(added)} 条：")
        for k in added:
            print(f"  + {k}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
