#!/usr/bin/env python3
"""Edit /boot/extlinux/extlinux.conf: add/replace or remove the 'waydroid' entry; nothing else changes.

  extlinux.py add <conf> <out> [--default]   clone LABEL primary → LABEL waydroid (Image-/initrd-waydroid, psi=1)
  extlinux.py remove <conf> <out>            drop LABEL waydroid; DEFAULT waydroid → primary

An entry is its 'LABEL' line plus the indented, non-empty lines after it; comments and blank lines stay put.
"""
import re
import sys


def parse(text):
    segs, cur = [], None  # segs: ["text", line] or ["entry", name, [lines]]
    for line in text.splitlines(keepends=True):
        m = re.match(r"LABEL\s+(\S+)", line)
        if m:
            cur = ["entry", m.group(1), [line]]
            segs.append(cur)
        elif cur is not None and line.strip() and line[0] in " \t" and not line.lstrip().startswith("#"):
            cur[2].append(line)
        else:
            cur = None
            segs.append(["text", line])
    return segs


def render(segs):
    return "".join(s[1] if s[0] == "text" else "".join(s[2]) for s in segs)


def entry(segs, name):
    return next((s for s in segs if s[0] == "entry" and s[1] == name), None)


def set_default(segs, name):
    for s in segs:
        if s[0] == "text" and re.match(r"DEFAULT\s", s[1]):
            s[1] = f"DEFAULT {name}\n"
            return
        if s[0] == "entry":
            break


def add(segs, make_default):
    prim = entry(segs, "primary")
    if prim is None:
        sys.exit("no LABEL primary")
    lines = []
    for line in prim[2]:
        key = line.split()[0]
        ind = re.match(r"\s*", line).group(0)
        if line.startswith("LABEL"):
            line = "LABEL waydroid\n"
        elif key == "MENU" and line.split()[1:2] == ["LABEL"]:
            line = f"{ind}MENU LABEL waydroid kernel (orin-waydroid)\n"
        elif key == "LINUX":
            line = f"{ind}LINUX /boot/Image-waydroid\n"
        elif key == "INITRD":
            line = f"{ind}INITRD /boot/initrd-waydroid\n"
        elif key == "APPEND":
            line = line.rstrip()
            line = (line if " psi=1" in line else line + " psi=1") + "\n"
        lines.append(line)
    if not any(l.split()[0] == "INITRD" for l in lines):
        i = next(i for i, l in enumerate(lines) if l.split()[0] == "LINUX")
        lines.insert(i + 1, re.match(r"\s*", lines[i]).group(0) + "INITRD /boot/initrd-waydroid\n")
    old = entry(segs, "waydroid")
    new = ["entry", "waydroid", lines]
    if old is not None:
        segs[segs.index(old)] = new
    else:
        segs.insert(segs.index(prim) + 1, new)
    if make_default:
        set_default(segs, "waydroid")


def remove(segs):
    old = entry(segs, "waydroid")
    if old is not None:
        segs.remove(old)
    if any(s[0] == "text" and re.match(r"DEFAULT\s+waydroid\b", s[1]) for s in segs):
        set_default(segs, "primary")


if __name__ == "__main__":
    cmd, src, dst = sys.argv[1:4]
    segs = parse(open(src).read())
    if cmd == "add":
        add(segs, "--default" in sys.argv[4:])
    elif cmd == "remove":
        remove(segs)
    else:
        sys.exit(__doc__)
    out = render(segs)
    if entry(parse(out), "primary") is None:
        sys.exit("refusing to write a config without LABEL primary")
    open(dst, "w").write(out)
