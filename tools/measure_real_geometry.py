#!/usr/bin/env python
"""真实几何下的底衬可读性测量（参数化版）。

## 与 render_home_backdrop.py 的差别

那个脚本复刻的是**旧测量模型**：固定左栏 420、用常量文件的
构图参数。但主界面的真实布局是（`home_view_actions.dart` /
`home_workbench_body.dart`）：

    Padding.all(12)                       ← Spacing.md 外边距
    └─ ConfigWorkbench
       ├─ collection 340                  ← kHomeWorkbenchDefaultCollectionWidth
       ├─ divider 16                      ← kHomeWorkbenchDividerWidth
       └─ details（占余下宽度，到窗口右缘 −12）

详情面板内部再有一层 `Padding.all(12)`（ActiveConfigPanel），
LogCenterPanel 还有 Card 自身 ~4 margin + Padding.all(12)。
所以**文字真正能出现的区域**远比旧模型宽 —— 日志长行可以一直
延伸到窗口右缘附近。旧模型量出来「达标」的素材，在真实几何下
可能不达标（第一版动画素材就是这么漏检的）。

本模块把构图参数**全部参数化**，供新素材调参迭代：
- Dart 侧改了构图常量，这里同步传参，两边必须一致；
- 每次生成素材后，用四档分辨率逐帧测最差次级文字对比度。

## 风险面

保守取「详情面板内部」整块为文字风险面（不只日志行）——
状态页/任务页/统计页的文字与图表都可能出现在那里。
左栏卡片自身有 94% 不透明度的卡片底，风险低，不测。
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

# ---- 与 render_home_backdrop.py 一致的界面结构常量 ----
SURFACE = (13, 16, 21)
PANEL_TINT = (22, 26, 33)
TXT = (226, 232, 240)
TXT_SUB = (150, 164, 182)

MARGIN = 12          # Spacing.md（外层 Padding 与面板内 Padding 同值）
COLLECTION_W = 340   # kHomeWorkbenchDefaultCollectionWidth
DIVIDER_W = 16       # kHomeWorkbenchDividerWidth


def stage_for(w: int) -> float:
    """右缘立绘舞台宽度（含右外边距），随窗口宽缩放。

    少女脸部在显示尺寸下约占 0.3×画幅宽 —— 窗口越大脸越大，
    固定宽舞台在高分辨率下装不下，所以按窗口宽的 16% 缩放，
    夹在 [200, 340]。
    """
    return float(min(340.0, max(200.0, w * 0.16)))


def _rel_lum(c):
    def f(u):
        u = u / 255.0
        return u / 12.92 if u <= 0.03928 else ((u + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2])


def contrast(a, b):
    l1, l2 = sorted((_rel_lum(a), _rel_lum(b)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def paint_backdrop_params(
    w: int,
    h: int,
    art: Image.Image,
    *,
    art_w: float = 1480,
    art_h: float = 2240,
    height_ratio: float = 1.1,
    anchor_from_right: float = 100.0,
    anchor_y: float = 0.45,
    art_anchor_x: float = 0.55,
    opacity: float = 0.80,
    fade_left_start: float = 0.26,
    fade_left_end: float = 0.62,
    fade_band_y: float = 0.10,
) -> Image.Image:
    """复刻 _BackdropPainter.paint()（参数化），向量化实现。

    锚点用「从右缘偏移」而不是窗口宽比例：舞台宽度是固定像素
    （不随窗口缩放），锚点跟着舞台走才能保证脸永远落在舞台里。
    """
    canvas = np.full((h, w, 3), SURFACE, np.float32)

    art_h_px = h * height_ratio
    art_w_px = art_h_px * (art_w / art_h)
    stage = stage_for(w)
    left = w - (stage / 2 + MARGIN) - art_w_px * art_anchor_x
    top = h * anchor_y - art_h_px / 2

    x0, y0 = max(0, int(left)), max(0, int(top))
    x1, y1 = min(w, int(left + art_w_px)), min(h, int(top + art_h_px))
    if x1 > x0 and y1 > y0:
        sx0 = max(0, int((x0 - left) / art_w_px * art.width))
        sy0 = max(0, int((y0 - top) / art_h_px * art.height))
        sx1 = min(art.width, int((x1 - left) / art_w_px * art.width))
        sy1 = min(art.height, int((y1 - top) / art_h_px * art.height))
        crop = art.crop((sx0, sy0, sx1, sy1)).resize((x1 - x0, y1 - y0), Image.LANCZOS)
        region = canvas[y0:y1, x0:x1]
        canvas[y0:y1, x0:x1] = region * (1 - opacity) + np.asarray(crop, np.float32) * opacity

    # 左渐隐 + 上下渐隐（两次 dstIn 的等效：与 surface 按系数混合）
    xx = np.arange(w, dtype=np.float32)
    span_x = max(1e-6, (fade_left_end - fade_left_start) * w)
    vx = np.clip((xx - fade_left_start * w) / span_x, 0.0, 1.0)
    yy = np.arange(h, dtype=np.float32)
    band = fade_band_y * h
    vy = np.ones(h, np.float32)
    vy[: int(band)] = np.linspace(0.0, 1.0, int(band), dtype=np.float32)[: int(band)]
    vy_tail = vy[h - int(band):] * 0 + np.linspace(1.0, 0.0, int(band), dtype=np.float32)
    vy[h - int(band):] = np.minimum(vy[h - int(band):], vy_tail)
    f = np.minimum(vx[None, :], vy[:, None])
    canvas = canvas * f[..., None] + np.array(SURFACE, np.float32) * (1 - f[..., None])
    return Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))


def measure_text_rows_real(
    bg: Image.Image,
    w: int,
    h: int,
    panel_alpha: float = 0.80,
    stage_from_right: float = 212.0,
) -> tuple[float, float]:
    """真实几何下详情面板文字风险面的最差对比度。

    [stage_from_right] 是右缘「立绘舞台」的宽度（含 12 外边距）——
    该区域**没有面板覆盖**，立绘全亮可见，文字不会出现在那里，
    因此从风险面里排除。返回 (正文最差, 次级最差)。
    """
    arr = np.asarray(bg, np.float32)

    dx0 = int(MARGIN + COLLECTION_W + DIVIDER_W + MARGIN)      # 详情面板文字区左缘
    dx1 = int(w - MARGIN - MARGIN - (stage_from_right - MARGIN))  # 右侧被舞台占走
    dy0 = int(MARGIN + MARGIN)
    dy1 = int(h - MARGIN - MARGIN)
    if dx1 <= dx0 or dy1 <= dy0:
        return 1e9, 1e9

    region = arr[dy0:dy1, dx0:dx1]
    # 8×8 窗口取最亮像素（最接近「这格里有字时的最坏底色」）
    hh, ww = region.shape[:2]
    ch, cw = hh // 8 * 8, ww // 8 * 8
    if ch < 8 or cw < 8:
        blocks = region.reshape(-1, 3)
        sums = blocks.sum(axis=1)
        brightest = blocks[sums.argmax()]
    else:
        blocks = region[:ch, :cw].reshape(ch // 8, 8, cw // 8, 8, 3)
        sums = blocks.sum(axis=(1, 3, 4))
        by, bx = np.unravel_index(sums.argmax(), sums.shape)
        cell = blocks[by, :, bx, :].reshape(-1, 3)
        brightest = cell[cell.sum(axis=1).argmax()]

    # 面板混合：与 Dart 侧 `homePanelColor` 的语义一致 ——
    # `withValues(alpha: panelAlpha)` 是**面板色占 panelAlpha**、
    # 底衬透 (1-panelAlpha)。曾把权重写反（背景占 panelAlpha），
    # 导致测量系统性过严、素材被过度压暗 —— 见本文件头注。
    mixed = tuple(
        PANEL_TINT[i] * panel_alpha + float(brightest[i]) * (1 - panel_alpha)
        for i in range(3)
    )
    return contrast(TXT, mixed), contrast(TXT_SUB, mixed)


def review_art(
    art_path: Path,
    *,
    anchor_from_right: float = 100.0,
    art_anchor_x: float = 0.55,
    height_ratio: float = 1.1,
    opacity: float = 0.80,
    panel_alpha: float = 0.86,
    stage_from_right: float = 212.0,
    frames: list[int] | None = None,
    sizes: list[tuple[int, int]] | None = None,
    save_prefix: str | None = None,
) -> tuple[float, str]:
    """四档分辨率逐帧复核，返回 (最差次级对比度, 位置描述)。"""
    im = Image.open(art_path)
    n = getattr(im, "n_frames", 1)
    if frames is None:
        frames = list(range(0, n, max(1, n // 12)))[:12]
    if sizes is None:
        sizes = [(1280, 800), (1440, 900), (1920, 1080), (2560, 1440)]

    worst = 1e9
    worst_where = ""
    for i in frames:
        im.seek(i)
        art = im.convert("RGB")
        for (w, h) in sizes:
            bg = paint_backdrop_params(
                w, h, art,
                height_ratio=height_ratio,
                anchor_from_right=anchor_from_right,
                art_anchor_x=art_anchor_x,
                opacity=opacity,
            )
            _, sub = measure_text_rows_real(bg, w, h, panel_alpha, stage_from_right)
            if sub < worst:
                worst, worst_where = sub, f"帧{i} @{w}x{h}"
            if save_prefix and (w, h) == sizes[0] and i == frames[len(frames) // 2]:
                bg.save(f"{save_prefix}_{w}x{h}.png")
    return worst, worst_where


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser()
    ap.add_argument("art", type=str)
    ap.add_argument("--anchor-from-right", type=float, default=100.0)
    ap.add_argument("--art-anchor-x", type=float, default=0.55)
    ap.add_argument("--height-ratio", type=float, default=1.1)
    ap.add_argument("--opacity", type=float, default=0.80)
    ap.add_argument("--panel-alpha", type=float, default=0.86)
    ap.add_argument("--stage-from-right", type=float, default=212.0)
    ap.add_argument("--save-prefix", type=str, default=None)
    args = ap.parse_args()

    worst, where = review_art(
        Path(args.art),
        anchor_from_right=args.anchor_from_right,
        art_anchor_x=args.art_anchor_x,
        height_ratio=args.height_ratio,
        opacity=args.opacity,
        panel_alpha=args.panel_alpha,
        stage_from_right=args.stage_from_right,
        save_prefix=args.save_prefix,
    )
    ok = "✓" if worst >= 4.5 else "✗"
    print(f"最差次级 {worst:.2f}:1 {ok}  @ {where}   "
          f"(hr={args.height_ratio} ar={args.anchor_from_right} "
          f"aax={args.art_anchor_x} op={args.opacity} "
          f"panelα={args.panel_alpha} stage={args.stage_from_right})")
