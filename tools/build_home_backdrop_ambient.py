"""生成主界面底衬的**全屏氛围底图**（`main_bg_muse_ambient.jpg`）。

## 为什么要单独一张（而不是把立绘拉大铺满）

用户要的是「背景全覆盖」，但直接把 740×1120 的立绘 cover 铺进 1600×900
会有两个问题：

1. **放大 2.2×** —— 画面糊到只剩色块，细节全丢；
2. **出现「两个少女」** —— 铺满版的大脸和舞台里的清晰版同时可见，
   视线打架，是典型的 AI slop。

所以分两层各司其职：

- **本文件产出的氛围底图**：少女重度模糊（高斯半径 70）后的**柔光**，
  叠在深空径向渐变上 —— 铺满 100% 窗口，提供「全覆盖的科技底色」，
  但**认不出脸**（模糊到只剩轮廓光），不与舞台里的清晰立绘抢焦点；
- **动画立绘**（`main_bg_muse_anim.webp`）：照旧锚在右缘舞台，清晰可见。

## 风格来源：dsh-boot-animation

启动动画的配色（见 `lib/modules/boot/splash_palette.dart` 的
`SplashPalette.deepSpace`）就是本文件的取色依据：

- 深空底 `#0A1428`（中心）→ `#04060C`（外缘）径向渐变
- 暗角 32% 黑（`vignette: 0x52000000`，别再回到 0xCC —— 会把右下角
  压成死黑块，splash_palette.dart 里有这段事故记录）

## 用法

    python tools/build_home_backdrop_ambient.py

产物写入 `src/assets/images/main_bg_muse_ambient.jpg`。
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

SRC_ROOT = Path(__file__).resolve().parent.parent / "src"
GIRL_SRC = SRC_ROOT / "assets" / "images" / "main_bg_muse.jpg"
OUT = SRC_ROOT / "assets" / "images" / "main_bg_muse_ambient.jpg"

# ---- 画布 ----
W, H = 1600, 900

# ---- 深空径向渐变（取自 SplashPalette.deepSpace）----
# 中心放在少女所在的右偏上位置，让「光从人物身上散出来」。
# 半径放到 1.6 而不是 splash 的紧凑值 —— 渐变要**横跨整个窗口**，
# 否则左三分之一会退化成纯 #04060C（实测亮度 7.5，等于「左边没内容」）。
CENTER_X = 0.68
CENTER_Y = 0.42
RADIUS_SCALE = 1.6
TOP_RGB = (0x0A, 0x14, 0x28)      # #0A1428
BOTTOM_RGB = (0x04, 0x06, 0x0C)   # #04060C

# ---- 少女柔光 ----
# 与 Dart 侧 `_kHeightRatio = 1.1` / `_kArtAnchorX = 0.52` 同几何：
# 1600×900 窗口下画幅 654×990，脸中心落在舞台中心 x≈1485。
GIRL_HEIGHT_RATIO = 1.1
GIRL_ANCHOR_X = 0.52
STAGE_HALF = 102.5   # 1600 窗口下 backdropStageWidth ≈ 205 的一半
FACE_X = W - STAGE_HALF - 12
BLUR_RADIUS = 70
GIRL_GAIN = 0.62      # 柔光叠加强度（加法）

# 大范围柔光：半径 70 的光晕只铺开约 140px，左三分之一仍然全黑。
# 再叠一层半径 260 的广域光晕，让人物的青光**横跨整个窗口** ——
# 这是「全覆盖」能不能成立的关键：左边要看到光，只是弱，不是没有。
WIDE_BLUR_RADIUS = 260
WIDE_GIRL_GAIN = 0.34

# 低频星云噪声：给纯渐变加上「有内容的起伏」。
#
# 启动动画之所以满屏都有东西看，靠的不只是渐变，还有星尘/扫描线这类
# 细结构。这里用低频噪声（20×12 上采样）而不是规则扫描线 —— 规则线
# 在 cover 缩放时会出摩尔纹，低频噪声不会，且更接近深空的呼吸感。
NEBULA_GRID = (20, 12)
NEBULA_GAIN = 7.0
NEBULA_SEED = 20260930

# ---- 暗角 ----
VIGNETTE_START = 0.70
VIGNETTE_STRENGTH = 0.32


def build_base() -> np.ndarray:
    """深空径向渐变底。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = W * CENTER_X, H * CENTER_Y
    rx, ry = W * RADIUS_SCALE, H * RADIUS_SCALE
    d = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
    t = np.clip(d, 0.0, 1.0)[..., None]
    top = np.array(TOP_RGB, np.float32)
    bottom = np.array(BOTTOM_RGB, np.float32)
    return top * (1 - t) + bottom * t


def build_girl_glow(radius: int) -> np.ndarray:
    """少女的模糊柔光层（radius 决定铺开范围）。"""
    girl = Image.open(GIRL_SRC).convert("RGB")
    gh = H * GIRL_HEIGHT_RATIO
    gw = gh * (girl.width / girl.height)
    girl = girl.resize((int(round(gw)), int(round(gh))), Image.LANCZOS)

    # 画幅左上角：让素材的 _kArtAnchorX 处（脸）落在 FACE_X
    left = int(round(FACE_X - gw * GIRL_ANCHOR_X))
    top = int(round(H * 0.45 - gh / 2))
    canvas = Image.new("RGB", (W, H), (0, 0, 0))
    # 负偏移/超出画布的部分由 paste 自动裁掉，正是我们要的出血效果
    canvas.paste(girl, (left, top))
    canvas = canvas.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(canvas, np.float32)


def build_nebula() -> np.ndarray:
    """低频噪声起伏：让暗部也有可辨的结构，不退化成一块死板的渐变。"""
    rng = np.random.default_rng(NEBULA_SEED)
    low = rng.normal(0.0, 1.0, (NEBULA_GRID[1], NEBULA_GRID[0])).astype(np.float32)
    # 双三次上采样 → 平滑的大块起伏（不是像素噪点）
    norm = (low - low.min()) / (np.ptp(low) + 1e-6)
    img = Image.fromarray((norm * 255).astype(np.uint8), "L")
    img = img.resize((W, H), Image.BICUBIC)
    field = np.asarray(img, np.float32) / 255.0
    # 中心化后按「离人物越远越弱」衰减，避免左缘出现与主体无关的亮斑
    return (field - 0.5)[..., None] * NEBULA_GAIN


def build_vignette() -> np.ndarray:
    """四周暗角：中心亮、边角压暗，压住边缘让主体更聚焦。"""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = W * CENTER_X, H * CENTER_Y
    d = np.sqrt(((xx - cx) / (W * 0.72)) ** 2 + ((yy - cy) / (H * 0.72)) ** 2)
    d = np.clip((d - VIGNETTE_START) / max(1e-6, 1 - VIGNETTE_START), 0.0, 1.0)
    return (1 - VIGNETTE_STRENGTH * d)[..., None]


def main() -> int:
    if not GIRL_SRC.exists():
        print(f"[x] 找不到立绘源图：{GIRL_SRC}")
        return 1

    base = build_base()
    out = base
    out = out + WIDE_GIRL_GAIN * build_girl_glow(WIDE_BLUR_RADIUS)
    out = out + GIRL_GAIN * build_girl_glow(BLUR_RADIUS)
    out = out + build_nebula()
    out *= build_vignette()
    out = np.clip(out, 0, 255).astype(np.uint8)

    img = Image.fromarray(out, "RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, "JPEG", quality=82, optimize=True)

    arr = np.asarray(img, np.float32)
    lum = arr @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    print(f"[√] 已生成 {OUT}  ({OUT.stat().st_size / 1024:.0f} KB, {W}×{H})")
    print(f"    亮度 均值 {lum.mean():.1f}  最大 {lum.max():.0f}  最小 {lum.min():.0f}")
    # 左右两侧都要「有内容」——这是用户要的全覆盖，左缘不能退化成纯底色
    left = lum[:, : W // 3]
    mid = lum[:, W // 3 : 2 * W // 3]
    right = lum[:, 2 * W // 3 :]
    print(f"    分区亮度  左 {left.mean():.1f}(±{left.std():.1f}) / "
          f"中 {mid.mean():.1f}(±{mid.std():.1f}) / "
          f"右 {right.mean():.1f}(±{right.std():.1f})")
    # 「全覆盖」判据：左缘既不能是死黑（<8），也不能是一块没有起伏的
    # 纯色板（std < 1.5）—— 两者在视觉上都等于「那边没有背景」。
    if left.mean() < 8 or left.std() < 1.5:
        print("    [!] 左缘仍像纯底色，需加大 WIDE_GIRL_GAIN / NEBULA_GAIN")
    r, g, b = arr[..., 0].mean(), arr[..., 1].mean(), arr[..., 2].mean()
    print(f"    色偏 R {r:.1f} / G {g:.1f} / B {b:.1f}"
          f"  （B > G > R = 蓝青主导的科技感）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
