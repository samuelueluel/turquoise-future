# Turquoise Package & Architecture Manifest

This document codifies the boundary between software baked into the immutable OS image and software managed in userland, explaining where and why Turquoise intentionally diverges from standard Bluefin conventions.

---

## 1. Architectural Philosophy: The Two-Tier Model

Bluefin adheres to a strict "distroless" philosophy: keep the host rootfs virtually empty, delegate CLI tools to Homebrew, and install all GUI apps as Flatpaks.

Turquoise rejects this purism where it harms latency, hardware control, or workstation reliability. Turquoise is a high-performance, single-user workstation image purpose-built for the **HP ZBook Ultra G1a (AMD Strix Halo / Ryzen AI Max+ 395)** running the **Niri Wayland tiling compositor**.

We partition software into two distinct tiers:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ TIER 1: Image-Baked (build/ scripts → /usr)                                  │
│   • Hardware & Kernel Control (kargs, TuneD, RyzenAdj, scx-scheds)           │
│   • Compositor & Display Stack (Niri, Noctalia, greetd, portals, seatd)      │
│   • Daily-Driver Terminal & Shell (Ghostty, Zsh, Yazi, Neovim, Tmux)         │
│   • System Daemons & Media (MPD, PipeWire freeworld, Tailscale)              │
│   • Critical Host Shared Libraries (GTK2 for Stata MP GUI)                   │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │ Isolated runtime boundary
┌──────────────────────────────────────▼───────────────────────────────────────┐
│ TIER 2: Userland Conventions (Managed at User Layer)                         │
│   • Homebrew (custom/brew/*.Brewfile): Ephemeral CLI & dev utilities         │
│   • Flatpak (custom/flatpaks/*.preinstall): Standard desktop GUI apps        │
│   • pipx / uv: Python CLI tools (e.g., amd-debug-tools)                      │
│   • Podman / Distrobox: Compilers, project-specific dev environments         │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Tier 1: Image-Baked Software (Justifications for Bluefin Violations)

Every package baked into the image rootfs must satisfy at least one criterion below:

### A. Hardware Control & Kernel Management
* **Kernel Arguments** (`/usr/lib/bootc/kargs.d/50-strix-halo.kargs`):
  * `amd_pstate=active`: Fixes 10–15W idle power draw on Strix Halo (default passive driver is broken).
  * `ttm.pages_limit=32505856`: Exposes ~124 GB of the 128 GB unified RAM pool to the Radeon 8060S iGPU for local LLM inference.
  * `amd_iommu=off`: Disables IOMMU for ~5–12% throughput boost on UMA memory.
* **sched-ext Userspace Schedulers (`scx-scheds`, `scx_loader`)**:
  * Runs `scx_lavd` or `scx_rusty` for low-latency desktop responsiveness across the 16-core dual-CCD CPU under heavy compute load. Requires D-Bus systemd daemon and BPF privileges.
* **Power Management (`tuned`, `tuned-ppd`, `ryzenadj`)**:
  * Replaces `power-profiles-daemon`. Applies dynamic sysfs/TDP/thermal limits during LLM prompt evaluation.
* **Hardware Quirk Workarounds (`ac-wakeup-disable.service`, UDev rules)**:
  * Stops HP AC adapter insertion from triggering instant suspend resumes.

### B. Compositor & Display Architecture
* **Niri Compositor (`niri`, `xwayland-satellite`)**:
  * Cannot run inside a container or Homebrew; requires direct Linux DRM/KMS, seat management (`seatd`/`logind`), and PAM authentication.
* **Display Manager (`greetd`, `gtkgreet`, `cage`)**:
  * Minimal system login manager that replaces bulky desktop managers (GDM/SDDM).
* **Desktop Shell (`noctalia-shell`, `gtk4-layer-shell`, `matugen`, `gpu-screen-recorder`)**:
  * Integrated Wayland bar, control center, and lock screen.
* **Wayland Portals & Display Helpers (`xdg-desktop-portal-gnome`, `xdg-desktop-portal-gtk`, `kanshi`, `grim`, `slurp`, `wdisplays`)**:
  * Niri uses Smithay (not wlroots), requiring `xdg-desktop-portal-gnome` for screen casting and PipeWire capture.

### C. Daily-Driver Terminal & Interactive Shell
* **Terminal Emulator (`ghostty`, `kitty`)**:
  * Primary terminal must be native to avoid container escape overhead, ensure direct GPU rendering, and provide correct terminfo definitions.
* **Shell & Core Tools (`zsh`, `yazi`, `tmux`, `neovim`, `git`, `chezmoi`)**:
  * Dotfiles are managed by Chezmoi; shell must be fully functional before Homebrew is mounted or initialized.
  * Yazi uses Kitty's graphics protocol for zero-latency image previews.

### D. Host System Daemons & Codecs
* **Audio Daemon (`mpd`, `mpc`, `beets`)**:
  * MPD runs as a user service linked directly to host PipeWire.
* **Codecs (`mesa-va-drivers-freeworld`, `ffmpeg`, `gstreamer1-plugins-ugly`, `libdvdcss`)**:
  * Hardware VA-API encoding/decoding on AMD GPUs without patent-crippled restrictions.
* **VPN (`tailscale`)**:
  * System-level network TUN device and daemon.

### E. Host Shared Library Dependencies
* **GTK2 (`gtk2`)**:
  * Stata's native Linux binary (`xstata-mp`) links directly against X11 and GTK2 libraries. Without `gtk2` in the host rootfs, Stata's GUI cannot run.

---

## 3. Tier 2: Userland Conventions (Following Bluefin)

Software that does not require host rootfs privileges belongs in Tier 2:

### A. Homebrew (`custom/brew/*.Brewfile`)
* Developer command-line tools that update frequently:
  * Formatters, linters, non-critical CLI utilities.
  * Installed automatically at login via `brew bundle` and updated in the background via Bluefin's systemd timers.

### B. Flatpaks (`custom/flatpaks/*.preinstall`)
* General GUI desktop applications isolated from the base OS:
  * Zen Browser, Obsidian, Zotero, Spotify, etc.
  * Declaratively tracked in `.preinstall` manifests and installed during system setup.

### C. Isolated Toolchains
* **pipx / uv**: Standalone Python executables (e.g., `amd-debug-tools`).
* **Podman / Distrobox**: Language SDKs, compilers, project-specific databases, and mutable development containers.

---

## 4. Decision Tree: Where Does a New Package Go?

When adding any new tool, ask:

1. **Does it manage hardware, kernels, power, or drivers?** → **Tier 1 (Image: `build/15-strix-halo.sh`)**
2. **Is it part of the Wayland display stack or login manager?** → **Tier 1 (Image: `build/20-niri.sh`)**
3. **Does a native host binary (like Stata) link directly against its shared libraries?** → **Tier 1 (Image: `build/30-packages.sh`)**
4. **Is it a standard GUI application with a Flatpak?** → **Tier 2 (`custom/flatpaks/default.preinstall`)**
5. **Is it an ephemeral or fast-moving CLI tool?** → **Tier 2 (`custom/brew/default.Brewfile`)**
6. **Is it a compiler, SDK, or language runtime?** → **Tier 2 (Distrobox / Dev Container)**
