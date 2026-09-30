#!/usr/bin/env python
"""从参考视频提取「已渲染段」，生成主界面底衬的**逐帧动画**（动画 WebP）。

## 为什么是 flipbook 而不是视频播放

用户给的参考视频（1280×720 HEVC，6.73s）本身就是风格来源 —— 蓝发少女、
青瞳、发丝飘动、眨眼。桌面端播放视频要引入 media_kit 这类原生插件，
手工构建链（无 flutter CLI）加插件的风险不可控。而动画 WebP：

- Flutter 引擎内置解码（Skia/libwebp），`instantiateImageCodec` 直接
  返回多帧 codec，`getNextFrame()` 逐帧推进，零新依赖；
- 单文件（~2-3MB），走既有 `AssetManifest.bin` 同步链；
- 解码失败时 Dart 侧自动回退静态 jpg（`main_bg_muse.jpg`），可观测。

## 段落选择（实测，不是拍的）

对 200 帧逐帧测「少女区域均值差」与「亮度」：

- 0–45 帧：线稿→渲染转变段（亮度 58→139，diff 13–19）—— 不能用
- 48–63 帧：短暂平静
- 70–193 帧：完全渲染，持续微动（发丝 1–17，含**眨眼**）—— 用这段
- 194 帧起：片尾淡出到白网页（crop 均值 127→252）—— 绝对不能用

所以 `SEG_START=70 / SEG_END=193` 是从数据里量出来的边界。

## 乒乓循环

193→70 直接跳切会有发丝位置跳变。改为**正放 + 倒放**：
眨眼正放是闭眼、倒放是睁眼，两者都是自然动作；发丝飘动的逆放
在这个幅度下不可辨。乒乓从构造上保证无缝（首帧 = 末帧的下一帧）。

## 防闪烁

亮度/白平衡增益从锚帧**算一次、全程固定**。若逐帧独立归一，
每帧的直方图抖动会变成肉眼可见的呼吸感 —— 这是逐帧处理的经典坑。

## 帧尺寸 = 740×1120，不是 1480×2240

动画的流畅度由**单帧解码耗时**决定：1480×2240 一帧解码 40–70ms，
撑不住 12fps；740×1120 只要 8–15ms。运动中的画面会掩盖轻微的
柔化（静态海报仍用 1480×2240 的 jpg，两不耽误）。

## 验收

写完必须跑本脚本的内置验收：
1. n_frames 往返一致；
2. 相邻帧均值差 < 1.0（防闪烁）；
3. 抽 6 帧过 `render_home_backdrop.py` 的真实合成管线，
   1280×800 与 1440×900 的次级文字最差对比度 ≥ 4.5:1。

用法：python tools/build_home_backdrop_anim.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_home_backdrop_asset import (  # noqa: E402
    CROP_BOX,
    EDGE_FRAC,
    EDGE_MIN,
    _keep_hue,
    _soft_edges,
)
from render_home_backdrop import measure_text_rows, paint_backdrop  # noqa: E402

#: 动画素材的亮度基准 —— 比静态素材的 43 更低，**必须是**：
#: 静态只验了一个「锚帧瞬间」，而动画的每一帧都会轮到
#: 「发丝亮部扫进文字行」的最差瞬间。实测（1280×800 最紧档）：
#: 目标 43 → 最差帧 3.95:1 ✗；37 → 4.46:1 ✗；35 → （见验收输出）。
#: 往上调之前必须先跑通本脚本的逐帧验收。
TARGET_BRIGHTNESS = 35.0

VIDEO = Path(r"C:\Users\12296\Desktop\96794a0b221a9dc5fe0154a49f78e52f.mp4")

#: 参与循环的源帧区间 [SEG_START, SEG_END]（闭区间）。依据见文件头。
SEG_START = 70
SEG_END = 193

#: 输出帧率与尺寸。12fps 对发丝飘动足够顺滑，解码耗时可控。
OUT_FPS = 12
OUT_SIZE = (740, 1120)

#: WebP 质量。78 在蓝发渐变上无明显色带，单帧 ~25-40KB。
QUALITY = 78

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "src" / "assets" / "images" / "main_bg_muse_anim.webp"


def _read_segment(video: Path) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(video))
    if not cap.isOpened():
        raise RuntimeError(f"打不开视频：{video}")
    frames: list[np.ndarray] = []
    idx = 0
    while True:
        ok, f = cap.read()
        if not ok:
            break
        if SEG_START <= idx <= SEG_END:
            # cv2 给的是 BGR；转 RGB 后与静态素材链一致
            frames.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
        idx += 1
    cap.release()
    n_total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if len(frames) != SEG_END - SEG_START + 1:
        raise RuntimeError(
            f"源帧不足：区间 [{SEG_START},{SEG_END}] 只取到 {len(frames)} 帧"
            f"（视频共 {n_total} 帧）。确认视频文件没换。"
        )
    return frames


def _sample_indices(count: int) -> list[int]:
    """从源帧序列里均匀抽到 OUT_FPS。"""
    src_fps = 29.7  # ffprobe 实测；抽帧按比例即可
    step = src_fps / OUT_FPS
    idx: list[int] = []
    t = 0.0
    while t < count - 1e-6:
        idx.append(min(count - 1, int(round(t))))
        t += step
    # 相邻去重（step < 1 时可能重复）
    out = [idx[0]]
    for i in idx[1:]:
        if i != out[-1]:
            out.append(i)
    return out


def _anchor_gains(frames: list[np.ndarray]) -> tuple[np.ndarray, float]:
    """从锚帧算出**固定**的白平衡与亮度增益（防闪烁，见文件头）。"""
    anchor = frames[len(frames) // 2].astype(np.float32)
    a = anchor[CROP_BOX[1]:CROP_BOX[3], CROP_BOX[0]:CROP_BOX[2]]

    lum = a.mean(axis=2)
    mask = lum >= np.percentile(lum, 97)
    if mask.sum() <= 50:
        wb = np.ones(3, dtype=np.float32)
    else:
        ref = a[mask].mean(axis=0)
        wb = np.clip(ref.mean() / np.maximum(ref, 1e-6), 0.9, 1.15).astype(np.float32)

    after_wb = np.clip(a * wb, 0, 255)
    gain = float(TARGET_BRIGHTNESS / max(after_wb.mean(), 1e-6))
    return wb, gain


def _process_frame(frame: np.ndarray, wb: np.ndarray, gain: float) -> Image.Image:
    a = frame[CROP_BOX[1]:CROP_BOX[3], CROP_BOX[0]:CROP_BOX[2]].astype(np.float32)
    a = np.clip(a * wb * gain, 0, 255)
    a = _keep_hue(a)
    img = Image.fromarray(a.astype(np.uint8))
    img = img.filter(ImageFilter.MedianFilter(3))
    img = img.resize(OUT_SIZE, Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=45, threshold=3))
    arr = _soft_edges(np.asarray(img).astype(np.float32))
    return Image.fromarray(arr.astype(np.uint8))


def _ping_pong(items: list[Image.Image]) -> list[Image.Image]:
    """正放 + 倒放（去掉首尾重复帧），从构造上无缝。"""
    return items + items[-2:0:-1]


def _verify(webp: Path, expect_frames: int) -> None:
    im = Image.open(webp)
    n = getattr(im, "n_frames", 1)
    if n != expect_frames:
        raise RuntimeError(f"编码往返不一致：期望 {expect_frames} 帧，实读 {n} 帧")

    # 防闪烁：逐帧均值必须平稳
    means: list[float] = []
    for i in range(n):
        im.seek(i)
        means.append(float(np.asarray(im.convert("RGB"), dtype=np.float32).mean()))
    max_step = max(abs(b - a) for a, b in zip(means, means[1:]))
    print(f"帧数 {n}  文件 {webp.stat().st_size / 1e6:.2f}MB  "
          f"亮度 {min(means):.1f}–{max(means):.1f}  相邻帧均值最大跳变 {max_step:.2f}")
    if max_step > 1.0:
        raise RuntimeError(f"相邻帧均值跳变 {max_step:.2f} > 1.0，会看到呼吸感，禁止交付")

    # 可读性：过真实合成管线。1280×800 是最紧档（立绘相对窗口最大），
    # 对它做**每 4 帧一测**的密集验收；1440×900 抽 6 帧做健全性确认。
    worst_overall = 1e9
    worst_where = ""
    dense = list(range(0, n, 4))
    sparse6 = list(range(0, n, max(1, n // 6)))[:6]
    for i in dense:
        im.seek(i)
        art = im.convert("RGB")
        bg = paint_backdrop(1280, 800, art)
        _, sub = measure_text_rows(bg, 1280, 800)
        if sub < worst_overall:
            worst_overall, worst_where = sub, f"帧{i} @ 1280x800"
    for i in sparse6:
        im.seek(i)
        art = im.convert("RGB")
        bg = paint_backdrop(1440, 900, art)
        _, sub = measure_text_rows(bg, 1440, 900)
        if sub < worst_overall:
            worst_overall, worst_where = sub, f"帧{i} @ 1440x900"
        print(f"  帧{i:3d} @ 1440x900: 次级 {sub:5.2f}:1")
    if worst_overall < 4.5:
        raise RuntimeError(
            f"动画帧最差次级对比度 {worst_overall:.2f}:1 < 4.5:1"
            f"（最差在 {worst_where}），需要下调 TARGET_BRIGHTNESS 后重跑。"
        )
    print(f"可读性验收 ✓（密集 25 帧 + 抽样 6 帧，最差 {worst_overall:.2f}:1 ≥ 4.5:1，"
          f"位于 {worst_where}）")


def main() -> int:
    if not VIDEO.is_file():
        print(f"错误：视频不存在 {VIDEO}", file=sys.stderr)
        return 1

    frames = _read_segment(VIDEO)
    idx = _sample_indices(len(frames))
    print(f"源段 [{SEG_START},{SEG_END}] {len(frames)} 帧 → 采样 {len(idx)} 帧 @ {OUT_FPS}fps")

    wb, gain = _anchor_gains(frames)
    print(f"锚帧增益：wb={np.round(wb, 3).tolist()} 亮度×{gain:.3f}（全程固定，防闪烁）")

    processed = [_process_frame(frames[i], wb, gain) for i in idx]
    loop = _ping_pong(processed)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    duration = round(1000 / OUT_FPS)
    loop[0].save(
        OUT_PATH,
        "WEBP",
        save_all=True,
        append_images=loop[1:],
        duration=duration,
        loop=0,  # 无限循环
        quality=QUALITY,
        method=4,
    )
    print(f"已写入 {OUT_PATH}（{len(loop)} 帧，每帧 {duration}ms）")

    _verify(OUT_PATH, len(loop))
    print()
    print("下一步：确认 Dart 侧 _kAnimAsset 指向该文件，并重跑构建部署链。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
