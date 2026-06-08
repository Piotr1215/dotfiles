#!/usr/bin/env bash
set -uo pipefail

# __nvidia_driver_pin_check.sh
# WHY: NVIDIA driver 580.126.09+ (incl. 580.159.03) carries a GPU VA-mapping
# reuse leak (gpu_vaspace.c / dmaAllocMapping_GM107) that freezes EVE multibox
# clients after sustained system-jump churn. Confirmed clean on 580.119.02.
# We pin to 580.119.02. This cron guards the pin: alerts if the running driver
# drifts off 580.119.02, if the apt holds vanish, or if a driver NEWER than the
# known-broken 580.159.03 ships (a candidate fix worth evaluating to unpin).
# Mails a daily status via msmtp using Piotr's header/ANSI-strip mechanism.

readonly EXPECTED="580.119.02"        # pinned-good version
readonly BROKEN_LATEST="580.159.03"   # current broken latest; newer => candidate fix
readonly MAILTO="piotrzan@gmail.com"
readonly DRIVER_PKG="nvidia-driver-580-open"
readonly HOLD_PKGS=(nvidia-driver-580-open nvidia-dkms-580-open \
  nvidia-kernel-source-580-open nvidia-kernel-common-580 nvidia-compute-utils-580 \
  nvidia-utils-580 xserver-xorg-video-nvidia-580 libnvidia-cfg1-580 \
  libnvidia-common-580 libnvidia-compute-580 libnvidia-decode-580 \
  libnvidia-encode-580 libnvidia-extra-580 libnvidia-fbc1-580 libnvidia-gl-580)

# --- gather (all read-only, no sudo) -----------------------------------------
running="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
[ -z "$running" ] && running="UNKNOWN(nvidia-smi failed)"

holds="$(apt-mark showhold 2>/dev/null | grep -E 'nvidia' || true)"
missing_holds=()
for p in "${HOLD_PKGS[@]}"; do
  grep -qx "$p" <<<"$holds" || missing_holds+=("$p")
done

repo_candidate="$(apt-cache policy "$DRIVER_PKG" 2>/dev/null | awk '/Candidate:/{print $2}')"

# --- version compare helper (dpkg) -------------------------------------------
newer() { dpkg --compare-versions "$1" gt "$2"; }   # newer A B => A > B

# --- evaluate state ----------------------------------------------------------
state="OK"; notes=()

if [ "$running" != "$EXPECTED" ]; then
  state="DRIFT"
  notes+=("Running driver is $running, expected pinned $EXPECTED.")
  case "$running" in
    580.12[6-9]*|580.1[3-9]*|58[1-9]*|59*) notes+=("!! Running version is in the BROKEN range (>=580.126.09) — EVE freeze bug active.");;
  esac
fi

if [ "${#missing_holds[@]}" -gt 0 ]; then
  [ "$state" = "OK" ] && state="DRIFT"
  notes+=("apt holds MISSING for: ${missing_holds[*]}")
fi

# new driver shipped beyond the known-broken latest => candidate fix to evaluate
if [ -n "$repo_candidate" ] && newer "${repo_candidate%%-*}" "$BROKEN_LATEST" 2>/dev/null; then
  state="NEWDRIVER"
  notes+=("Pop repo now offers $repo_candidate (newer than broken $BROKEN_LATEST).")
  notes+=("ACTION: check NVIDIA 580/590 release notes for the gpu_vaspace VA-mapping fix before unpinning.")
fi

# --- compose + send (terse: one-line report) --------------------------------
case "$state" in
  OK)        summary="No upstream fix yet. Still safely pinned ${running}, holds intact." ;;
  DRIFT)     summary="DRIFT — running ${running}, expected ${EXPECTED}. ${notes[*]}" ;;
  NEWDRIVER) summary="UPSTREAM CANDIDATE: ${repo_candidate} now available (newer than broken ${BROKEN_LATEST}). Check its release notes for the gpu_vaspace VA-mapping fix; if fixed, unpin + upgrade." ;;
  *)         summary="${notes[*]}" ;;
esac

subject="[nvidia-pin ${state}] $(hostname -s) running=${running}"

# Piotr's M-alias mail mechanism inline (cron sh has no zsh global alias).
{
  printf 'Subject: %s\nFrom: %s\nTo: %s\n\n' "$subject" "$MAILTO" "$MAILTO"
  printf '%s\n' "$summary" | sed -r 's/\x1b\[[0-9;]*m//g'
} | msmtp "$MAILTO"

echo "$subject"
