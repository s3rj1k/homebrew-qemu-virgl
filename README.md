# qemu-virgl — QEMU for Apple Silicon with GPU acceleration

A Homebrew tap that builds `qemu-system-aarch64` with **venus (Vulkan-on-Metal)** and
**OpenGL (ANGLE/Metal)** guest GPU acceleration, for running 3D-accelerated Linux desktops
on Apple Silicon Macs. Built from the utmapp venus stack (ANGLE, libepoxy, virglrenderer,
MoltenVK). **Apple Silicon (arm64) only.**

## Install

Prerequisites: **full Xcode** (not just Command Line Tools — ANGLE/MoltenVK build via
`xcodebuild`; run `sudo xcodebuild -license accept`) and **Homebrew**.

```sh
brew tap s3rj1k/qemu-virgl
brew install s3rj1k/qemu-virgl/qemu-virgl
```

This builds the venus stack (`libangle`, `libepoxy-angle`, `virglrenderer`,
`molten-vk-venus`). They're `keg_only`, so there are no libepoxy conflicts and no
`brew link --force` is needed. `qemu-system-aarch64` is wrapped to find the MoltenVK ICD
and select Metal automatically.

## Run

Shared (`vmnet`) networking needs root, and `sudo` resets `PATH`, so launch via the
**absolute path**. The flags that enable acceleration are
`-device virtio-gpu-gl-pci,venus=true,…` and `-display cocoa,gl=es`.

```sh
# One-time setup: a disk, a writable copy of the UEFI vars, and an arm64 Linux ISO.
qemu-img create -f qcow2 disk.qcow2 64G
cp "$(brew --prefix)/share/qemu/edk2-aarch64-code.fd" .
cp "$(brew --prefix)/share/qemu/edk2-arm-vars.fd" .
curl -LO https://cdimage.ubuntu.com/releases/25.10/release/ubuntu-25.10-desktop-arm64.iso

# Boot (drop -cdrom/-boot d once installed):
sudo "$(brew --prefix)/bin/qemu-system-aarch64" \
  -machine virt,accel=hvf -cpu host -smp 4 -m 8G \
  -device virtio-gpu-gl-pci,venus=true,hostmem=8G,blob=true \
  -display cocoa,gl=es \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -device virtio-net-pci,netdev=net -netdev vmnet-shared,id=net \
  -drive if=pflash,format=raw,file=./edk2-aarch64-code.fd,readonly=on \
  -drive if=pflash,format=raw,file=./edk2-arm-vars.fd \
  -drive if=virtio,format=qcow2,file=./disk.qcow2 \
  -chardev qemu-vdagent,id=spice,name=vdagent,clipboard=on \
  -device virtio-serial-pci \
  -device virtserialport,chardev=spice,name=com.redhat.spice.0 \
  -cdrom ubuntu-25.10-desktop-arm64.iso -boot d
```

Release the mouse with **Ctrl-Alt-G**. Clipboard sharing works once the guest runs
`spice-vdagent`.

## Verify

Host-side smoke test (MoltenVK exposes a Metal Vulkan device; QEMU starts clean):

```sh
brew install vulkan-tools
bash "$(brew --prefix)/Library/Taps/s3rj1k/homebrew-qemu-virgl/scripts/venus-smoke.sh"
```

Inside the guest — the definitive check (needs a venus-capable Mesa; on Ubuntu 25.10 use the
patched Mesa from the upstream venus notes):

```sh
glxinfo | grep -E "OpenGL renderer|direct rendering"   # → virgl (ANGLE … Metal); direct rendering: Yes
vulkaninfo --summary                                   # → a venus / virtio-gpu Vulkan device
vkcube
```

## Optional: quickemu

```sh
brew install s3rj1k/qemu-virgl/quickemu-virgl   # patched quickemu that uses qemu-virgl
```

Conflicts with homebrew-core `quickemu`; uninstall that first if present.

## Troubleshooting

- **Networking / `vmnet` fails** — it needs root; run under `sudo` with the absolute binary
  path. Use `vmnet-shared` (the supported macOS backend), not `-netdev user`.
- **GPU not accelerated** — use `virtio-gpu-gl-pci` (not `virtio-gpu-pci`) and
  `-display cocoa,gl=es`; re-check with the smoke test above.
- **"Addressing limited to 32 bits"** — remove `highmem=off` or lower `-m`.
