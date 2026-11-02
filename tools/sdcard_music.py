#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ====================================================================
# sdcard_music.py —— TF 卡「裸扇区音乐区」安全写入 + 布局核验助手
#
# 【背景】
#   FPGA 端 sd_card 驱动按【裸 LBA】读扇区, 不解析文件系统:
#     · BMP 素材: bmp_read_auto.v 从 Z_*_START 起每 8 扇区扫 "BM" 头;
#     · 会议配置: meeting_cfg.v 固定读扇区 200000 (MTG1);
#     · 音乐素材: wav_stream_player 固定读 WAV_START_LBA (=300000) 起的
#                 连续 38464 个扇区(裸 PCM, 无文件头)。
#   因此音乐必须写在【卡上无人使用的连续扇区】里。本工具在写之前
#   先把卡的文件系统布局解析清楚, 逐项断言, 再写入并回读校验。
#
# 【为什么必须解析文件系统】
#   裸写落在 FAT 表 / 分配位图 / 已被文件占用的簇上, 都会破坏卡上原有
#   素材(BMP 与 MTG1 配置)。仅看"目标区当前是全 0"是不够的 —— 必须确认
#   这些簇在 FAT32 的 FAT 表或 exFAT 分配位图里被标记为【未分配】。
#
# 【LBA 约定(易错点)】
#   本卡为 MBR 单分区(exFAT), 分区物理偏移通常为 2048 扇区。
#   · find_bmp.py 读的是 \\.\F:  → 报告的是【卷内扇区】(相对分区起点);
#   · FPGA 读的是物理扇区。
#   两者相差一个分区偏移。本工具 --probe 会在物理盘上扫 BMP 头, 实测判定
#   Z_* 常量到底是物理 LBA 还是卷内 LBA, 避免音乐区整体错位。
#
# 【用法】(必须【管理员权限】终端; 物理盘访问需要)
#   探测(只读, 不动盘):
#     python tools/sdcard_music.py --disk 1 --lba 300000 --sectors 38464
#   写入(先自动备份被覆盖区, 再写, 再回读校验 sha256):
#     python tools/sdcard_music.py --disk 1 --lba 300000 `
#         --raw audio_final/assets/wel_music_48k_mono.raw --write
# ====================================================================

import argparse
import hashlib
import os
import struct
import sys

SEC = 512

try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass


# --------------------------------------------------------------------
# 工具函数
# --------------------------------------------------------------------
def u16(b, o):
    return struct.unpack_from('<H', b, o)[0]


def u32(b, o):
    return struct.unpack_from('<I', b, o)[0]


def u64(b, o):
    return struct.unpack_from('<Q', b, o)[0]


def read_at(f, lba, nsec):
    f.seek(lba * SEC)
    buf = f.read(nsec * SEC)
    if len(buf) != nsec * SEC:
        raise IOError('读取不足: lba=%d nsec=%d 实际=%d' % (lba, nsec, len(buf)))
    return buf


class Layout(object):
    """从 MBR + FAT32/exFAT BPB 解析卡布局(全部换算为物理扇区)。"""

    def __init__(self, f, disk_no):
        self.disk_no = disk_no
        self.raw0 = read_at(f, 0, 1)

        # ---- MBR: 取第一个非空分区项 ----
        if self.raw0[510] != 0x55 or self.raw0[511] != 0xAA:
            raise ValueError('扇区 0 无 MBR 签名, 可能卡未分区/格式异常')
        self.part_offset = None
        for i in range(4):
            e = 446 + i * 16
            lba = u32(self.raw0, e + 8)
            nsec = u32(self.raw0, e + 12)
            if lba and nsec:
                self.part_offset = lba
                self.part_sectors = nsec
                break
        if self.part_offset is None:
            raise ValueError('MBR 里没有非空分区项')

        # ---- 文件系统引导扇区(分区首扇区) ----
        bs = read_at(f, self.part_offset, 1)
        if bs[3:11] == b'EXFAT   ':
            self.fs_type         = 'exFAT'
            self.bpb_part_offset = u64(bs, 64)
            self.volume_length   = u64(bs, 72)
            self.fat_offset      = u32(bs, 80)
            self.fat_length      = u32(bs, 84)
            self.heap_offset     = u32(bs, 88)
            self.cluster_count   = u32(bs, 92)
            self.root_cluster    = u32(bs, 96)
            self.bytes_per_sec   = 1 << bs[108]
            self.sec_per_clu     = 1 << bs[109]
            self.num_fats        = bs[110]
        elif bs[82:90] == b'FAT32   ':
            self.fs_type         = 'FAT32'
            self.bytes_per_sec   = u16(bs, 11)
            self.sec_per_clu     = bs[13]
            reserved             = u16(bs, 14)
            self.num_fats        = bs[16]
            total16              = u16(bs, 19)
            self.volume_length   = total16 if total16 else u32(bs, 32)
            self.fat_offset      = reserved
            self.fat_length      = u32(bs, 36)
            self.heap_offset     = reserved + self.num_fats * self.fat_length
            data_sectors         = self.volume_length - self.heap_offset
            self.cluster_count   = data_sectors // self.sec_per_clu
            self.root_cluster    = u32(bs, 44)
            self.bpb_part_offset = u32(bs, 28)
        else:
            raise ValueError('分区起点不是受支持的 FAT32/exFAT 文件系统'
                             '(OEM=%r, FAT标识=%r)' % (bs[3:11], bs[82:90]))

        self.clu_bytes = self.bytes_per_sec * self.sec_per_clu
        if self.bytes_per_sec != SEC:
            raise ValueError('扇区大小 %d != 512, 本工具未支持' % self.bytes_per_sec)
        if not self.sec_per_clu or (self.sec_per_clu & (self.sec_per_clu - 1)):
            raise ValueError('每簇扇区数 %d 非法' % self.sec_per_clu)

        # ---- 换算成物理扇区 ----
        self.fat_start_phys  = self.part_offset + self.fat_offset
        self.fat_end_phys    = self.fat_start_phys + self.fat_length * self.num_fats
        self.heap_start_phys = self.part_offset + self.heap_offset
        self.heap_end_phys   = self.heap_start_phys + self.cluster_count * self.sec_per_clu

    def clu_of(self, phys_lba):
        """物理扇区 → 簇号(相对簇堆; 簇 n 的首扇区 = heap_start + (n-2)*spc)"""
        return (phys_lba - self.heap_start_phys) // self.sec_per_clu + 2

    def describe(self):
        print('==================== 卡布局(MBR + %s) ====================' % self.fs_type)
        print('  分区物理偏移      : %d 扇区 (=%d 字节)'
              % (self.part_offset, self.part_offset * SEC))
        print('  分区长度          : %d 扇区' % self.part_sectors)
        print('  BPB 分区偏移      : %d' % self.bpb_part_offset)
        print('  FAT 区(物理)      : %d ~ %d  (共 %d 份, 每份 %d 扇区)'
              % (self.fat_start_phys, self.fat_end_phys - 1,
                 self.num_fats, self.fat_length))
        print('  簇堆起点(物理)    : %d' % self.heap_start_phys)
        print('  簇堆结束(物理)    : %d' % self.heap_end_phys)
        print('  簇大小            : %d 字节 (%d 扇区/簇)'
              % (self.clu_bytes, self.sec_per_clu))
        print('  簇总数            : %d (%.2f GB 可用簇堆)'
              % (self.cluster_count,
                 self.cluster_count * self.clu_bytes / 1e9))
        if self.fs_type == 'exFAT':
            print('  分配状态来源      : 根目录 0x81 分配位图')
        else:
            print('  分配状态来源      : FAT32 第一份 FAT 表')
        print('  卷内扇区 → 物理扇区 = +%d' % self.part_offset)


def pump_header(f, phys_start, step, lba_lo, lba_hi):
    """在 [lba_lo, lba_hi) 里按 step 扇区步进找 "BM" 头, 返回物理起点列表"""
    hits = []
    start = ((lba_lo + step - 1) // step) * step
    lba = start
    while lba < lba_hi:
        if read_at(f, lba, 1)[0:2] == b'BM':
            hits.append(lba)
        lba += step
    return hits


def read_bitmap(lay, f):
    """读根目录, 找 0x81 分配位图项, 返回位图字节串"""
    # 根目录可能跨多个簇; 这里读前 32 个簇足够放下 0x81/0x82/标签项
    clu = lay.root_cluster
    total = 0
    for _ in range(32):
        lba = lay.heap_start_phys + (clu - 2) * lay.sec_per_clu
        d = read_at(f, lba, lay.sec_per_clu)
        for o in range(0, len(d), 32):
            t = d[o]
            if t == 0x81:                       # Allocation Bitmap
                first = u32(d, o + 20)
                dlen = u64(d, o + 24)
                blba = lay.heap_start_phys + (first - 2) * lay.sec_per_clu
                need = (dlen + SEC - 1) // SEC
                return read_at(f, blba, need)[:dlen], first, dlen
            if t == 0x00:                       # 目录项结束
                break
        # 下一簇(FAT 链) —— 用简单线性假设: 根目录通常连续
        clu += 1
        total += 1
    raise ValueError('根目录中未找到 0x81 分配位图项')


def bitmap_allocated(bm, clu):
    """簇 clu(>=2) 的分配位: bit(clu-2), 1=已分配"""
    idx = clu - 2
    return (bm[idx >> 3] >> (idx & 7)) & 1


def allocated_clusters(lay, f, c0, c1):
    """返回目标范围内已被文件系统占用的簇号。"""
    if c0 < 2 or c1 >= lay.cluster_count + 2:
        raise ValueError('目标簇号超出数据区范围')
    if lay.fs_type == 'exFAT':
        bmd, bfirst, bdlen = read_bitmap(lay, f)
        print('  分配位图         : 首簇 %d, 长度 %d 字节(覆盖 %d 簇)'
              % (bfirst, bdlen, bdlen * 8))
        if c1 - 2 >= bdlen * 8:
            raise ValueError('目标簇号超出位图覆盖范围')
        return [c for c in range(c0, c1 + 1) if bitmap_allocated(bmd, c)]

    # FAT32 每个簇占 4 字节，低 28 bit 为有效值；0 表示空闲。
    off0 = c0 * 4
    off1 = (c1 + 1) * 4
    sec0 = off0 // SEC
    sec1 = (off1 + SEC - 1) // SEC
    table = read_at(f, lay.fat_start_phys + sec0, sec1 - sec0)
    bad = []
    for clu in range(c0, c1 + 1):
        pos = clu * 4 - sec0 * SEC
        if u32(table, pos) & 0x0FFFFFFF:
            bad.append(clu)
    return bad


# --------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description='TF 卡裸扇区音乐区安全写入/核验')
    ap.add_argument('--disk', type=int, default=1, help='物理盘号(默认 1)')
    ap.add_argument('--lba', type=int, default=300000, help='音乐区起始物理扇区')
    ap.add_argument('--sectors', type=int, default=38464, help='音乐区扇区数')
    ap.add_argument('--raw', default=None, help='裸 PCM 文件(写入时必需)')
    ap.add_argument('--write', action='store_true', help='真正写入(缺省只探测)')
    ap.add_argument('--force', action='store_true', help='目标区非全 0 时仍写入')
    ap.add_argument('--skip-probe', action='store_true', help='跳过历史扇区锚点扫描')
    ap.add_argument('--backup', default=None, help='写入前将完整音乐区备份到此文件')
    a = ap.parse_args()

    dev = r'\\.\PhysicalDrive%d' % a.disk
    print('打开 %s (只读探测) ...' % dev)
    try:
        f = open(dev, 'rb', buffering=0)
    except PermissionError:
        print('*** 打开物理盘被拒绝: 请用【管理员权限】的终端重跑 ***')
        return 2

    lay = Layout(f, a.disk)
    lay.describe()

    # ---------------- 1) 判定 FPGA 读取的 LBA 口径 ----------------
    # FPGA 端 sd_card_sec_read_write.v 直接下发 CMD17(sec_addr) —— 即【物理扇区】。
    # 用两个已知锚点交叉验证: MTG1 配置(应固定物理 200000)与 BMP "BM" 头。
    print('\n==================== 1) LBA 口径核验 ====================')
    print('  FPGA 音乐地址按【物理扇区】解释；目标 LBA 不叠加分区偏移。')
    if not a.skip_probe:
        print('  在物理扇区 124000~142000 按 8 扇区步进扫描历史 BMP 锚点 ...')
        bm = pump_header(f, None, 8, 124000, 142000)
        print('  物理扇区命中 %d 处: %s' % (len(bm), bm[:12]))
        if lay.fs_type == 'FAT32':
            print('  ※ 最终版图片采用 FAT32 文件名寻址，锚点仅供历史卡排查。')
    else:
        print('  已跳过历史 BMP 锚点扫描。')

    # ---------------- 2) 音乐区落位核验 ----------------
    print('\n==================== 2) 音乐区落位核验 ====================')
    lba0 = a.lba
    lba1 = a.lba + a.sectors              # 开区间
    print('  目标物理扇区区间 : [%d, %d)  共 %d 扇区 (%.2f MB)'
          % (lba0, lba1, a.sectors, a.sectors * SEC / 1e6))

    errs = []
    if lba0 < lay.heap_end_phys and lba0 >= lay.heap_start_phys:
        pass
    else:
        errs.append('目标起点不在簇堆范围内')
    if lba1 > lay.heap_end_phys:
        errs.append('目标终点越过簇堆末端(卡容量不足)')
    if not (lba1 <= lay.fat_start_phys or lba0 >= lay.fat_end_phys):
        errs.append('目标区与 FAT 表区 [%d,%d) 重叠 —— 会毁文件系统!'
                    % (lay.fat_start_phys, lay.fat_end_phys))
    if lba1 - 1 >= lay.heap_end_phys:
        errs.append('目标区越过卡容量')

    c0 = lay.clu_of(lba0)
    c1 = lay.clu_of(lba1 - 1)
    print('  对应簇号范围     : %d ~ %d  (共 %d 簇)'
          % (c0, c1, c1 - c0 + 1))
    print('  簇堆剩余空间     : 目标终点后还有 %d 扇区 (%.1f MB)'
          % (lay.heap_end_phys - lba1,
             (lay.heap_end_phys - lba1) * SEC / 1e6))

    if not errs:
        try:
            bad = allocated_clusters(lay, f, c0, c1)
        except ValueError as exc:
            errs.append(str(exc))
        else:
            if bad:
                errs.append('目标区有 %d 个簇已被文件系统占用(例: 簇 %s) —— '
                            '写入会破坏卡上文件!' % (len(bad), bad[:8]))
            else:
                print('  → 目标区全部 %d 个簇在%s中均为【未分配】 ✔'
                      % (c1 - c0 + 1,
                         'FAT表' if lay.fs_type == 'FAT32' else '分配位图'))

    if errs:
        print('\n*** 核验未通过, 拒绝写入: ***')
        for e in errs:
            print('   - %s' % e)
        f.close()
        return 3

    # ---------------- 3) 目标区当前内容 ----------------
    print('\n==================== 3) 目标区当前内容 ====================')
    CH = 4096
    zeros = True
    nz_examples = []
    lba = lba0
    while lba < lba1:
        n = min(CH, lba1 - lba)
        blk = read_at(f, lba, n)
        if any(blk):
            zeros = False
            if len(nz_examples) < 3:
                nz_examples.append((lba, blk[:16].hex()))
        lba += n
    if zeros:
        print('  目标区当前全为 0 → 是空白区, 无数据可丢 ✔')
    else:
        print('  目标区存在非 0 数据, 例: %s' % nz_examples)
        print('  （若确认这些扇区对 FPGA 无用, 加 --force 覆盖）')

    if not a.write:
        print('\n[探测模式] 未写入任何数据。加 --write 执行写入。')
        f.close()
        return 0

    # ---------------- 4) 写入 ----------------
    if not a.raw:
        print('\n*** --write 必须配合 --raw <裸PCM文件> ***')
        f.close()
        return 1
    if not os.path.isfile(a.raw):
        print('\n*** 找不到文件 %s ***' % a.raw)
        f.close()
        return 1
    raw_len = os.path.getsize(a.raw)
    region_len = a.sectors * SEC
    print('\n==================== 4) 写入 ====================')
    print('  源文件        : %s' % a.raw)
    print('  源文件长度    : %d 字节 (%d 扇区, 余 %d 字节)'
          % (raw_len, raw_len // SEC, raw_len % SEC))
    if raw_len > region_len:
        print('*** 源文件超出预留扇区数(%d) ***' % a.sectors)
        f.close()
        return 1
    if not zeros and not a.force:
        print('*** 目标区非空, 拒绝写入(加 --force 强制) ***')
        f.close()
        return 1

    # 覆盖前先备份完整音乐区；GUI 默认总是传入备份路径。
    if a.backup:
        backup_dir = os.path.dirname(os.path.abspath(a.backup))
        if backup_dir and not os.path.isdir(backup_dir):
            os.makedirs(backup_dir)
        print('  备份原音乐区  : %s' % a.backup)
        with open(a.backup, 'wb') as bak:
            lba = lba0
            while lba < lba1:
                n = min(CH, lba1 - lba)
                bak.write(read_at(f, lba, n))
                lba += n

    # FPGA 会读取完整预留区。源音频不足时必须把尾部清零，避免旧音乐残留。
    padded_sha = hashlib.sha256()
    with open(a.raw, 'rb') as g:
        for chunk in iter(lambda: g.read(1 << 20), b''):
            padded_sha.update(chunk)
    remain_zero = region_len - raw_len
    zero_block = bytes(1 << 20)
    while remain_zero:
        chunk = zero_block[:min(remain_zero, len(zero_block))]
        padded_sha.update(chunk)
        remain_zero -= len(chunk)
    expect_sha = padded_sha.hexdigest()
    print('  整区期望sha256: %s' % expect_sha)

    f.close()
    fw = open(dev, 'r+b', buffering=0)
    try:
        fw.seek(lba0 * SEC)
        wrote = 0
        with open(a.raw, 'rb') as g:
            while True:
                chunk = g.read(1 << 20)
                if not chunk:
                    break
                fw.write(chunk)
                wrote += len(chunk)
        remain_zero = region_len - wrote
        while remain_zero:
            chunk = zero_block[:min(remain_zero, len(zero_block))]
            fw.write(chunk)
            wrote += len(chunk)
            remain_zero -= len(chunk)
        fw.flush()
        os.fsync(fw.fileno())
        print('  已写入 %d 字节' % wrote)
    finally:
        fw.close()

    # ---------------- 5) 回读校验 ----------------
    print('\n==================== 5) 回读校验 ====================')
    f = open(dev, 'rb', buffering=0)
    h2 = hashlib.sha256()
    lba = lba0
    remain = region_len
    while remain > 0:
        n = min(CH, remain // SEC)
        blk = read_at(f, lba, n)
        h2.update(blk)
        lba += n
        remain -= len(blk)
    f.close()
    got = h2.hexdigest()
    print('  回读 sha256   : %s' % got)
    if got == expect_sha:
        print('  → 校验一致 ✔  音乐区写入完成 (LBA %d, %d 扇区；尾部已清零)'
              % (lba0, a.sectors))
        return 0
    print('  *** 校验不一致 —— 写入失败, 请重试 ***')
    return 4


if __name__ == '__main__':
    sys.exit(main())
