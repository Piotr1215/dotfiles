#!/usr/bin/env bash
set -uo pipefail

# __nvidia_pin_downgrade.sh
# WHY: downgrade NVIDIA 580.159.03 (VA-mapping leak, EVE freeze) -> 580.119.02
# (last good 580 before the 580.126.09 regression) using debs already cached in
# /var/cache/apt/archives, then apt-mark hold so Pop can't auto-upgrade back.
# SAFETY: refuses to run with EVE clients live; rebuilds DKMS for the RUNNING
# kernel and verifies the .ko exists BEFORE declaring reboot-safe (Pop!_OS does
# not always write /var/run/reboot-required; a missing module = black screen).
# Run with sudo from a place you can reach a TTY (Ctrl+Alt+F3) if X drops.

readonly WANT="580.119.02"
readonly ARCH=/var/cache/apt/archives
readonly KREL="$(uname -r)"
readonly HOLD_PKGS=(nvidia-driver-580-open nvidia-dkms-580-open \
  nvidia-kernel-source-580-open nvidia-kernel-common-580 nvidia-compute-utils-580 \
  nvidia-utils-580 xserver-xorg-video-nvidia-580 libnvidia-cfg1-580 \
  libnvidia-common-580 libnvidia-compute-580 libnvidia-decode-580 \
  libnvidia-encode-580 libnvidia-extra-580 libnvidia-fbc1-580 libnvidia-gl-580 \
  "nvidia-firmware-580-${WANT}")

die() { echo "ABORT: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run with sudo."

# 1. Refuse if EVE is live (downgrade yanks the driver out from under it).
if pgrep -x exefile.exe >/dev/null 2>&1; then
  die "EVE clients (exefile.exe) are running. Close all EVE clients first."
fi

# 2. Confirm the full 580.119.02 deb set is cached.
mapfile -t debs < <(ls "$ARCH"/*"${WANT}"*.deb 2>/dev/null)
[ "${#debs[@]}" -ge 18 ] || die "expected >=18 cached ${WANT} debs, found ${#debs[@]}. Re-download before proceeding."
echo ">> found ${#debs[@]} cached ${WANT} debs"

# 3. Install (apt allows downgrade from local debs, resolves deps).
echo ">> installing ${WANT} from cache (this rebuilds DKMS for $KREL)..."
apt-get install -y --allow-downgrades "${debs[@]}" || die "apt install failed."

# 4. DKMS gate — module MUST be built for the RUNNING kernel before reboot.
echo ">> verifying DKMS for kernel $KREL ..."
dkms status 2>/dev/null | grep -E "nvidia/${WANT}.*${KREL}.*installed" \
  || die "DKMS does NOT show nvidia/${WANT} installed for $KREL. DO NOT REBOOT. Run: dkms autoinstall && recheck."
ko="$(ls /lib/modules/"$KREL"/updates/dkms/nvidia.ko* 2>/dev/null | head -1)"
[ -n "$ko" ] || die "nvidia.ko not found under /lib/modules/$KREL/updates/dkms/. DO NOT REBOOT."
echo ">> DKMS OK: $ko"

# 5. Verify installed version is what we want.
got="$(dpkg -l nvidia-driver-580-open | awk '/^ii/{print $3}')"
case "$got" in "${WANT}"*) echo ">> installed nvidia-driver-580-open = $got";; *) die "version mismatch: got '$got', wanted ${WANT}*";; esac

# 6. Pin: hold so Pop can't auto-upgrade back to the broken version.
echo ">> applying apt-mark hold ..."
apt-mark hold "${HOLD_PKGS[@]}"
echo ">> holds:"; apt-mark showhold | grep -E 'nvidia' | sed 's/^/   /'

cat <<EOF

=========================================================
 PASS. nvidia ${WANT} installed, DKMS built for $KREL, holds applied.
 SAFE TO REBOOT now:   sudo systemctl reboot
 After reboot verify:  nvidia-smi --query-gpu=driver_version --format=csv,noheader   (expect ${WANT})
 The 0800 cron mail will then report state=OK instead of DRIFT.
=========================================================
EOF
