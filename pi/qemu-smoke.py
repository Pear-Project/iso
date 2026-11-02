#!/usr/bin/env python3
"""Boots the pearOS Pi image in QEMU (aarch64 'virt' + UEFI) and takes a screenshot
every --interval seconds, so a CI run shows how far it gets (GRUB, kernel, Plymouth,
first-boot assistant...). Reuses the QMP/screendump helpers of the shared test harness
(pearOS-archlinux/iso, tests/boot-test.py).

  qemu-smoke.py IMAGE --harness path/to/boot-test.py --out DIR [--duration 480]
"""
import argparse, importlib.util, os, subprocess, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("image")
ap.add_argument("--harness", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--duration", type=int, default=480)
ap.add_argument("--interval", type=int, default=20)
ap.add_argument("--memory", default="6G")
a = ap.parse_args()

spec = importlib.util.spec_from_file_location("bt", a.harness)
bt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bt)

os.makedirs(a.out, exist_ok=True)
sock = os.path.join(a.out, "qmp.sock")
if os.path.exists(sock):
    os.remove(sock)
fw = next((p for p in ("/usr/share/AAVMF/AAVMF_CODE.fd", "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd")
           if os.path.exists(p)), None)
if not fw:
    sys.exit("no aarch64 UEFI firmware found (install qemu-efi-aarch64)")
kvm = os.access("/dev/kvm", os.W_OK)
cmd = ["qemu-system-aarch64", "-M", "virt", "-cpu", "host" if kvm else "max", "-smp", "4", "-m", a.memory,
       "-bios", fw,
       "-drive", f"if=none,id=hd,format=raw,file={a.image}", "-device", "virtio-blk-pci,drive=hd",
       "-device", "virtio-gpu-pci", "-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet",
       "-display", "none", "-serial", f"file:{os.path.join(a.out, 'serial.log')}",
       "-qmp", f"unix:{sock},server=on,wait=off"]
if kvm:
    cmd[1:1] = ["-accel", "kvm"]
else:
    cmd[1:1] = ["-accel", "tcg"]
print("QEMU:", " ".join(cmd), flush=True)
q = subprocess.Popen(cmd)
qmp = bt.QMP(sock)
n = 0
t0 = time.time()
try:
    while time.time() - t0 < a.duration and q.poll() is None:
        time.sleep(a.interval)
        n += 1
        ppm = os.path.join(a.out, "s.ppm")
        qmp.cmd("screendump", filename=ppm)
        w, h, rgb = bt.read_ppm(ppm)
        bt.write_png(os.path.join(a.out, f"{n}.png"), w, h, rgb)
        bright = sum(rgb[::97]) / len(rgb[::97])
        print(f"[{n * a.interval:>4}s] {n}.png {w}x{h} brightness={bright:.1f}", flush=True)
finally:
    q.kill()
