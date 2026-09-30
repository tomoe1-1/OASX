#!/usr/bin/env python
"""复刻 _BackdropPainter（含全屏 ambient 层）渲染主页预览，用于可视化验收。

锁屏状态下无法对真机截屏，本脚本用与 Dart 完全一致的几何与混合公式
离线渲染，确认「背景全面覆盖 + 立绘舞台 + 可读性」三件事。

与 measure_real_geometry.py 的区别：本脚本**输出 PNG 预览图**，并补上了
ambient 全屏层（v2 新增的「背景全覆盖」那一层）。
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"C:/Users/12296/Desktop/yys/OASX-Neo/src/assets/images")
ART = ROOT / "main_bg_muse_anim.webp"
AMBIENT = ROOT / "main_bg_muse_ambient.jpg"

SURFACE = np.array([13, 16, 21], np.float32)
PANEL_TINT = np.array([22, 26, 33], np.float32)

MARGIN = 12
COLLECTION_W = 340
DIVIDER_W = 16
DETAILS_MIN = 360
LOG_MIN = 360
THREE_PANE_FLOOR = COLLECTION_W + DIVIDER_W + DETAILS_MIN + DIVIDER_W + LOG_MIN  # 1092

HEIGHT_RATIO = 1.1
ANCHOR_Y = 0.45
ART_ANCHOR_X = 0.52
ART_W, ART_H = 1480.0, 2240.0
OPACITY = 0.80
AMBIENT_OPACITY = 0.92
PANEL_ALPHA = 0.82
FADE_LEFT_START = 0.26
FADE_LEFT_END = 0.62
FADE_BAND_Y = 0.10


def stage_for(workbench_w: float) -> float:
    ideal = float(min(300.0, max(120.0, workbench_w * 0.13)))
    return float(min(ideal, max(0.0, workbench_w - THREE_PANE_FLOOR)))


def _rel_lum(c):
    def f(u):
        u = u / 255.0
        return u / 12.92 if u <= 0.03928 else ((u + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def contrast(a, b):
    l1, l2 = sorted((_rel_lum(a), _rel_lum(b)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def render(w: int, h: int, art: Image.Image, ambient: Image.Image) -> np.ndarray:
    canvas = np.tile(SURFACE, (h, w, 1)).astype(np.float32)

    # ---- ① 全屏 ambient 层（cover + 0.92）----
    a = ambient.convert("RGB").resize((w, h), Image.LANCZOS)
    canvas = canvas * (1 - AMBIENT_OPACITY) + np.asarray(a, np.float32) * AMBIENT_OPACITY

    # ---- ② 立绘 ----
    workbench_w = w - 2 * MARGIN
    stage = stage_for(workbench_w)
    anchor_from_right = stage / 2 + MARGIN
    art_h_px = h * HEIGHT_RATIO
    art_w_px = art_h_px * (ART_W / ART_H)
    left = w - anchor_from_right - art_w_px * ART_ANCHOR_X
    top = h * ANCHOR_Y - art_h_px / 2
    x0, y0 = max(0, int(left)), max(0, int(top))
    x1, y1 = min(w, int(left + art_w_px)), min(h, int(top + art_h_px))
    if x1 > x0 and y1 > y0:
        sx0 = max(0, int((x0 - left) / art_w_px * art.width))
        sy0 = max(0, int((y0 - top) / art_h_px * art.height))
        sx1 = min(art.width, int((x1 - left) / art_w_px * art.width))
        sy1 = min(art.height, int((y1 - top) / art_h_px * art.height))
        crop = art.crop((sx0, sy0, sx1, sy1)).resize((x1 - x0, y1 - y0), Image.LANCZOS)
        region = canvas[y0:y1, x0:x1]
        canvas[y0:y1, x0:x1] = region * (1 - OPACITY) + np.asarray(crop, np.float32) * OPACITY

    # ---- ③ 渐隐（左淡出 + 上下带）----
    xx = np.arange(w, dtype=np.float32)
    span_x = max(1e-6, (FADE_LEFT_END - FADE_LEFT_START) * w)
    vx = np.clip((xx - FADE_LEFT_START * w) / span_x, 0.0, 1.0)  # 左 0 → 右 1
    yy = np.arange(h, dtype=np.float32)
    band = int(FADE_BAND_Y * h)
    vy = np.ones(h, np.float32)
    if band > 1:
        vy[:band] = np.linspace(0.0, 1.0, band)
        vy[h - band:] = np.minimum(vy[h - band:], np.linspace(1.0, 0.0, band))
    f = np.minimum(vx[None, :], vy[:, None])
    canvas = canvas * f[..., None] + SURFACE[None, None, :] * (1 - f[..., None])

    # ---- ④ 三栏面板（半透明，舞台区不画）----
    cx0, cx1 = MARGIN, MARGIN + COLLECTION_W
    dx0 = cx1 + DIVIDER_W + MARGIN
    dx1 = w - MARGIN - MARGIN - max(0, int(stage) - MARGIN)  # 右侧被舞台占走
    lx0 = dx1 + DIVIDER_W + MARGIN
    lx1 = w - MARGIN
    for (px0, px1) in [(cx0, cx1), (dx0, dx1), (lx0, lx1)]:
        if px1 <= px0:
            continue
        region = canvas[:, px0:px1]
        canvas[:, px0:px1] = region * (1 - PANEL_ALPHA) + PANEL_TINT[None, None, :] * PANEL_ALPHA

    return np.clip(canvas, 0, 255).astype(np.uint8)


def main() -> None:
    ambient = Image.open(AMBIENT)
    im = Image.open(ART)
    n = getattr(im, "n_frames", 1)
    im.seek(n // 2)
    art = im.convert("RGB")

    out_dir = Path(r"C:/Users/12296/AppData/Local/Temp")
    for (w, h) in [(1280, 800), (1920, 1080)]:
        img = render(w, h, art, ambient)
        out = out_dir / f"home_v2_{w}x{h}.png"
        Image.fromarray(img).save(out)
        # 分区亮度，确认「不是只有一边有」
        lum = img.mean(axis=2)
        left = lum[:, : w // 3].mean()
        mid = lum[:, w // 3:2 * w // 3].mean()
        right = lum[:, 2 * w // 3:].mean()
        print(f"{out.name}: 左 {left:.1f} / 中 {mid:.1f} / 右 {right:.1f}")
        # 面板文字区最差底色对比度（次级文字 TXT_SUB = 150,164,182）
        dx0 = int(MARGIN + COLLECTION_W + DIVIDER_W + MARGIN)
        dx1 = int(w - MARGIN - MARGIN - max(0, int(stage_for(w - 2 * MARGIN)) - MARGIN))
        region = img[MARGIN * 2:h - MARGIN * 2, dx0:dx1].reshape(-1, 3)
        brightest = region[region.sum(axis=1).argmax()]
        mixed = PANEL_TINT * PANEL_ALPHA + brightest * (1 - PANEL_ALPHA)
        print(f"   面板内最差底色对比度(次级) {contrast((150, 164, 182), mixed):.2f}:1")


if __name__ == "__main__":
    main()
