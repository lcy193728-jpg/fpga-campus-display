#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""最终版TF卡素材管理器。

板端协议保持不变：图片仍使用根目录FAT32大写8.3短名，迎新音乐仍写入
固定物理LBA 300000。此模块只在PC端完成素材转换、命名、写入和校验。
"""

from __future__ import annotations

import ctypes
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import wave

try:
    from PIL import Image, ImageOps
except ImportError:
    Image = None
    ImageOps = None


IMAGE_SIZE = (640, 480)
BMP_FILE_SIZE = 54 + IMAGE_SIZE[0] * IMAGE_SIZE[1] * 3
WAV_START_LBA = 300000
WAV_SECTORS = 38464
WAV_REGION_BYTES = WAV_SECTORS * 512
PCM_BYTES_PER_SECOND = 48000 * 2

SCENE_SLOTS = {
    "迎新场景": [(f"迎新图片{i}", f"WEL{i}.BMP") for i in range(1, 9)],
    "会议场景": [(f"会议议程{i}", f"MEET{i}.BMP") for i in range(1, 4)],
    "抢答场景": [
        ("题目1", "QUIZ1.BMP"), ("题目2", "QUIZ2.BMP"),
        ("题目3", "QUIZ3.BMP"), ("1号队伍", "QUIZ4.BMP"),
        ("2号队伍", "QUIZ5.BMP"), ("3号队伍", "QUIZ6.BMP"),
        ("4号队伍", "QUIZ7.BMP"), ("比赛结束页", "QUIZ8.BMP"),
    ],
    "应急场景": [(f"应急图片{i}", f"ALM{i}.BMP") for i in range(1, 9)],
}


def sha256_file(path: os.PathLike[str] | str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_bmp(path: os.PathLike[str] | str) -> dict[str, int]:
    with open(path, "rb") as stream:
        header = stream.read(54)
    if len(header) != 54 or header[:2] != b"BM":
        raise ValueError("不是有效的Windows BMP文件")
    file_size = struct.unpack_from("<I", header, 2)[0]
    pixel_offset = struct.unpack_from("<I", header, 10)[0]
    dib_size = struct.unpack_from("<I", header, 14)[0]
    width = struct.unpack_from("<i", header, 18)[0]
    height = struct.unpack_from("<i", header, 22)[0]
    planes = struct.unpack_from("<H", header, 26)[0]
    bit_count = struct.unpack_from("<H", header, 28)[0]
    compression = struct.unpack_from("<I", header, 30)[0]
    actual_size = os.path.getsize(path)
    if (file_size != actual_size or pixel_offset != 54 or dib_size != 40 or
            width != 640 or height != 480 or planes != 1 or
            bit_count != 24 or compression != 0 or actual_size != BMP_FILE_SIZE):
        raise ValueError(
            "BMP规格不符合板端协议：必须为640×480、24bit、BI_RGB、正高度、54字节头")
    return {
        "width": width, "height": height, "bits": bit_count,
        "file_size": actual_size,
    }


def convert_image(source: os.PathLike[str] | str,
                  destination: os.PathLike[str] | str,
                  fit_mode: str = "完整显示（黑边）") -> dict[str, object]:
    """转换成板端唯一推荐的640×480/24bit/BI_RGB BMP。"""
    if Image is None:
        raise RuntimeError("缺少Pillow，请执行：pip install pillow")
    source = Path(source)
    destination = Path(destination)
    with Image.open(source) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")
        if fit_mode == "居中裁剪":
            result = ImageOps.fit(image, IMAGE_SIZE, method=Image.Resampling.LANCZOS)
        else:
            result = ImageOps.contain(image, IMAGE_SIZE, method=Image.Resampling.LANCZOS)
            canvas = Image.new("RGB", IMAGE_SIZE, (0, 0, 0))
            canvas.paste(result, ((640 - result.width) // 2, (480 - result.height) // 2))
            result = canvas
        destination.parent.mkdir(parents=True, exist_ok=True)
        result.save(destination, format="BMP")
    info = parse_bmp(destination)
    info["sha256"] = sha256_file(destination)
    return info


def install_image(source: os.PathLike[str] | str,
                  card_root: os.PathLike[str] | str,
                  target_name: str,
                  fit_mode: str) -> dict[str, object]:
    """先在同一卷生成临时文件，校验通过后再替换正式槽位。"""
    root = Path(card_root)
    if not root.is_dir():
        raise ValueError("TF卡盘符不存在")
    if target_name not in {name for slots in SCENE_SLOTS.values() for _, name in slots}:
        raise ValueError("目标文件名不属于最终版素材槽位")
    fd, temp_name = tempfile.mkstemp(prefix="FPGA_", suffix=".TMP", dir=root)
    os.close(fd)
    temp_path = Path(temp_name)
    target = root / target_name
    try:
        info = convert_image(source, temp_path, fit_mode)
        os.replace(temp_path, target)
        verified = parse_bmp(target)
        if sha256_file(target) != info["sha256"]:
            raise IOError("写入后SHA-256校验不一致")
        verified["sha256"] = info["sha256"]
        verified["path"] = str(target)
        return verified
    finally:
        if temp_path.exists():
            temp_path.unlink()


def scan_slots(card_root: os.PathLike[str] | str) -> list[tuple[str, str, str]]:
    root = Path(card_root)
    rows = []
    for scene, slots in SCENE_SLOTS.items():
        for label, filename in slots:
            path = root / filename
            if not path.exists():
                status = "缺少"
            else:
                try:
                    parse_bmp(path)
                    status = "有效"
                except Exception as exc:
                    status = "不合格：" + str(exc)
            rows.append((scene, label + " / " + filename, status))
    return rows


def prepare_audio(source: os.PathLike[str] | str,
                  destination: os.PathLike[str] | str) -> dict[str, object]:
    """转换为48kHz/16bit/mono裸PCM；优先使用ffmpeg。"""
    source = Path(source)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
                   "-i", str(source), "-vn", "-ac", "1", "-ar", "48000",
                   "-c:a", "pcm_s16le", "-f", "s16le", str(destination)]
        result = subprocess.run(command, capture_output=True, text=True,
                                encoding="utf-8", errors="replace")
        if result.returncode:
            raise RuntimeError("音频转换失败：" + result.stderr.strip())
    else:
        # 无ffmpeg时仍允许导入已符合协议的PCM WAV。
        try:
            with wave.open(str(source), "rb") as wav:
                if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(),
                        wav.getcomptype()) != (1, 2, 48000, "NONE"):
                    raise ValueError
                with open(destination, "wb") as raw:
                    while True:
                        block = wav.readframes(48000)
                        if not block:
                            break
                        raw.write(block)
        except (wave.Error, ValueError):
            raise RuntimeError(
                "未找到ffmpeg；只能导入48kHz、16bit、单声道PCM WAV") from None

    size = destination.stat().st_size
    if size == 0:
        raise ValueError("转换后的音频为空")
    if size > WAV_REGION_BYTES:
        destination.unlink(missing_ok=True)
        raise ValueError("音频超过固定音乐区容量（最长约205.1秒），请先裁剪")
    if size & 1:
        destination.unlink(missing_ok=True)
        raise ValueError("转换后的PCM长度不是完整的16bit采样")

    # 板端的total_sectors为固定常量，无法获知本次导入歌曲的真实长度。
    # 将歌曲在PC端循环铺满整个音乐区，避免短歌曲播放后出现长时间静音。
    source_size = size
    source_seconds = source_size / PCM_BYTES_PER_SECOND
    if source_size < WAV_REGION_BYTES:
        pcm = destination.read_bytes()
        repeat = (WAV_REGION_BYTES + source_size - 1) // source_size
        destination.write_bytes((pcm * repeat)[:WAV_REGION_BYTES])
        size = WAV_REGION_BYTES
    return {
        "bytes": size,
        "source_bytes": source_size,
        "source_seconds": source_seconds,
        "region_seconds": size / PCM_BYTES_PER_SECOND,
        "sha256": sha256_file(destination),
        "path": str(destination),
    }


def windows_volume_info(root: str) -> tuple[str, str]:
    if os.name != "nt":
        return "", ""
    volume_name = ctypes.create_unicode_buffer(261)
    fs_name = ctypes.create_unicode_buffer(261)
    serial = ctypes.c_uint()
    max_component = ctypes.c_uint()
    flags = ctypes.c_uint()
    ok = ctypes.windll.kernel32.GetVolumeInformationW(
        root, volume_name, len(volume_name), ctypes.byref(serial),
        ctypes.byref(max_component), ctypes.byref(flags), fs_name, len(fs_name))
    if not ok:
        return "", ""
    return volume_name.value, fs_name.value


def candidate_drives() -> list[tuple[str, str, str]]:
    rows = []
    if os.name != "nt":
        return rows
    for letter in "DEFGHIJKLMNOPQRSTUVWXYZ":
        root = letter + ":\\"
        if not os.path.exists(root):
            continue
        drive_type = ctypes.windll.kernel32.GetDriveTypeW(root)
        label, fs_name = windows_volume_info(root)
        # 移动盘全部列出以便提示格式；固定盘仅列FAT32，避免把普通系统盘
        # 放进高风险的裸扇区写入列表。部分USB读卡器会被Windows识别为3。
        if drive_type == 2 or (drive_type == 3 and fs_name.upper() == "FAT32"):
            rows.append((root, label or "无卷标", fs_name or "未知"))
    return rows


def physical_disk_for_drive(root: str) -> int | None:
    """通过Windows存储管理查询盘符对应的物理磁盘号。"""
    if os.name != "nt" or len(root) < 1:
        return None
    letter = root[0].upper()
    script = "(Get-Partition -DriveLetter '%s').DiskNumber" % letter
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        return None
    for line in result.stdout.splitlines():
        if line.strip().isdigit():
            return int(line.strip())
    return None


class MediaManagerFrame(ttk.Frame):
    def __init__(self, master, script_dir: os.PathLike[str] | str):
        super().__init__(master, padding=12)
        self.script_dir = Path(script_dir)
        self.card_root = tk.StringVar()
        self.card_summary = tk.StringVar(value="未选择TF卡")
        self.scene = tk.StringVar(value="迎新场景")
        self.slot = tk.StringVar()
        self.fit_mode = tk.StringVar(value="完整显示（黑边）")
        self.image_source = tk.StringVar()
        self.audio_source = tk.StringVar()
        self.audio_raw = tk.StringVar()
        self.audio_info = tk.StringVar(value="尚未转换音频")
        self.disk_number = tk.StringVar()
        self._drive_map = {}
        self._build()
        self.refresh_drives()
        self.update_slots()

    def _build(self):
        card = ttk.LabelFrame(self, text="1. 选择TF卡（最终版要求FAT32）", padding=10)
        card.pack(fill="x")
        self.drive_box = ttk.Combobox(card, textvariable=self.card_root, state="readonly", width=48)
        self.drive_box.grid(row=0, column=0, sticky="we")
        self.drive_box.bind("<<ComboboxSelected>>", lambda _e: self.on_drive_selected())
        ttk.Button(card, text="刷新盘符", command=self.refresh_drives).grid(row=0, column=1, padx=8)
        ttk.Button(card, text="检查全部槽位", command=self.audit_card).grid(row=0, column=2)
        ttk.Label(card, textvariable=self.card_summary).grid(row=1, column=0, columnspan=3, sticky="w", pady=(6, 0))
        card.columnconfigure(0, weight=1)

        image_box = ttk.LabelFrame(self, text="2. 图片素材：自动转换、命名并写入根目录", padding=10)
        image_box.pack(fill="x", pady=10)
        ttk.Label(image_box, text="场景").grid(row=0, column=0, sticky="w")
        scene_box = ttk.Combobox(image_box, textvariable=self.scene, state="readonly",
                                 values=list(SCENE_SLOTS), width=14)
        scene_box.grid(row=0, column=1, padx=6, sticky="w")
        scene_box.bind("<<ComboboxSelected>>", lambda _e: self.update_slots())
        ttk.Label(image_box, text="槽位").grid(row=0, column=2, sticky="w")
        self.slot_box = ttk.Combobox(image_box, textvariable=self.slot, state="readonly", width=28)
        self.slot_box.grid(row=0, column=3, padx=6, sticky="w")
        ttk.Label(image_box, text="适配方式").grid(row=0, column=4, sticky="w")
        ttk.Combobox(image_box, textvariable=self.fit_mode, state="readonly", width=18,
                     values=("完整显示（黑边）", "居中裁剪")).grid(row=0, column=5, padx=6)
        ttk.Entry(image_box, textvariable=self.image_source).grid(row=1, column=0, columnspan=5,
                                                                  sticky="we", pady=(10, 0))
        ttk.Button(image_box, text="选择图片", command=self.choose_image).grid(row=1, column=5, padx=6, pady=(10, 0))
        ttk.Button(image_box, text="转换、写入并校验", command=self.write_image).grid(
            row=2, column=0, columnspan=6, sticky="we", pady=(8, 0))
        image_box.columnconfigure(3, weight=1)

        audio_box = ttk.LabelFrame(self, text="3. 迎新音乐：转换为48kHz/16bit/单声道裸PCM", padding=10)
        audio_box.pack(fill="x")
        ttk.Entry(audio_box, textvariable=self.audio_source).grid(row=0, column=0, columnspan=4, sticky="we")
        ttk.Button(audio_box, text="选择音频", command=self.choose_audio).grid(row=0, column=4, padx=6)
        ttk.Button(audio_box, text="转换并检查", command=self.convert_audio).grid(row=0, column=5)
        ttk.Label(audio_box, textvariable=self.audio_info).grid(row=1, column=0, columnspan=6, sticky="w", pady=6)
        ttk.Label(audio_box, text="物理磁盘号").grid(row=2, column=0, sticky="w")
        ttk.Entry(audio_box, textvariable=self.disk_number, width=8).grid(row=2, column=1, sticky="w")
        ttk.Label(audio_box, text="自动识别；写卡需管理员权限。图片更新后应最后重写音乐。",
                  foreground="#8a4b08").grid(row=2, column=2, columnspan=3, sticky="w")
        ttk.Button(audio_box, text="安全写入音乐并回读校验", command=self.write_audio).grid(row=2, column=5)
        audio_box.columnconfigure(0, weight=1)

        self.log = tk.Text(self, height=11, wrap="word")
        self.log.pack(fill="both", expand=True, pady=(10, 0))
        self._log("说明：本工具不会修改FPGA位流；图片按场景自动生成大写8.3短名。")

    def _log(self, message: str):
        stamp = time.strftime("%H:%M:%S")
        self.log.insert("end", f"[{stamp}] {message}\n")
        self.log.see("end")

    def refresh_drives(self):
        rows = candidate_drives()
        self._drive_map = {f"{root}  [{fs_name}]  {label}": root for root, label, fs_name in rows}
        self.drive_box["values"] = list(self._drive_map)
        if rows and self.card_root.get() not in self._drive_map:
            self.card_root.set(next(iter(self._drive_map)))
            self.on_drive_selected()
        elif not rows:
            self.card_summary.set("未找到候选盘符；请插入TF卡后刷新")

    def selected_root(self) -> str:
        value = self.card_root.get()
        root = self._drive_map.get(value, value)
        if not root:
            raise ValueError("请先选择TF卡")
        label, fs_name = windows_volume_info(root)
        if fs_name.upper() != "FAT32":
            raise ValueError(f"所选卷为{fs_name or '未知格式'}，最终版要求FAT32，已拒绝写入")
        return root

    def on_drive_selected(self):
        value = self.card_root.get()
        root = self._drive_map.get(value, value)
        label, fs_name = windows_volume_info(root)
        disk = physical_disk_for_drive(root)
        if disk is not None:
            self.disk_number.set(str(disk))
        self.card_summary.set(f"{root}  卷标：{label or '无'}  文件系统：{fs_name or '未知'}  "
                              f"物理磁盘：{disk if disk is not None else '未识别'}")

    def update_slots(self):
        values = [f"{label} → {name}" for label, name in SCENE_SLOTS[self.scene.get()]]
        self.slot_box["values"] = values
        self.slot.set(values[0])

    def choose_image(self):
        path = filedialog.askopenfilename(
            title="选择图片", filetypes=[("图片", "*.jpg *.jpeg *.png *.bmp *.webp"), ("所有文件", "*.*")])
        if path:
            self.image_source.set(path)

    def _target_name(self) -> str:
        index = self.slot_box.current()
        if index < 0:
            index = 0
        return SCENE_SLOTS[self.scene.get()][index][1]

    def write_image(self):
        try:
            root = self.selected_root()
            source = self.image_source.get()
            if not source or not os.path.isfile(source):
                raise ValueError("请先选择有效图片")
            target = self._target_name()
            if not messagebox.askyesno("确认写入", f"将图片转换并写入：\n{root}{target}\n\n"
                                                   "若槽位已有图片，将被替换。是否继续？"):
                return
            info = install_image(source, root, target, self.fit_mode.get())
            self._log(f"图片写入成功：{target}，{info['file_size']}字节，SHA-256 {info['sha256'][:16]}…")
            self._log("提示：音乐位于裸扇区；图片变更完成后请重新执行一次音乐安全写入。")
            messagebox.showinfo("完成", f"{target} 已写入并通过格式及哈希校验。")
        except Exception as exc:
            self._log("图片写入失败：" + str(exc))
            messagebox.showerror("图片写入失败", str(exc))

    def audit_card(self):
        try:
            root = self.selected_root()
            rows = scan_slots(root)
            valid = sum(status == "有效" for _, _, status in rows)
            missing = sum(status == "缺少" for _, _, status in rows)
            invalid = len(rows) - valid - missing
            self._log(f"素材检查：有效{valid}，缺少{missing}，不合格{invalid}。")
            for scene, slot, status in rows:
                if status.startswith("不合格"):
                    self._log(f"  {scene} / {slot}：{status}")
            messagebox.showinfo("槽位检查", f"有效：{valid}\n缺少：{missing}\n不合格：{invalid}")
        except Exception as exc:
            messagebox.showerror("检查失败", str(exc))

    def choose_audio(self):
        path = filedialog.askopenfilename(
            title="选择迎新音乐", filetypes=[("音频", "*.wav *.mp3 *.flac *.m4a *.aac *.ogg"),
                                               ("所有文件", "*.*")])
        if path:
            self.audio_source.set(path)

    def convert_audio(self):
        try:
            source = self.audio_source.get()
            if not source or not os.path.isfile(source):
                raise ValueError("请先选择有效音频")
            out_dir = Path(tempfile.gettempdir()) / "fpga_tf_media_manager"
            out_path = out_dir / "welcome_48k_mono.raw"
            info = prepare_audio(source, out_path)
            self.audio_raw.set(str(out_path))
            self.audio_info.set(
                f"已转换：原音频{info['source_seconds']:.1f}秒，已循环铺满"
                f"{info['region_seconds']:.1f}秒音乐区 / {info['bytes'] / 1024 / 1024:.2f}MiB / "
                f"SHA-256 {info['sha256'][:16]}…")
            self._log(self.audio_info.get())
        except Exception as exc:
            self.audio_raw.set("")
            self.audio_info.set("转换失败：" + str(exc))
            messagebox.showerror("音频转换失败", str(exc))

    def write_audio(self):
        try:
            root = self.selected_root()
            raw = self.audio_raw.get()
            if not raw or not os.path.isfile(raw):
                raise ValueError("请先点击“转换并检查”")
            if not self.disk_number.get().isdigit():
                raise ValueError("无法确定物理磁盘号，请检查盘符或手动填写")
            disk = int(self.disk_number.get())
            auto_disk = physical_disk_for_drive(root)
            if auto_disk is not None and auto_disk != disk:
                raise ValueError("填写的物理磁盘号与所选TF卡盘符不一致")
            if not messagebox.askyesno(
                    "高风险操作确认",
                    f"即将向物理磁盘 {disk} 的LBA {WAV_START_LBA}写入迎新音乐。\n"
                    "工具会先检查FAT32分配状态、备份原音乐区并回读校验。\n\n"
                    "请再次确认所选设备确为TF卡，是否继续？"):
                return
            backup_dir = Path.home() / "Documents" / "FPGA_TF_Backups"
            backup = backup_dir / time.strftime("music_lba300000_%Y%m%d_%H%M%S.bin")
            script = self.script_dir / "sdcard_music.py"
            command = [sys.executable, str(script), "--disk", str(disk),
                       "--lba", str(WAV_START_LBA), "--sectors", str(WAV_SECTORS),
                       "--raw", raw, "--write", "--force", "--skip-probe",
                       "--backup", str(backup)]
            self._log("开始安全检查并写入音乐，请勿拔出TF卡……")
            self.update_idletasks()
            result = subprocess.run(command, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace")
            self._log(result.stdout.strip() or result.stderr.strip())
            if result.returncode:
                if result.returncode == 2:
                    raise RuntimeError("物理磁盘访问被拒绝，请右键以管理员身份启动本工具")
                raise RuntimeError(f"安全写入未完成，错误码{result.returncode}；详见日志")
            messagebox.showinfo("写入完成", f"音乐已写入并回读校验通过。\n原音乐备份：\n{backup}")
        except Exception as exc:
            self._log("音乐写入失败：" + str(exc))
            messagebox.showerror("音乐写入失败", str(exc))
