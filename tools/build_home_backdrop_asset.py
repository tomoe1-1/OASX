#!/usr/bin/env python
"""从参考视频的一帧生成主界面底衬素材（1480×2240）。

## 为什么要有这个脚本

底衬素材不是「裁一张图压暗」那么简单 —— 它要同时满足三个互相拉扯的约束：

1. **可读性**：素材透过多层半透明面板后，日志区次级文字仍要 ≥ 4.5:1
2. **可见性**：压太暗就白放一张图，看不出任何氛围
3. **无硬边**：素材与窗口背景融合，不能出现肉眼可辨的矩形/椭圆边界

调这三个参数很容易按下葫芦浮起瓢，所以固定成脚本，每次改完必须
用 `render_home_backdrop.py` 复核四档分辨率。

## ⚠️ 踩过的坑：不要用「椭圆距离场」做边缘羽化

上一版用 `r = sqrt(nx² + ny²)` + 线性映射做羽化，结果：

- 素材是 740×1120 的**竖构图**，归一化后 r=1 是一条**竖椭圆**
  （水平半径 370px，垂直半径 560px）
- 四角 r 全部 = 1.41 ⇒ `f = 0` ⇒ **完全变黑**
- 全图 **59.2%** 被压暗，只有中心 40.8% 保留原亮度
- 在深色界面上形成一块**肉眼可见的椭圆/矩形贴片**，用户直接看得出「这里黑了」

正确做法：**素材保持完整矩形**，只在最外侧 6% 做一次很轻的线性收边
（最低保留 55%，不是 0）。真正的边缘融合交给 Dart 侧已有的
`dstIn` 线性渐变（左 + 上下）—— 线性渐变不会形成块状边界。

## ⚠️ 亮度基准：43 不是随便定的

素材均值直接决定可读性。实测（hrat=1.6 / ax=0.95 / α=0.80 / op=0.80，
1280×800 是最紧的一档）：

| 素材均值 | 次级文字最差 | |
|---|---|---|
| 65.6 | 2.95:1 | ✗ |
| 56.2 | 3.50:1 | ✗ |
| 48.6 | 4.08:1 | ✗ |
| **42.9** | **4.52:1** | ✓ |
| 37.3 | 5.01:1 | ✓ |

所以 `TARGET_BRIGHTNESS = 43.0` 是实测下限附近的值，不是审美选择。
往上调必须重跑复核脚本，否则会悄悄压破 AA。

## 处理链

1. 裁切：原帧 `(620, 40, 990, 600)` —— 370×560，比例 0.661，
   刚好等于 740/1120。含蓝发主体 + 青瞳 + 蝴蝶结（蓝色是科技感来源，
   只裁眼睛会丢掉它）。
2. 白平衡：**只对高光（top 3%）** 做，并限幅 0.9–1.15。
   整幅灰世界白平衡会把蓝发拉成灰蓝、整体蒙雾。
3. 压暗到 `TARGET_BRIGHTNESS`。
4. 保留色相：接近灰的像素轻微冷推（R×0.96, B×1.06）——
   靠**色相**而非亮度营造氛围，低亮度下仍有辨识度。
5. 中值滤波 3px 降噪（小图上做，噪声未放大）→ LANCZOS 一步放大到
   成品尺寸 → 保守 USM 锐化补回边缘（见 OUT_SIZE 注释）。
6. 线性边缘收边（最外 6%，最低 55%）。

## 用法

    python tools/build_home_backdrop_asset.py <原帧路径>
    python tools/build_home_backdrop_asset.py            # 用默认路径
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

# ---- 与 render_home_backdrop.py / home_backdrop.dart 对齐的常量 ----

#: 裁切框（左, 上, 右, 下）。比例必须 = 740/1120 ≈ 0.6607
CROP_BOX = (620, 40, 990, 600)

#: 成品尺寸。必须与 home_backdrop.dart 的 _kArtWidth / _kArtHeight 一致。
#:
#: 1480×2240 = 原生裁切 370×560 的 **4 倍**。取这么大不是「以为能变清晰」，
#: 而是为了**减少重采样次数**：
#:
#:   源视频物理上限 = 1280×720（HEVC，已用 ffprobe 确认）→ 少女区域
#:   原生只有 370×560 像素。真实细节就这么多，再怎么放大也不会变多。
#:
#:   但「放大几次」影响很大。若素材只存 740×1120，在 2560×1440 上
#:   显示尺寸约 1522×2304，运行时还要再放大 2.06×（相对原生 4.11×），
#:   两次重采样把仅有的细节又磨掉一层。
#:
#:   直接存 1480×2240 后：
#:     2560×1440 → 放大 1.03×（≈1:1，不额外损失）
#:     1440×900  → 缩小 0.64×（缩小反而更锐利）
#:     1280×800  → 缩小 0.57×
#:   即高分屏不再放大，小屏靠缩小获得锐度 —— 这是 720p 源下的最优解。
OUT_SIZE = (1480, 2240)

#: 素材亮度基准。见文件头「亮度基准」表 —— 往上调必须重跑复核脚本
TARGET_BRIGHTNESS = 43.0

#: 边缘收边的宽度（占边长比例）与最低保留系数
EDGE_FRAC = 0.06
EDGE_MIN = 0.55

DEFAULT_SOURCE = Path(r"C:\Users\12296\AppData\Local\Temp\vf\a32.png")

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "src" / "assets" / "images" / "main_bg_muse.jpg"
CHECK_PATH = ROOT / "tools" / "preview" / "asset_check.png"


def _white_balance_highlights(a: np.ndarray) -> np.ndarray:
    """只对高光做白平衡。

    整幅灰世界白平衡的副作用：画面像蒙了层雾，青色被闷掉，蓝发变灰蓝。
    只取最亮 3% 做基准并限幅，既校正了拍屏偏色，又保住色相。
    """
    lum = a.mean(axis=2)
    mask = lum >= np.percentile(lum, 97)
    if mask.sum() <= 50:
        return a
    ref = a[mask].mean(axis=0)
    gain = np.clip(ref.mean() / np.maximum(ref, 1e-6), 0.9, 1.15)
    return np.clip(a * gain, 0, 255)


def _keep_hue(a: np.ndarray) -> np.ndarray:
    """把接近灰的像素轻微冷推，保住「科技蓝青」的调性。"""
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    pale = ((mx - mn) / np.maximum(mx, 1e-6)) < 0.12
    out = a.copy()
    out[:, :, 0] = np.where(pale, out[:, :, 0] * 0.96, out[:, :, 0])
    out[:, :, 2] = np.where(pale, np.minimum(out[:, :, 2] * 1.06, 255), out[:, :, 2])
    return np.clip(out, 0, 255)


def _soft_edges(a: np.ndarray) -> np.ndarray:
    """最外侧窄带的线性收边。

    注意是**线性**不是椭圆 —— 见文件头「踩过的坑」。
    """
    h, w = a.shape[:2]
    ex = max(1, int(w * EDGE_FRAC))
    ey = max(1, int(h * EDGE_FRAC))

    fx = np.ones(w, dtype=np.float32)
    fx[:ex] = np.linspace(EDGE_MIN, 1.0, ex)
    fx[-ex:] = np.linspace(1.0, EDGE_MIN, ex)

    fy = np.ones(h, dtype=np.float32)
    fy[:ey] = np.linspace(EDGE_MIN, 1.0, ey)
    fy[-ey:] = np.linspace(1.0, EDGE_MIN, ey)

    return np.clip(a * np.outer(fy, fx)[:, :, None], 0, 255)


def build(source: Path, out_path: Path, check_path: Path | None = None) -> Image.Image:
    src = Image.open(source).convert("RGB")
    cropped = src.crop(CROP_BOX)

    ratio = cropped.width / cropped.height
    want = OUT_SIZE[0] / OUT_SIZE[1]
    if abs(ratio - want) > 0.01:
        raise ValueError(
            f"裁切比例 {ratio:.3f} 与目标 {want:.3f} 不符，会把画面拉变形。"
            f"请调整 CROP_BOX。"
        )

    a = np.asarray(cropped).astype(np.float32)
    a = _white_balance_highlights(a)
    a = np.clip(a * (TARGET_BRIGHTNESS / max(a.mean(), 1e-6)), 0, 255)
    a = _keep_hue(a)

    img = Image.fromarray(a.astype(np.uint8))
    # 先在小图上降噪（此时噪声还没被放大）
    img = img.filter(ImageFilter.MedianFilter(3))
    img = img.resize(OUT_SIZE, Image.LANCZOS)
    # 放大必然损失边缘锐度（原生只有 370×560）。用很轻的 USM 把边缘对比
    # 找回来一点。参数刻意保守 —— 底衬是氛围元素，锐过头会出现振铃白边，
    # 在深色界面上比「糊」更难看。
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=45, threshold=3))

    arr = _soft_edges(np.asarray(img).astype(np.float32))
    final = Image.fromarray(arr.astype(np.uint8))
    final.save(out_path, quality=92)

    print(f"裁切 {cropped.size} (比例 {ratio:.3f})")
    print(f"成品 {final.size}  均值 {arr.mean():.1f}  "
          f"（目标 {TARGET_BRIGHTNESS}）")
    print(f"边缘收边：最外 {int(OUT_SIZE[0] * EDGE_FRAC)}px / "
          f"{int(OUT_SIZE[1] * EDGE_FRAC)}px，最低保留 "
          f"{EDGE_MIN * 100:.0f}%（线性，非椭圆）")
    print(f"已写入 {out_path}")

    if check_path is not None:
        check_path.parent.mkdir(parents=True, exist_ok=True)
        final.save(check_path)

    return final


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not src.is_file():
        print(f"错误：原帧不存在 {src}", file=sys.stderr)
        print("用法：python tools/build_home_backdrop_asset.py <原帧路径>",
              file=sys.stderr)
        return 1

    build(src, OUT_PATH, CHECK_PATH)
    print()
    print("下一步必须复核可读性：")
    print("  python tools/render_home_backdrop.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
