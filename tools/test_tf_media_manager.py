#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tf_media_manager as media
import sdcard_music as music


class MediaManagerTests(unittest.TestCase):
    @staticmethod
    def tempdir():
        base = Path(__file__).resolve().parent / "_test_tmp"
        base.mkdir(exist_ok=True)
        return tempfile.TemporaryDirectory(dir=base)

    def test_image_conversion_and_slot_install(self):
        with self.tempdir() as folder:
            root = Path(folder)
            source = root / "source.png"
            Image.new("RGB", (1000, 500), (12, 34, 56)).save(source)
            info = media.install_image(source, root, "WEL1.BMP", "完整显示（黑边）")
            self.assertEqual(info["file_size"], media.BMP_FILE_SIZE)
            self.assertEqual(media.parse_bmp(root / "WEL1.BMP")["bits"], 24)
            with Image.open(root / "WEL1.BMP") as result:
                self.assertEqual(result.size, (640, 480))
                self.assertEqual(result.getpixel((0, 0)), (0, 0, 0))

    def test_invalid_slot_is_rejected(self):
        with self.tempdir() as folder:
            source = Path(folder) / "source.png"
            Image.new("RGB", (10, 10), "white").save(source)
            with self.assertRaises(ValueError):
                media.install_image(source, folder, "OTHER.BMP", "居中裁剪")

    def test_audio_conversion(self):
        with self.tempdir() as folder:
            source = Path(folder) / "tone.wav"
            raw = Path(folder) / "tone.raw"
            with wave.open(str(source), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(48000)
                wav.writeframes(b"\x01\x00" * 4800)
            info = media.prepare_audio(source, raw)
            self.assertEqual(info["source_bytes"], 9600)
            self.assertEqual(info["bytes"], media.WAV_REGION_BYTES)
            self.assertAlmostEqual(info["source_seconds"], 0.1, places=3)
            with open(raw, "rb") as stream:
                self.assertEqual(stream.read(4), b"\x01\x00\x01\x00")
                stream.seek(9600)
                self.assertEqual(stream.read(4), b"\x01\x00\x01\x00")

    def test_fat32_layout_and_allocation_check(self):
        base = Path(__file__).resolve().parent / "_test_tmp"
        base.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(delete=False, dir=base) as tmp:
            path = Path(tmp.name)
        try:
            with open(path, "w+b") as disk:
                disk.truncate(3 * 1024 * 1024)
                mbr = bytearray(512)
                mbr[510:512] = b"\x55\xAA"
                mbr[446 + 4] = 0x0C
                struct.pack_into("<I", mbr, 446 + 8, 2048)
                struct.pack_into("<I", mbr, 446 + 12, 100000)
                disk.seek(0)
                disk.write(mbr)

                boot = bytearray(512)
                boot[82:90] = b"FAT32   "
                struct.pack_into("<H", boot, 11, 512)
                boot[13] = 8
                struct.pack_into("<H", boot, 14, 32)
                boot[16] = 2
                struct.pack_into("<I", boot, 28, 2048)
                struct.pack_into("<I", boot, 32, 100000)
                struct.pack_into("<I", boot, 36, 100)
                struct.pack_into("<I", boot, 44, 2)
                disk.seek(2048 * 512)
                disk.write(boot)

                # 第一份FAT从物理2080扇区开始；将簇12标记为已占用。
                disk.seek(2080 * 512 + 12 * 4)
                disk.write(struct.pack("<I", 0x0FFFFFFF))
                disk.flush()

            with open(path, "rb", buffering=0) as disk:
                layout = music.Layout(disk, 1)
                self.assertEqual(layout.fs_type, "FAT32")
                self.assertEqual(layout.clu_of(layout.heap_start_phys), 2)
                self.assertEqual(music.allocated_clusters(layout, disk, 10, 13), [12])
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main()
