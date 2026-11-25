"""Extract OpenCore log files (opencore-*.txt) from a RAW disk image (GPT + FAT32).

Usage: python -I scripts/read_fat_logs.py <raw-image> <output-dir>
Make the raw image with: VBoxManage clonemedium disk OpenCore.vhd boot.raw --format RAW
"""
import os
import struct
import sys


def main(img_path, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    with open(img_path, "rb") as f:
        def read(off, n):
            f.seek(off)
            return f.read(n)

        # GPT header at LBA 1, entries usually at LBA 2
        hdr = read(512, 92)
        if hdr[:8] != b"EFI PART":
            raise SystemExit("no GPT found")
        ent_lba, ent_count, ent_size = struct.unpack_from("<QII", hdr, 72)
        part_lba = None
        for i in range(ent_count):
            e = read(ent_lba * 512 + i * ent_size, ent_size)
            first = struct.unpack_from("<Q", e, 32)[0]
            # skip empty slots and non-FAT32 partitions (e.g. Microsoft Reserved)
            if e[:16] != b"\0" * 16 and first and read(first * 512 + 82, 8) == b"FAT32   ":
                part_lba = first
                break
        if part_lba is None:
            raise SystemExit("no partition found")
        base = part_lba * 512

        bpb = read(base, 512)
        bps = struct.unpack_from("<H", bpb, 11)[0]
        spc = bpb[13]
        reserved = struct.unpack_from("<H", bpb, 14)[0]
        nfats = bpb[16]
        fatsz = struct.unpack_from("<I", bpb, 36)[0]
        root_cluster = struct.unpack_from("<I", bpb, 44)[0]
        cluster_size = bps * spc
        fat_off = base + reserved * bps
        data_off = base + (reserved + nfats * fatsz) * bps

        def chain(c):
            while 2 <= c < 0x0FFFFFF8:
                yield c
                c = struct.unpack("<I", read(fat_off + c * 4, 4))[0] & 0x0FFFFFFF

        def read_chain(c, size=None):
            data = b"".join(read(data_off + (cl - 2) * cluster_size, cluster_size) for cl in chain(c))
            return data if size is None else data[:size]

        root = read_chain(root_cluster)
        found = 0
        lfn = ""
        for off in range(0, len(root), 32):
            ent = root[off:off + 32]
            if ent[0] == 0:
                break
            if ent[0] == 0xE5:
                lfn = ""
                continue
            if ent[11] == 0x0F:  # long file name part
                part = (ent[1:11] + ent[14:26] + ent[28:32]).decode("utf-16-le", "ignore")
                lfn = part.split("\0")[0] + lfn
                continue
            short = ent[0:8].decode("ascii", "ignore").strip() + "." + ent[8:11].decode("ascii", "ignore").strip()
            name = lfn or short
            lfn = ""
            print("  ", name)
            if name.lower().startswith("opencore") and name.lower().endswith(".txt"):
                cl = (struct.unpack_from("<H", ent, 20)[0] << 16) | struct.unpack_from("<H", ent, 26)[0]
                size = struct.unpack_from("<I", ent, 28)[0]
                with open(os.path.join(out_dir, name), "wb") as o:
                    o.write(read_chain(cl, size))
                found += 1
        print(f"{found} log file(s) extracted to {out_dir}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
