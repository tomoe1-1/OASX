#!/usr/bin/env python
"""离屏复核主界面底衬（HomeBackdrop）的构图与可读性。

背景：本机 GUI 抓帧走不通（Impeller/OpenGLES 下 GPU 像素不在 GDI 可见 DC），
所以这里用 Pillow 按 `home_backdrop.dart` 的**同一组常量**复刻绘制，
用来回答两个问题：

  1. 构图对不对 —— 眼睛有没有落在设计位置、边缘有没有硬接缝
  2. 文字能不能读 —— 面板半透明后，正文对「透过来的最亮背景像素」
     还够不够 WCAG AA 的 4.5:1

⚠️ 常量必须与 Dart 侧保持一致。任何一侧改了数，另一侧要同步，
否则这个脚本给出的结论就是假的。

⚠️ **测量点也很重要**：可读性必须在**文字真正所在的行**上量，
而不是面板之间的缝隙。缝隙里没有字，量出来永远很好看（曾因此得出
「13:1，余量很大」的错误结论，实际文字行上只有 3.2–3.8:1）。
`measure_text_rows()` 量的才是真正的风险面。
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw

# ---- 与 home_backdrop.dart 保持一致的常量 ----
ART_W, ART_H = 1480, 2240  # 只用比值；与成品素材像素一致（见 build_home_backdrop_asset.py）
HEIGHT_RATIO = 1.6
ANCHOR_X = 0.95
ANCHOR_Y = 0.45
ART_ANCHOR_X = 0.45
OPACITY = 0.80
FADE_LEFT_START, FADE_LEFT_END = 0.26, 0.62
FADE_BAND_Y = 0.10
PANEL_ALPHA = 0.80

# ---- 界面结构常量（对齐 design_tokens）----
RAIL_W = 88
SPACING_MD = 12
APPBAR_H = 64
SURFACE = (13, 16, 21)
PANEL_TINT = (22, 26, 33)
CARD_TINT = (30, 35, 43)
LINE = (58, 68, 82)
TXT = (226, 232, 240)
TXT_SUB = (150, 164, 182)
ACCENT = (126, 192, 220)

ROOT = Path(__file__).resolve().parent.parent
ART_PATH = ROOT / "src" / "assets" / "images" / "main_bg_muse.jpg"
OUT_DIR = ROOT / "tools" / "preview"


def _rel_lum(c: tuple[float, float, float]) -> float:
    def f(u: float) -> float:
        u /= 255.0
        return u / 12.92 if u <= 0.03928 else ((u + 0.055) / 1.055) ** 2.4

    r, g, b = (f(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    l1, l2 = sorted((_rel_lum(a), _rel_lum(b)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)


def paint_backdrop(w: int, h: int, art: Image.Image) -> Image.Image:
    """复刻 _BackdropPainter.paint()。"""
    canvas = Image.new("RGB", (w, h), SURFACE)

    # 定位：高度锚定窗口，水平锚点落在 ANCHOR_X
    art_h = h * HEIGHT_RATIO
    art_w = art_h * (ART_W / ART_H)
    left = w * ANCHOR_X - art_w * ART_ANCHOR_X
    top = h * ANCHOR_Y - art_h / 2

    layer = art.resize((max(1, int(art_w)), max(1, int(art_h))), Image.LANCZOS)
    ox, oy = int(left), int(top)
    x0, y0 = max(0, ox), max(0, oy)
    x1, y1 = min(w, ox + layer.width), min(h, oy + layer.height)
    if x1 > x0 and y1 > y0:
        src = layer.crop((x0 - ox, y0 - oy, x1 - ox, y1 - oy))
        dst = canvas.crop((x0, y0, x1, y1))
        canvas.paste(Image.blend(dst, src, OPACITY), (x0, y0))

    # 左侧 + 上下渐隐（对应 Dart 侧两次 dstIn）
    px = canvas.load()
    span_x = max(1e-6, (FADE_LEFT_END - FADE_LEFT_START) * w)
    band = FADE_BAND_Y * h
    for y in range(h):
        vy = 1.0
        if y < band:
            vy = y / max(1.0, band)
        elif y > h - band:
            vy = (h - y) / max(1.0, band)
        vy = max(0.0, min(1.0, vy))
        for x in range(w):
            t = (x - w * FADE_LEFT_START) / span_x
            vx = max(0.0, min(1.0, t))
            f = vx * vy
            r, g, b = px[x, y]
            px[x, y] = (
                int(r * f + SURFACE[0] * (1 - f)),
                int(g * f + SURFACE[1] * (1 - f)),
                int(b * f + SURFACE[2] * (1 - f)),
            )
    return canvas


def _tint_over(base: tuple[int, int, int], tint: tuple[float, float, float],
               alpha: float) -> tuple[int, int, int]:
    return tuple(int(base[i] * (1 - alpha) + tint[i] * alpha) for i in range(3))  # type: ignore[return-value]


def draw_shell(bg: Image.Image, panel_alpha: float) -> Image.Image:
    """叠出主界面骨架，用于可读性测量（不是像素级复刻）。"""
    w, h = bg.size
    out = bg.copy()
    arr = bg.load()
    d = ImageDraw.Draw(out)

    lx0, lx1 = RAIL_W + SPACING_MD, RAIL_W + SPACING_MD + 420
    rx0, rx1 = lx1 + SPACING_MD, w - SPACING_MD
    ty0, ty1 = APPBAR_H + SPACING_MD, h - SPACING_MD

    def panel(box, alpha):
        x0, y0, x1, y1 = box
        sub = out.crop(box)
        sp = sub.load()
        for yy in range(sub.height):
            for xx in range(sub.width):
                sp[xx, yy] = _tint_over(tuple(arr[x0 + xx, y0 + yy]), PANEL_TINT, alpha)  # type: ignore[arg-type]
        mask = Image.new("L", sub.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, sub.width - 1, sub.height - 1), radius=12, fill=255
        )
        out.paste(sub, (x0, y0), mask)
        d.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=12, outline=LINE)

    panel((lx0, ty0, lx1, ty1), panel_alpha)
    panel((rx0, ty0, rx1, ty1), panel_alpha)

    # 卡片（左栏）
    for i in range(5):
        y = ty0 + 16 + i * 122
        if y + 104 > ty1 - 16:
            break
        box = (lx0 + 16, y, lx1 - 16, y + 104)
        sub = out.crop(box)
        sp = sub.load()
        for yy in range(sub.height):
            for xx in range(sub.width):
                sp[xx, yy] = _tint_over(tuple(arr[box[0] + xx, box[1] + yy]), CARD_TINT, 0.94)  # type: ignore[arg-type]
        mask = Image.new("L", sub.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, sub.width - 1, sub.height - 1), radius=10, fill=255
        )
        out.paste(sub, (box[0], box[1]), mask)
        d.rounded_rectangle(box, radius=10, outline=LINE)
        d.text((box[0] + 16, box[1] + 18), f"task {i + 1}", fill=TXT)
        d.text((box[0] + 16, box[1] + 44), "running 12:34", fill=TXT_SUB)
        d.text((box[0] + 16, box[1] + 70), "progress 68%", fill=ACCENT)

    d.text((rx0 + 24, ty0 + 18), "Run log", fill=TXT)
    for i in range(11):
        d.text((rx0 + 24, ty0 + 56 + i * 28), f"[12:3{i}]  step {i + 1} done  1.2s", fill=TXT_SUB)

    d.rectangle((0, 0, RAIL_W, h), fill=(16, 19, 25))
    d.rectangle((0, 0, w, APPBAR_H), fill=(16, 19, 25))
    d.line((RAIL_W, 0, RAIL_W, h), fill=LINE)
    d.line((0, APPBAR_H, w, APPBAR_H), fill=LINE)
    return out


def measure_text_rows(bg: Image.Image, w: int, h: int) -> tuple[float, float]:
    """在**文字真正所在的行**上测量对比度。

    这才是底衬对可读性的实际威胁面 —— 面板半透明，透上来的背景会垫在
    文字下面。只看面板缝隙会得出过于乐观的结论（曾经如此）。

    日志区的行布局与 `draw_shell()` 一致：
        x 从 rx0 + 24 起，宽约 336（最长的日志行）
        y 从 ty0 + 56 起，每行 28px，字形高约 16px

    返回 (正文最差对比度, 次级文字最差对比度)。
    """
    rx0 = RAIL_W + SPACING_MD + 420 + SPACING_MD
    ty0 = APPBAR_H + SPACING_MD
    arr = bg.load()

    worst_body = 1e9
    worst_sub = 1e9
    for i in range(11):
        y = ty0 + 56 + i * 28 + 6
        if y + 16 >= h - SPACING_MD:
            break
        x1 = min(rx0 + 24 + 336, w)
        if x1 <= rx0 + 24:
            continue
        # 该行里最亮的背景像素 —— 它决定了这一行最差的可读性
        brightest = (0, 0, 0)
        for yy in range(y, y + 16):
            for xx in range(rx0 + 24, x1):
                c = arr[xx, yy]
                if sum(c) > sum(brightest):
                    brightest = c
        # 面板压在背景上之后透出来的颜色
        mixed = tuple(
            PANEL_TINT[i] * (1 - PANEL_ALPHA) + brightest[i] * PANEL_ALPHA
            for i in range(3)
        )
        worst_body = min(worst_body, contrast(TXT, mixed))
        worst_sub = min(worst_sub, contrast(TXT_SUB, mixed))
    return worst_body, worst_sub


def report(w: int, h: int, art: Image.Image) -> Image.Image:
    bg = paint_backdrop(w, h, art)
    ui = draw_shell(bg, PANEL_ALPHA)

    # ① 文字行上的真实可读性（主要指标）
    worst_body, worst_sub = measure_text_rows(bg, w, h)

    # ② 面板缝隙里的亮度（辅助参考：这里能直观看出底衬够不够明显）
    gap = ui.crop((RAIL_W + SPACING_MD + 423, APPBAR_H, RAIL_W + SPACING_MD + 429, h))
    gp = list(gap.getdata())
    gp.sort(key=lambda c: sum(c), reverse=True)
    top = gp[: max(1, len(gp) // 20)]
    avg = tuple(sum(c[i] for c in top) / len(top) for i in range(3))

    ok_body = "✓" if worst_body >= 4.5 else "✗"
    ok_sub = "✓" if worst_sub >= 4.5 else "✗"

    print(f"--- {w}x{h} ---")
    print(f"  文字行 · 正文最差   : {worst_body:5.2f} : 1   {ok_body}  (AA 需 4.5)")
    print(f"  文字行 · 次级最差   : {worst_sub:5.2f} : 1   {ok_sub}  (AA 需 4.5)")
    print(f"  面板缝隙 最亮 5%    : {tuple(round(v) for v in avg)}  (底衬可见度参考)")
    return ui


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    art = Image.open(ART_PATH).convert("RGB")
    print(f"art: {art.size} @ {ART_PATH.name}")
    print(f"常量: hrat={HEIGHT_RATIO} ax={ANCHOR_X} ay={ANCHOR_Y} "
          f"op={OPACITY} 面板α={PANEL_ALPHA}\n")

    all_ok = True
    for w, h in [(1280, 800), (1440, 900), (1920, 1080), (2560, 1440)]:
        ui = report(w, h, art)
        ui.save(OUT_DIR / f"home_backdrop_{w}x{h}.png")
        _, sub = measure_text_rows(paint_backdrop(w, h, art), w, h)
        all_ok = all_ok and sub >= 4.5

    print()
    print("结论：" + ("全部达标（次级文字 ≥ 4.5:1）" if all_ok
                     else "存在不达标分辨率，需要调整构图或面板透明度"))
    print(f"预览已写入 {OUT_DIR}")


if __name__ == "__main__":
    main()
