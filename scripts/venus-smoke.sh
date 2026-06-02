#!/usr/bin/env bash
#
# venus-smoke.sh — host-side smoke test for the qemu-virgl venus (Vulkan-on-Metal)
# stack. macOS Apple Silicon only. Does NOT boot a guest.
#
#   Level A  MoltenVK exposes the Mac's GPU as a Vulkan device — the Metal->Vulkan
#            half venus relies on. Strong signal. Needs `brew install vulkan-tools`.
#   Level B  QEMU launches with the venus GPU device + cocoa display without an
#            early crash — load sanity (binary + linked dylibs + display backend +
#            config). Needs a GUI login session (cocoa can't open a window over
#            plain SSH). WEAK: with no guest driving the device, virgl_renderer_init
#            and the ANGLE/libvulkan dlopens never fire, so this does NOT exercise
#            venus runtime init itself.
#
# Definitive end-to-end test (the only one that truly exercises venus): boot the
# Ubuntu guest with patched Mesa and run vulkaninfo / vkcube / glxinfo INSIDE the
# guest — see the README.

set -uo pipefail

PREFIX="$(brew --prefix)"
# molten-vk-venus ships the ICD keg-private under share/ (the shared etc path
# collides with homebrew-core molten-vk), so resolve it via opt.
ICD="$PREFIX/opt/molten-vk-venus/share/vulkan/icd.d/MoltenVK_icd.json"
[ -f "$ICD" ] || ICD="$(find "$PREFIX/opt/molten-vk-venus" "$PREFIX/Cellar/molten-vk-venus" -name MoltenVK_icd.json 2>/dev/null | head -1)"
QEMU="$PREFIX/bin/qemu-system-aarch64"
fail=0

echo "molten-vk-venus ICD: ${ICD:-<not found>}"
{ [ -n "$ICD" ] && [ -f "$ICD" ]; } || { echo "FAIL: MoltenVK ICD not found — is molten-vk-venus installed?"; exit 1; }
[ -x "$QEMU" ] || { echo "FAIL: $QEMU not found — is qemu-virgl installed?"; exit 1; }

echo
echo "=== Level A: MoltenVK Vulkan device (vulkaninfo via the ICD) ==="
if ! command -v vulkaninfo >/dev/null; then
  echo "SKIP: vulkaninfo missing — run 'brew install vulkan-tools' to enable Level A"
else
  out="$(VK_ICD_FILENAMES="$ICD" vulkaninfo --summary 2>&1)" || true
  printf '%s\n' "$out" | sed -n '1,30p'
  if printf '%s\n' "$out" | grep -qi moltenvk && printf '%s\n' "$out" | grep -qi apple; then
    echo "PASS: MoltenVK enumerated an Apple GPU"
  else
    echo "FAIL: no MoltenVK/Apple GPU in vulkaninfo output"
    fail=1
  fi
fi

echo
echo "=== Level B: QEMU starts with the venus device + cocoa GL ES context ==="
log="$(mktemp)"
# -S freezes the vCPU: the machine, devices and display still initialize, so a
# missing-dylib / bad-signature / display failure surfaces, but no guest runs.
VK_LOADER_DEBUG=warn MVK_CONFIG_LOG_LEVEL=2 "$QEMU" \
  -machine virt,accel=hvf -cpu host -m 2G -S \
  -device virtio-gpu-gl-pci,venus=true,hostmem=2G,blob=true \
  -display cocoa,gl=es >"$log" 2>&1 &
pid=$!
sleep 6
if kill -0 "$pid" 2>/dev/null; then
  echo "PASS: QEMU stayed up (binary + linked libs + display backend loaded, no early failure)"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
else
  echo "FAIL: QEMU exited early — last log lines:"
  tail -n 25 "$log"
  if grep -qiE 'cocoa|nswindow|display|window server' "$log"; then
    echo "  hint: looks display-related — run from Terminal.app in a GUI login session, not plain SSH"
  fi
  if grep -qi 'hvf' "$log"; then
    echo "  hint: mentions HVF — the binary needs its hvf entitlement intact (re-sign issue?)"
  fi
  if grep -qiE 'dylib|image not found|code sign|load command' "$log"; then
    echo "  hint: mentions a dylib/signature — a relocation/codesign regression in the bundle/keg"
  fi
  fail=1
fi
rm -f "$log"

echo
if [ "$fail" -eq 0 ]; then
  echo "venus smoke test PASSED (host-side)"
else
  echo "venus smoke test FAILED — see above"
fi
echo "Definitive end-to-end test: boot the Ubuntu guest (patched Mesa) and run"
echo "  vulkaninfo --summary   # expect a venus / virtio-gpu Vulkan device"
echo "  vkcube                 # spinning cube via venus -> MoltenVK -> Metal"
echo "  glxinfo | grep -E 'renderer|direct'   # 'virgl (ANGLE ... Metal)'"
echo "inside the guest — see the README."
exit "$fail"
