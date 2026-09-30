#!/usr/bin/env python
"""从重画的 AI 视频生成主界面底衬**逐帧动画**（第二版）。

## 为什么换素材源

第一版取自用户参考视频（1280×720）的「已渲染段」。它有两个无法在
处理链内解决的问题：

1. 源分辨率天花板 1280×720，立绘清晰度不足；
2. 为了让半透明面板下的文字达到 WCAG AA，素材被压到均值 35 ——
   「蓝发少女」压成了「隐约可见的暗影」（用户反馈：背景只有黑块、
   没有参考的风格）。

第二版改用 **AI 重画的 1176×1764 竖幅视频**（image-to-video，
首帧为按用户提示词重画的锚帧图）：

- 原生竖幅、原生偏暗偏冷（少女区 44-48），处理链几乎不用压亮度；
- 「蓝色线框线稿 → 扫描实体化 → 3D 渲染」的完整叙事由视频前半段
  承担，**主页循环只取渲染完成后的微动段** —— 线稿叙事留给启动页
  （启动页本就有这段自绘动画），主页背景如果每 5 秒重演一次实体化
  会持续打断工作界面。

## 段落选择（实测）

对 121 帧逐帧测少女区域（x>0.3W）均值与相邻帧差：

- 0-12 帧：线稿态（帧差 2.3-3.2）
- 15-84 帧：扫描实体化（帧差 6.5-9.2，扫描带横扫）—— 不进主页循环
- **88-120 帧：实体化完成后的微动**（帧差 2.1-3.0，亮度 43.7-48.0
  平稳）—— 用这段

## 水印

生成模型的输出在**右下角固定位置**带「AI生成」角标（实测右下 8%
区域峰值亮度 186-240，帧间稳定存在）。裁掉底部 7% 彻底移除；
为保持 740:1120 的画幅比，左右各对称裁 46px（少女构图居中，
对称裁不改变构图重心）。

## 防闪烁 / 乒乓 / 帧尺寸

与第一版同（`build_home_backdrop_anim.py`）：增益从锚帧算一次
全程固定；乒乓循环从构造上无缝；740×1120 保证单帧解码 8-15ms。

## 验收（写完必须全过）

1. n_frames 往返一致；
2. 相邻帧均值跳变 < 1.0；
3. 逐帧过 `render_home_backdrop.py` 的**真实几何**合成
   （左栏 340 + 详情面板到右缘），四档分辨率次级文字 ≥ 4.5:1。

用法：python tools/build_home_backdrop_anim_v2.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_home_backdrop_asset import (  # noqa: E402
    _keep_hue,
    _soft_edges,
)
from render_home_backdrop import paint_backdrop  # noqa: E402

#: 生成视频（image-to-video，首帧 = 重画的锚帧线稿图）。
VIDEO = Path(
    r"C:\Users\12296\Desktop\yys\OASX-Neo\tools\preview\redraw"
    r"\Preserve_the_input_image_s_EXA_2026-09-29T18-19-10.mp4"
)

#: 参与循环的源帧区间 [SEG_START, SEG_END]（闭区间）。
#: 实体化完成后的微动段。依据见文件头的逐帧实测。
SEG_START = 88
SEG_END = 120

#: 裁剪（源帧 1176×1764）：头肩特写。
#:
#: 完整竖幅里少女偏右（脸中心 x≈0.62），直接整幅显示会让脸一半
#: 落在窗口外。这里裁出「脸+肩+左侧发丝」的特写，同时 y 上限 0.78
#: 顺带**彻底避开底部 7% 的水印**（生成模型的固定角标）。
#: 裁后 847×1288，比例 0.6576 ≈ 740/1120（0.6607），resize 消化 0.5%。
CROP_BOX = (0.28, 0.05, 1.0, 0.78)  # (x0, y0, x1, y1) 归一化

#: 素材内**水平渐变压暗**：左侧（会透过面板垫在文字下）压暗，
#: 右侧（落在无面板的舞台里）保持全亮。
#:
#: 全局压暗会把脸也压没（第一版素材的教训：均值 35 = 黑块）。
#: 而显示几何是「右侧舞台全亮 + 左侧透 86% 面板」，所以压暗也应该
#: 只作用于左侧 —— 渐变从 nx=0.45（增益 0.55）平滑升到 nx=0.75
#: （增益 1.0），脸区（nx≥0.62 主区）完全不受影响，发丝高光在
#: 面板区的透出亮度约减半，文字对比度因此达标。
DIM_LEFT_GAIN = 0.55
DIM_GRAD_START = 0.45
DIM_GRAD_END = 0.75

#: 输出帧率与尺寸（与第一版一致：解码耗时决定帧率上限）。
OUT_FPS = 12
OUT_SIZE = (740, 1120)

#: WebP 质量。
QUALITY = 78

#: 动画素材亮度目标。
#:
#: 第一版压到 35 是为了对旧素材（亮部集中在发丝、均值 43 起）做
#: 全局压制 —— 结果风格尽失。新素材原生偏暗偏冷（少女区 44-48），
#: 亮部集中在脸与发丝高光、背景更黑，同样可读性预算下可以给到
#: **50**：人物可辨、青蓝发色明确。往上加之前必须先过本脚本的
#: 逐帧真实几何验收。
TARGET_BRIGHTNESS = 50.0

ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = ROOT / "src" / "assets" / "images" / "main_bg_muse_anim.webp"

#: 真实几何复核的四档分辨率（与 render_home_backdrop.py 对齐）。
REVIEW_SIZES = [(1280, 800), (1440, 900), (1920, 1080), (2560, 1440)]


def read_segment(video: Path) -> list[np.ndarray]:
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
            frames.append(cv2.cvtColor(f, cv2.COLOR_BGR2RGB))
        idx += 1
    cap.release()
    need = SEG_END - SEG_START + 1
    if len(frames) != need:
        raise RuntimeError(f"源帧不足：区间 [{SEG_START},{SEG_END}] 只取到 {len(frames)} 帧")
    return frames


def crop_frame(frame: np.ndarray) -> np.ndarray:
    """头肩特写裁剪（含水印规避），见 CROP_BOX 注释。"""
    h, w = frame.shape[:2]
    x0 = int(w * CROP_BOX[0])
    y0 = int(h * CROP_BOX[1])
    x1 = int(w * CROP_BOX[2])
    y1 = int(h * CROP_BOX[3])
    return frame[y0:y1, x0:x1]


def sample_indices(count: int) -> list[int]:
    """从源帧序列均匀抽到 OUT_FPS（相邻去重）。"""
    src_fps = 24.0  # 实测 24fps
    step = src_fps / OUT_FPS
    idx: list[int] = []
    t = 0.0
    while t < count - 1e-6:
        idx.append(min(count - 1, int(round(t))))
        t += step
    out = [idx[0]]
    for i in idx[1:]:
        if i != out[-1]:
            out.append(i)
    return out


def anchor_gains(frames: list[np.ndarray]) -> tuple[np.ndarray, float]:
    """从锚帧算**固定**的白平衡与亮度增益（防闪烁）。"""
    anchor = frames[len(frames) // 2].astype(np.float32)
    lum = anchor.mean(axis=2)
    mask = lum >= np.percentile(lum, 97)
    if mask.sum() <= 50:
        wb = np.ones(3, dtype=np.float32)
    else:
        ref = anchor[mask].mean(axis=0)
        wb = np.clip(ref.mean() / np.maximum(ref, 1e-6), 0.9, 1.15).astype(np.float32)
    after_wb = np.clip(anchor * wb, 0, 255)
    gain = float(TARGET_BRIGHTNESS / max(after_wb.mean(), 1e-6))
    return wb, gain


def process_frame(frame: np.ndarray, wb: np.ndarray, gain: float) -> Image.Image:
    a = crop_frame(frame).astype(np.float32)
    a = np.clip(a * wb * gain, 0, 255)
    # 水平渐变压暗（左侧头发区），见 DIM_LEFT_GAIN 注释。
    h, w = a.shape[:2]
    nx = np.linspace(0.0, 1.0, w, dtype=np.float32)
    dim = np.where(
        nx <= DIM_GRAD_START,
        DIM_LEFT_GAIN,
        np.where(
            nx >= DIM_GRAD_END,
            1.0,
            DIM_LEFT_GAIN
            + (1.0 - DIM_LEFT_GAIN) * (nx - DIM_GRAD_START) / (DIM_GRAD_END - DIM_GRAD_START),
        ),
    )
    a = np.clip(a * dim[None, :, None], 0, 255)
    a = _keep_hue(a)
    img = Image.fromarray(a.astype(np.uint8))
    img = img.filter(ImageFilter.MedianFilter(3))
    img = img.resize(OUT_SIZE, Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=45, threshold=3))
    arr = _soft_edges(np.asarray(img).astype(np.float32))
    return Image.fromarray(arr.astype(np.uint8))


def ping_pong(items: list[Image.Image]) -> list[Image.Image]:
    """正放 + 倒放（去掉首尾重复帧），从构造上无缝。"""
    return items + items[-2:0:-1]


def verify_real_geometry(path: Path) -> float:
    """真实几何逐帧可读性验收（左栏 340 + 详情面板到右缘）。

    构图常量（anchor / opacity / panel alpha）以 measure_real_geometry
    的默认值为准 —— Dart 侧与测量脚本两侧必须同步改，见该模块头注。
    """
    from measure_real_geometry import review_art
    worst, where = review_art(path)
    print(f"真实几何最差次级 {worst:.2f}:1（位于 {where}）")
    return worst


def main() -> int:
    if not VIDEO.is_file():
        print(f"错误：视频不存在 {VIDEO}", file=sys.stderr)
        return 1

    frames = read_segment(VIDEO)
    idx = sample_indices(len(frames))
    print(f"源段 [{SEG_START},{SEG_END}] {len(frames)} 帧 → 采样 {len(idx)} 帧 @ {OUT_FPS}fps")

    wb, gain = anchor_gains(frames)
    print(f"锚帧增益：wb={np.round(wb, 3).tolist()} 亮度×{gain:.3f}（全程固定，防闪烁）")

    processed = [process_frame(frames[i], wb, gain) for i in idx]
    loop = ping_pong(processed)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    duration = round(1000 / OUT_FPS)
    loop[0].save(
        OUT_PATH,
        "WEBP",
        save_all=True,
        append_images=loop[1:],
        duration=duration,
        loop=0,
        quality=QUALITY,
        method=4,
    )
    print(f"已写入 {OUT_PATH}（{len(loop)} 帧，每帧 {duration}ms）")

    # ---- 验收 ----
    im = Image.open(OUT_PATH)
    n = getattr(im, "n_frames", 1)
    if n != len(loop):
        raise RuntimeError(f"编码往返不一致：期望 {len(loop)} 帧，实读 {n} 帧")

    means: list[float] = []
    for i in range(n):
        im.seek(i)
        means.append(float(np.asarray(im.convert("RGB"), dtype=np.float32).mean()))
    max_step = max(abs(b - a) for a, b in zip(means, means[1:]))
    print(f"帧数 {n}  文件 {OUT_PATH.stat().st_size / 1e6:.2f}MB  "
          f"亮度 {min(means):.1f}–{max(means):.1f}  相邻帧均值最大跳变 {max_step:.2f}")
    if max_step > 1.0:
        raise RuntimeError(f"相邻帧均值跳变 {max_step:.2f} > 1.0，会看到呼吸感")

    worst = verify_real_geometry(OUT_PATH)
    if worst < 4.5:
        raise RuntimeError(
            f"真实几何下最差次级对比度 {worst:.2f}:1 < 4.5:1，"
            "需要下调 TARGET_BRIGHTNESS 或调整构图常量后重跑。"
        )
    print(f"可读性验收 ✓（密集逐帧，最差 {worst:.2f}:1 ≥ 4.5:1）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
