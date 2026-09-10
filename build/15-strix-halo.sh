#!/usr/bin/bash

set -euo pipefail

###############################################################################
# Strix Halo Hardware Enablement
###############################################################################
# Configures the HP ZBook Ultra G1a (AMD Ryzen AI Max+ 395 / Radeon 8060S UMA):
# - Overlay halo hardware configs and bootc kargs
# - sched-ext userspace schedulers (scx-scheds via COPR)
# - linux-firmware updates
# - TuneD and TuneD-PPD (replacing power-profiles-daemon)
# - ryzenadj static binary for LLM thermal throttle hooks
# - GTK2 for Stata MP GUI
# - Enable hardware services
###############################################################################

# Source helper functions
# shellcheck source=/dev/null
source /ctx/build/copr-helpers.sh

echo "::group:: Overlay Strix Halo Hardware Files"
rsync -rvK /ctx/custom/halo/ /
echo "::endgroup::"

echo "::group:: Sched-ext Schedulers"
copr_install_isolated "sirlucjan/scx-scheds-cargo" scx-scheds
echo "::endgroup::"

echo "::group:: Firmware and Host Libraries"
dnf5 install -y linux-firmware gtk2
echo "::endgroup::"

echo "::group:: Power Tuning (TuneD + RyzenAdj)"
# Replace power-profiles-daemon with tuned and tuned-ppd for dynamic accelerator profiles
dnf5 remove -y power-profiles-daemon
dnf5 install -y tuned tuned-ppd

# Install musl-static ryzenadj binary
bash /ctx/build/install-ryzenadj.sh
echo "::endgroup::"

echo "::group:: Enable Hardware Services"
systemctl enable ac-wakeup-disable.service
systemctl enable scx_loader.service
systemctl enable tuned.service
echo "::endgroup::"

echo "Strix Halo hardware enablement complete!"
