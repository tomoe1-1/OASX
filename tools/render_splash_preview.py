"""精确复刻 SplashPainter._paintArt 的渲染验证器。

用途：本机 GUI 抓帧（Impeller/GPU 不可抓）与 flutter_tester（引擎快照不匹配）
两条路都走不通，改用本脚本直接按 painter 的数学公式 + 真实立绘资源
合成各进度的画面，用于人工/程序核查「线稿渐变」与「睁眼」的可读性。

复刻对应 splash_painter.dart 的 _paintArt / paint 关键区段：
  - 线稿层：artClosedWire*(1-liftT) + artOpenWire*liftT，用 plus(加亮) 合成
  - 实体层：artClosed*(1-liftT) + artOpen*liftT，裁剪到扫描线以上
  - 眼区扫描光带
  - 虹膜渐亮 + 收缩 + 高光点
  - 冲击波圆环

（眼睑开合弧线已随 splash_painter.dart 一并移除，见下方第 3 段注释。）
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

ASSETS = r"C:/Users/12296/Desktop/yys/OASX-Neo/src/assets/splash"
OUT = r"C:/Users/12296/Desktop/yys/OASX-Neo/src/test_snapshots"

# ---- 画面参数（对应 splash_painter.dart）----
W, H = 1200, 800
ART_SCALE = 1.0

# 配色（SplashPalette.deepSpace）
BACKDROP_TOP = (10, 20, 40)
BACKDROP_BOTTOM = (4, 6, 12)
WIRE_GLOW = (109, 195, 227)
SCAN = (131, 211, 220)
IRIS = (47, 232, 200)
TEXT = (242, 246, 250)
# SplashPalette.deepSpace.accent = 0xFF4FA8D8
ACCENT = (79, 168, 216)
# SplashPalette.deepSpace 的文字三档
TEXT_DIM = (110, 140, 168)   # 0xFF6E8CA8 —— 语录
FAINT = (84, 112, 138)       # 0xFF54708A —— 日期（比语录再暗一档）

EYE_U, EYE_V = 0.58, 0.33


def seg(p, b, e):
    if e <= b:
        return 1.0
    return max(0.0, min(1.0, (p - b) / (e - b)))


def ease_out(t):
    return 1 - (1 - t) ** 3


def ease_in_out(t):
    return 4 * t * t * t if t < 0.5 else 1 - ((-2 * t + 2) ** 3) / 2


def art_rect():
    """按当前全局 W/H 算立绘贴合矩形（cover + 右对齐）。

    与 splash_painter._artRect 逐字对应：
        scale = max(W/1200, H/800) * artScale
        w = 1200*scale, h = 800*scale
        top = (H-h)/2
        left = W-w              <- 右缘贴齐画布右缘

    旧实现是「高度贴合」(`h=H, w=h*1.5`)，在宽高比偏离 3:2 时会在右缘
    留出空白竖带。改为 cover 后两轴同时覆盖，不再出现空带。
    """
    return art_rect_cover((W, H), ART_SCALE)


def art_rect_cover(size, art_scale=ART_SCALE, art_w=1200.0, art_h=800.0):
    w_, h_ = size
    if w_ <= 0 or h_ <= 0:
        return 0.0, 0.0, 0.0, 0.0
    scale = max(w_ / art_w, h_ / art_h) * art_scale
    w = art_w * scale
    h = art_h * scale
    top = (h_ - h) / 2
    left = w_ - w
    return left, top, w, h


def load(path):
    """保留原 mode —— 线稿 PNG 靠 alpha 携带线条信息，不能转 RGB。"""
    return Image.open(path)


def paste_plus(base, img, dst, opacity):
    """模拟 BlendMode.plus 叠加到 base 上。

    资源现在都是**黑底 RGB**：
      - 实体 JPG：黑底发光
      - 线稿 PNG：已在生成阶段把 alpha 预乘到黑底，RGB 即最终贡献
    所以统一按 `base + img * opacity` 处理，无预乘分支。
    """
    left, top, w, h = dst
    scaled = img.convert("RGB").resize(
        (max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)
    arr = np.asarray(scaled).astype(np.float32) * opacity

    cx0, cy0 = int(round(left)), int(round(top))
    sx0 = max(0, -cx0)
    sy0 = max(0, -cy0)
    sx1 = min(arr.shape[1], W - cx0)
    sy1 = min(arr.shape[0], H - cy0)
    if sx1 <= sx0 or sy1 <= sy0:
        return base
    region = arr[sy0:sy1, sx0:sx1, :]
    bx0, by0 = cx0 + sx0, cy0 + sy0
    b = np.asarray(base).astype(np.float32)
    sub = b[by0:by0 + region.shape[0], bx0:bx0 + region.shape[1], :]
    b[by0:by0 + region.shape[0], bx0:bx0 + region.shape[1], :] = np.clip(
        sub + region, 0, 255)
    return Image.fromarray(b.astype(np.uint8))


def radial_glow(size, center, radius, color, alpha):
    """生成径向渐变的发光贴片并叠加。"""
    layer = Image.new("RGB", size, (0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 40
    for i in range(steps, 0, -1):
        r = radius * i / steps
        a = alpha * (1 - i / steps) ** 1.2
        col = tuple(int(c * a) for c in color)
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r],
                  fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.10))
    return layer


def render(progress, with_art=True):
    # 背景
    base = Image.new("RGB", (W, H), BACKDROP_BOTTOM)
    # 径向渐变背景
    yy, xx = np.mgrid[0:H, 0:W]
    cx, cy = W * 0.5, H * 0.42
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    maxd = max(W, H) * 0.78
    t = np.clip(dist / maxd, 0, 1)
    bg = (np.array(BACKDROP_TOP) * (1 - t)[..., None]
          + np.array(BACKDROP_BOTTOM) * t[..., None])
    base = Image.fromarray(bg.astype(np.uint8))

    left, top, aw, ah = art_rect()
    eye = (left + aw * EYE_U, top + ah * EYE_V)

    # ---- 时序 ----
    lift_t = ease_in_out(seg(progress, 0.58, 0.90))
    shine_t = ease_out(seg(progress, 0.72, 0.96))
    scan_t = seg(progress, 0.64, 0.92)
    wire_in = ease_out(seg(progress, 0.04, 0.26))
    solid_in = ease_in_out(seg(progress, 0.24, 0.58))
    burst = seg(progress, 0.88, 1.0)

    if with_art:
        asset_dir = ASSETS
    else:
        asset_dir = None

    if asset_dir:
        closed_wire = load(os.path.join(asset_dir, "girl_closed_wire.png"))
        open_wire = load(os.path.join(asset_dir, "girl_open_wire.png"))
        closed = load(os.path.join(asset_dir, "girl_closed.jpg"))
        open_i = load(os.path.join(asset_dir, "girl_open.jpg"))

        # ---- 1. 线稿层 ----
        dst = (left, top, aw, ah)
        base = paste_plus(base, closed_wire, dst, wire_in * (1 - lift_t) * 0.95)
        base = paste_plus(base, open_wire, dst, wire_in * lift_t * 0.95)

        # ---- 2. 实体层（裁剪到扫描线以上）----
        solid_op = solid_in * 0.92
        if solid_op > 0.001:
            front = ease_out(solid_in) * (H * 1.15)
            layer = Image.new("RGB", (W, H), (0, 0, 0))
            layer = paste_plus(layer, closed, dst, solid_op * (1 - lift_t))
            layer = paste_plus(layer, open_i, dst, solid_op * lift_t)
            arr = np.asarray(layer).copy()
            arr[int(front):, :, :] = 0
            base = Image.fromarray(
                np.clip(np.asarray(base).astype(np.int32) + arr.astype(np.int32), 0, 255
                        ).astype(np.uint8))

    # ---- 3. 眼区扫描光带 ----
    #
    # 注意：这里**不再画眼睑开合弧线**。
    # 那两道弧线是贴上去的叠加层，位置靠固定归一化坐标（眼距 0.185、
    # 开合量 0.028）估算；而立绘里眼睛处于斜向透视且被发丝半遮，
    # 弧线对不上真实眼位，观感像两个悬空胶囊。已在 splash_painter.dart
    # 中整体删除，此处必须同步 —— 否则本脚本会渲染出真实程序里
    # 并不存在的画面，验证就失去意义了。
    if 0 < scan_t < 1:
        band_h = ah * 0.14
        band_y = eye[1] - band_h * 0.65 + band_h * 1.3 * scan_t
        band = Image.new("RGB", (W, H), (0, 0, 0))
        bd = ImageDraw.Draw(band)
        for i in range(30):
            tt = i / 30
            a = math.sin(tt * math.pi) * 0.30
            y = band_y - band_h / 2 + band_h * tt
            bd.line([(left, y), (left + aw, y)],
                    fill=tuple(int(c * a) for c in SCAN), width=2)
        band = band.filter(ImageFilter.GaussianBlur(3))
        # 裁剪到眼部区域
        arr = np.asarray(band).copy()
        mask = np.zeros((H, W), bool)
        x0, x1 = int(left + aw * 0.58 - aw * 0.23), int(left + aw * 0.58 + aw * 0.23)
        y0, y1 = int(eye[1] - ah * 0.08), int(eye[1] + ah * 0.08)
        mask[max(0, y0):y1, max(0, x0):x1] = True
        arr[~mask] = 0
        base = Image.fromarray(
            np.clip(np.asarray(base).astype(np.int32) + arr.astype(np.int32), 0, 255
                    ).astype(np.uint8))

    # ---- 4. 虹膜渐亮 + 收缩 + 高光 ----
    if shine_t > 0:
        a = math.sin(shine_t * math.pi * 0.85) * 0.75
        glow_r = H * (0.055 - 0.028 * shine_t)
        glow = radial_glow((W, H), eye, glow_r, IRIS, a)
        base = Image.fromarray(
            np.clip(np.asarray(base).astype(np.int32)
                    + np.asarray(glow).astype(np.int32), 0, 255).astype(np.uint8))
        if shine_t > 0.5:
            hp = (shine_t - 0.5) / 0.5
            d = ImageDraw.Draw(base, "RGB")
            hr = glow_r * 0.20 * hp
            hx = eye[0] - glow_r * 0.28
            hy = eye[1] - glow_r * 0.30
            d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr],
                      fill=tuple(int(255 * 0.85 * hp) for _ in range(3)))

    # ---- 5. 冲击波 ----
    if 0 < burst < 1:
        d = ImageDraw.Draw(base, "RGB")
        a = math.sin(burst * math.pi) * 0.45
        ring_r = H * (0.04 + 0.16 * burst)
        col = tuple(int(c * a) for c in IRIS)
        lw = max(1, int(H * 0.0028 * (1 - burst)))
        d.ellipse([eye[0] - ring_r, eye[1] - ring_r,
                   eye[0] + ring_r, eye[1] + ring_r], outline=col, width=lw)

    # ---- 左侧品牌字标（简化：仅用于构图核查）----
    #
    # 字标下方现在是「日期 + 每日语录」（取代原固定副标题）。
    # 这里用 ASCII 占位而不是真实中文 —— 本脚本没有加载中文字体，
    # 直接画中文会渲染成豆腐块，反而看不出排版对不对。真实字号
    # 与行距按下式复刻，位置是准的。
    d = ImageDraw.Draw(base, "RGB")
    panel_in = ease_out(seg(progress, 0.56, 0.90))
    if panel_in > 0.6:
        bs = min(W * 0.062, 62.0)
        oy = H * 0.50 - bs / 2
        d.text((W * 0.075, oy), "OASX", fill=TEXT)
        y = oy + bs + 11
        date_s = max(bs * 0.24, 11.0)
        motto_s = max(bs * 0.27, 11.0)
        d.text((W * 0.075 + 2, y), "2026 / 09 / 29  Tue", fill=FAINT)
        y += date_s * 1.25 + 7
        d.text((W * 0.075 + 2, y),
               "the line under the mark", fill=(110, 140, 168))

    # ---- 暗角 ----
    vig = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-W * 0.2, -H * 0.2, W * 1.2, H * 1.2], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(120))
    dark = Image.new("RGB", (W, H), (0, 0, 0))
    base = Image.composite(base, dark, vig)

    return base


def render_deploy(progress, stages=None, status_line="", overall=None,
                  skippable=True, hint_time=0.0):
    """渲染**部署模式**：左栏 = 品牌字标（compact）+ 部署进度面板，右栏 = 立绘。

    复刻 splash_painter.paint 的部署分支：
        brandIn = ease_out(seg(p, 0.10, 0.34))   -> _paintBrandTitle(compact: true)
        panelIn = ease_out(seg(p, 0.56, 0.90))   -> paintSplashPanel(...)
        hintIn  = ease_out(seg(p, 0.30, 0.55))   -> paintSkipHint(...)

    以及 splash_deploy_panel.paintSplashPanel 的新布局常量：
        panelW = 0.36W, left = 0.075W, listTop = 0.28H,
        rowH = min(0.050H, 34), barY 紧跟阶段列表, detailY 跟在进度条后
    """
    if stages is None:
        stages = [("检查运行环境", "done", -1),
                  ("拉取 OAS 仓库", "done", -1),
                  ("安装运行依赖", "running", 0.63),
                  ("启动 OAS 服务", "pending", -1),
                  ("建立连接", "pending", -1)]

    base = render(progress)

    brand_in = ease_out(seg(progress, 0.10, 0.34))
    panel_in = ease_out(seg(progress, 0.56, 0.90))
    if brand_in <= 0:
        return base

    d = ImageDraw.Draw(base, "RGB")

    # ---- 品牌字标（compact）----
    bs = min(W * 0.030, 34.0)
    left = W * 0.075
    title_top = H * 0.135
    ty = title_top - bs / 2
    d.text((left, ty), "OASX", fill=TEXT)
    if brand_in > 0.3:
        d.line([(left, ty + bs + 6), (left + bs * 2.2, ty + bs + 6)],
               fill=ACCENT, width=2)
    if brand_in >= 0.75:
        # 日期 + 语录（真实位置；ASCII 占位，本脚本无中文字体）
        dy = ty + bs + 11
        d.text((left + 2, dy), "2026 / 09 / 29  Tue", fill=FAINT)
        dy += max(bs * 0.24, 11.0) * 1.25 + 7
        d.text((left + 2, dy), "the line under the mark",
               fill=TEXT_DIM)

    if panel_in <= 0:
        return base

    # ---- 部署面板 ----
    panel_w = W * 0.36
    maxw = panel_w * 0.92
    list_top = H * 0.28
    row_h = min(H * 0.050, 34.0)
    dot_r = row_h * 0.105
    label_size = min(W * 0.0105, 12.0)

    for i, (label, state, sp) in enumerate(stages):
        row_t = ease_out(max(0.0, min(1.0, (panel_in - 0.35 - i * 0.09) / 0.45)))
        if row_t <= 0:
            continue
        row_y = list_top + i * row_h
        cx = left + dot_r
        cy = row_y + row_h * 0.32

        # 标记
        if state == "done":
            d.ellipse([cx - dot_r, cy - dot_r, cx + dot_r, cy + dot_r],
                      fill=ACCENT)
        elif state == "running":
            d.ellipse([cx - dot_r * 0.72, cy - dot_r * 0.72,
                       cx + dot_r * 0.72, cy + dot_r * 0.72],
                      fill=WIRE_GLOW)
        else:
            d.ellipse([cx - dot_r * 0.92, cy - dot_r * 0.92,
                       cx + dot_r * 0.92, cy + dot_r * 0.92],
                      outline=(90, 100, 110), width=1)

        lc = {"done": TEXT, "running": WIRE_GLOW,
              "failed": (255, 107, 107), "pending": (110, 122, 130)}[state]
        d.text((cx + dot_r * 2.6, cy - label_size * 0.62), label, fill=lc)

        if state == "running" and sp >= 0:
            pct = f"{round(sp * 100)}%"
            pw = len(pct) * label_size * 0.62
            d.text((left + panel_w - pw, cy - label_size * 0.5), pct, fill=ACCENT)

    # 总进度条
    ov = overall if overall is not None else 0.63
    bar_y = list_top + len(stages) * row_h + H * 0.035
    bar_w = panel_w * 0.78
    d.rectangle([left, bar_y, left + bar_w, bar_y + 3], fill=(50, 58, 64))
    fillw = ov * bar_w
    if fillw > 1:
        d.rectangle([left, bar_y, left + fillw, bar_y + 3], fill=ACCENT)
    d.text((left + bar_w + 12, bar_y - label_size * 0.6),
           f"{round(ov * 100)}%", fill=TEXT)

    # 细节行
    if status_line:
        d.text((left, bar_y + H * 0.055), status_line, fill=(140, 152, 160))

    # ---- 跳过提示（复刻 paintSkipHint）----
    #
    # 呼吸：breath = 0.75 + 0.25*sin(2πt/2.4)，不可跳过时固定 0.8。
    # 位置：底部居中，y = 0.92H。文字后垫径向暗晕保证对比度。
    hint_in = ease_out(seg(progress, 0.30, 0.55))
    if hint_in > 0:
        breath = 0.8 if not skippable else (
            0.75 + 0.25 * math.sin(hint_time * 2 * math.pi / 2.4))
        alpha = breath * hint_in
        hint_text = ("点击任意处或按任意键跳过" if skippable
                     else "正在部署 OAS，请勿关闭窗口")
        # 估算文字宽度（12px 中文字 ≈ 12px/字，含 1.4 字距）
        tw = len(hint_text) * 12 * 1.0
        th = 12
        hx = (W - tw) / 2
        hy = H * 0.92

        # 径向暗晕（用乘法把中心压暗，等效于 painter 里画的暗色径向渐变）
        arr = np.asarray(base).astype(np.float32)
        yy2, xx2 = np.mgrid[0:H, 0:W]
        dd = np.sqrt((xx2 - W / 2) ** 2 + (yy2 - (hy + th / 2)) ** 2)
        halo = np.clip(1 - dd / (tw * 0.62), 0, 1)[..., None]
        dark_amt = halo * (0.55 * hint_in)
        arr = arr * (1 - dark_amt) + np.array([4, 6, 12]) * dark_amt
        base = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(base, "RGB")

        tcol = tuple(int(255 * 0.62 * alpha) for _ in range(3))
        d.text((hx, hy), hint_text, fill=tcol)

    return base


def ratio_report():
    """核查极端宽高比下的贴合行为（cover 策略）。"""
    cases = [("基准 1200×800", 1200, 800),
             ("超宽 2560×800", 2560, 800),
             ("超宽 3440×900", 3440, 900),
             ("窄 900×800", 900, 800),
             ("竖屏 800×1200", 800, 1200),
             ("极窄 640×1000", 640, 1000)]
    print("\n=== 立绘贴合核查（资源 1200×800，cover 策略，artScale=1.0）===")
    print(f"{'场景':<18}{'lt':>9}{'top':>8}{'w':>7}{'h':>7}   结果")
    for name, w_, h_ in cases:
        left, top, w, h = art_rect_cover((w_, h_))
        note = []
        # cover 的判据：贴图必须**两轴都 >= 画布**，否则会出现空白带
        if w < w_ - 0.5:
            note.append(f"⚠ 横向留白 {w_ - w:.0f}px")
        if h < h_ - 0.5:
            note.append(f"⚠ 纵向留白 {h_ - h:.0f}px")
        if left > 0.5:
            note.append(f"⚠ 右留白 {left:.0f}px")
        if not note:
            over_x = -left if left < 0 else 0.0
            over_y = -top if top < 0 else 0.0
            parts = []
            if over_x:
                parts.append(f"左溢出 {over_x:.0f}px")
            if over_y:
                parts.append(f"上下各溢出 {over_y:.0f}px")
            note.append("铺满" + ("（" + "、".join(parts) + "）" if parts else ""))
        print(f"{name:<18}{left:>9.0f}{top:>8.0f}{w:>7.0f}{h:>7.0f}   "
              + "、".join(note))
    print()


def main():
    os.makedirs(OUT, exist_ok=True)
    ratio_report()
    points = [0.00, 0.10, 0.16, 0.22, 0.28, 0.34, 0.42, 0.50, 0.56,
              0.62, 0.66, 0.70, 0.74, 0.78, 0.82, 0.86, 0.90, 0.94, 1.00]
    for p in points:
        im = render(p)
        name = f"snap_{int(round(p*100)):03d}.png"
        im.save(os.path.join(OUT, name))
        print("rendered", name)

    # 额外：睁眼过程条带图（横向拼贴，便于一眼看动作）
    strip_pts = [0.60, 0.64, 0.68, 0.72, 0.76, 0.80, 0.84, 0.88, 0.92, 0.96, 1.0]
    thumbs = []
    for p in strip_pts:
        im = render(p).resize((360, 240), Image.LANCZOS)
        thumbs.append(im)
    strip = Image.new("RGB", (360 * len(thumbs), 240), (0, 0, 0))
    for i, t in enumerate(thumbs):
        strip.paste(t, (i * 360, 0))
    strip.save(os.path.join(OUT, "_strip_eyes.png"))
    print("rendered _strip_eyes.png")

    # ---- 部署模式：验证「字标 + 面板」并行且不重叠 ----
    deploy_pts = [0.30, 0.60, 0.75, 0.90, 1.00]
    for p in deploy_pts:
        im = render_deploy(p, status_line="Cloning into 'OAS'...")
        name = f"deploy_{int(round(p*100)):03d}.png"
        im.save(os.path.join(OUT, name))
        print("rendered", name)

    # ---- 跳过提示：呼吸的一个完整周期（验证位置 / 对比度 / 相位）----
    #
    # hintTime 走 0 → 2.4s 一整圈，配合 p=0.6（hintIn 已满格），
    # 让呼吸幅度完整可见。改 skippable=False 再出一张「部署中」对照。
    for i in range(6):
        ht = 2.4 * i / 6
        im = render_deploy(0.60, status_line="Cloning into 'OAS'...",
                           skippable=True, hint_time=ht)
        name = f"hint_{i}.png"
        im.save(os.path.join(OUT, name))
        print("rendered", name)
    im = render_deploy(0.60, status_line="Cloning into 'OAS'...",
                       skippable=False)
    im.save(os.path.join(OUT, "hint_busy.png"))
    print("rendered hint_busy.png")


if __name__ == "__main__":
    main()
