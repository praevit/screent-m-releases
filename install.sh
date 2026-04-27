#!/bin/bash
set -euo pipefail

# ============================================================
#  Screentaem Display Client — Installer & Manager
#  https://releases.screentaem.com/install.sh
#
#  Usage: curl -fsSL https://releases.screentaem.com/install.sh | bash
#
#  Handles:
#   - Fresh install (standard or kiosk mode)
#   - Detects existing installation → offer uninstall or reinstall
#   - Kiosk: auto-detects GNOME vs lightweight (minimal X11)
#   - All questions asked upfront before any changes
# ============================================================

RELEASES_BASE="https://releases.screentaem.com/latest"

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_banner() {
  echo ""
  echo -e "${BOLD}  ┌─────────────────────────────────────────┐${NC}"
  echo -e "${BOLD}  │                                         │${NC}"
  echo -e "${BOLD}  │     ${BLUE}Screentaem Display Client${NC}${BOLD}          │${NC}"
  echo -e "${BOLD}  │     ${DIM}Installer & Manager${NC}${BOLD}                │${NC}"
  echo -e "${BOLD}  │                                         │${NC}"
  echo -e "${BOLD}  └─────────────────────────────────────────┘${NC}"
  echo ""
}

info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }
error()   { echo -e "  ${RED}✗${NC}  $1"; }
step()    { echo -e "\n  ${BOLD}[$1/$TOTAL_STEPS]${NC} $2"; }

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  local yn_hint
  if [ "$default" = "y" ]; then yn_hint="[Y/n]"; else yn_hint="[y/N]"; fi

  while true; do
    echo -en "  ${YELLOW}?${NC}  ${prompt} ${DIM}${yn_hint}${NC} "
    read -r answer </dev/tty
    answer="${answer:-$default}"
    case "$answer" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo -e "  ${DIM}   Please answer y or n${NC}" ;;
    esac
  done
}

# ============================================================
#  PHASE 1: Detect Platform
# ============================================================

detect_platform() {
  OS_RAW="$(uname -s)"
  ARCH_RAW="$(uname -m)"

  case "$OS_RAW" in
    Linux*)  PLATFORM="linux" ;;
    Darwin*) PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*)
      error "Windows detected. Please download the installer directly from:"
      info "https://releases.screentaem.com/latest/win/amd"
      exit 1
      ;;
    *)
      error "Unsupported operating system: $OS_RAW"
      exit 1
      ;;
  esac

  case "$ARCH_RAW" in
    x86_64|amd64)   ARCH="x64"; URL_ARCH="amd"; DEB_ARCH="amd64" ;;
    aarch64|arm64)   ARCH="arm64"; URL_ARCH="arm"; DEB_ARCH="arm64" ;;
    *)
      error "Unsupported architecture: $ARCH_RAW"
      exit 1
      ;;
  esac
}

# ============================================================
#  PHASE 2: Detect Existing Installation
# ============================================================

detect_existing_install() {
  EXISTING_INSTALL="none"
  EXISTING_DETAILS=""

  if [ "$PLATFORM" = "linux" ]; then
    # Check kiosk install (kiosk user + system config artifacts)
    # Note: can't check files inside /home/kiosk (chmod 700), so check system-level indicators
    if id "kiosk" &>/dev/null && { [ -f /etc/systemd/system/kiosk-watchdog.service ] \
        || [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ] \
        || grep -q "AutomaticLogin=kiosk" /etc/gdm3/custom.conf 2>/dev/null; }; then
      EXISTING_INSTALL="kiosk"
      EXISTING_DETAILS="kiosk user + system services"
    # Check standard install
    elif [ -f "$HOME/.local/bin/screentaem.AppImage" ]; then
      EXISTING_INSTALL="standard"
      EXISTING_DETAILS="$HOME/.local/bin/screentaem.AppImage"
    fi
  elif [ "$PLATFORM" = "mac" ]; then
    MAC_APP=$(ls -d /Applications/Screentaem*.app 2>/dev/null | head -1)
    if [ -n "$MAC_APP" ]; then
      EXISTING_INSTALL="mac"
      EXISTING_DETAILS="$MAC_APP"
    fi
  fi
}

# ============================================================
#  PHASE 3: Ask ALL Questions Upfront
# ============================================================

ask_questions() {
  echo -e "  ${BOLD}Configuration${NC}"
  echo -e "  ${DIM}─────────────${NC}"
  echo ""

  # --- Handle existing install ---
  if [ "$EXISTING_INSTALL" != "none" ]; then
    warn "Existing installation detected: ${BOLD}${EXISTING_INSTALL}${NC}"
    info "Location: ${DIM}${EXISTING_DETAILS}${NC}"
    echo ""

    echo -e "  ${BOLD}What would you like to do?${NC}"
    echo ""
    echo -e "    ${BOLD}1${NC}  Uninstall"
    echo -e "    ${BOLD}2${NC}  Reinstall (uninstall + fresh install)"
    echo -e "    ${BOLD}3${NC}  Repair (re-run setup without removing data)"
    echo -e "    ${BOLD}4${NC}  Exit"
    echo ""
    while true; do
      echo -en "  ${YELLOW}?${NC}  Choose an option ${DIM}[1-4]${NC} "
      read -r choice </dev/tty
      case "$choice" in
        1) ACTION="uninstall"; break ;;
        2) ACTION="reinstall"; break ;;
        3) ACTION="repair"; break ;;
        4) info "Exiting."; exit 0 ;;
        *) echo -e "  ${DIM}   Please enter 1, 2, 3, or 4${NC}" ;;
      esac
    done
    echo ""

    # If uninstall-only, ask about optional removals
    if [ "$ACTION" = "uninstall" ] && [ "$EXISTING_INSTALL" = "kiosk" ]; then
      UNINSTALL_GPU="n"
      if ask_yn "Also remove GPU drivers (nvidia/mesa)?" "n"; then
        UNINSTALL_GPU="y"
      fi

      UNINSTALL_CHROME="n"
      if command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null; then
        if ask_yn "Also remove Google Chrome?" "n"; then
          UNINSTALL_CHROME="y"
        fi
      fi

      UNINSTALL_X11="n"
      if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
        # Lightweight mode was used
        if ask_yn "Also remove minimal X11 packages (xorg, xinit, openbox)?" "n"; then
          UNINSTALL_X11="y"
        fi
      fi
      return
    fi

    if [ "$ACTION" = "uninstall" ]; then
      return
    fi

    # Repair: re-run provisioning with detected settings, no extra questions needed
    if [ "$ACTION" = "repair" ]; then
      KIOSK_MODE="y"
      AUTO_START="y"
      SSH_CHOICE="y"  # keep SSH as-is during repair

      # Detect which display mode was used
      if [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
        DISPLAY_MODE="lightweight"
      elif grep -q "AutomaticLogin=kiosk" /etc/gdm3/custom.conf 2>/dev/null; then
        DISPLAY_MODE="gnome"
      else
        DISPLAY_MODE="lightweight"
      fi

      info "Repair mode: will re-run kiosk setup (${BOLD}${DISPLAY_MODE}${NC})"
      info "This re-installs dependencies, fixes symlinks, and re-deploys configs"
      return
    fi
  else
    ACTION="install"
  fi

  # --- Install questions ---
  KIOSK_MODE="n"
  AUTO_START="n"
  SSH_CHOICE="n"
  DISPLAY_MODE=""

  if [ "$PLATFORM" = "linux" ]; then
    if ask_yn "Is this a dedicated kiosk device? (auto-login, watchdog, security hardening)" "n"; then
      KIOSK_MODE="y"
      AUTO_START="y"

      # Detect display environment for kiosk
      if dpkg -l ubuntu-desktop &>/dev/null 2>&1 && command -v gdm3 &>/dev/null 2>&1; then
        DISPLAY_MODE="gnome"
      elif dpkg -l gnome-shell &>/dev/null 2>&1 && command -v gdm3 &>/dev/null 2>&1; then
        DISPLAY_MODE="gnome"
      else
        DISPLAY_MODE="lightweight"
      fi

      echo ""
      if [ "$DISPLAY_MODE" = "gnome" ]; then
        info "GNOME Desktop detected — will use existing desktop environment"
      else
        info "No desktop detected — will install minimal X11 + openbox (~50 MB)"
      fi
      echo ""

      # Kiosk-specific questions
      echo -e "  ${DIM}SSH allows remote access for maintenance.${NC}"
      if ask_yn "Keep SSH enabled?" "y"; then
        SSH_CHOICE="y"
      fi
    fi
  fi

  if [ "$KIOSK_MODE" = "n" ]; then
    if ask_yn "Enable auto-start on boot?" "y"; then
      AUTO_START="y"
    fi
  fi

  echo ""
}

# ============================================================
#  PHASE 4: Summary & Confirm
# ============================================================

print_summary() {
  echo -e "  ${BOLD}Summary${NC}"
  echo -e "  ${DIM}───────${NC}"
  success "Platform: ${BOLD}${PLATFORM}${NC} (${ARCH})"

  if [ "$ACTION" = "uninstall" ]; then
    success "Action: ${BOLD}Uninstall${NC} (${EXISTING_INSTALL} mode)"
    echo ""
    if ! ask_yn "Proceed with uninstall?" "y"; then
      info "Cancelled."
      exit 0
    fi
    return
  fi

  if [ "$ACTION" = "reinstall" ]; then
    success "Action: ${BOLD}Reinstall${NC} (uninstall ${EXISTING_INSTALL} → fresh install)"
  elif [ "$ACTION" = "repair" ]; then
    success "Action: ${BOLD}Repair${NC} (re-run setup, keep data)"
  fi

  if [ "$PLATFORM" = "linux" ]; then
    DOWNLOAD_URL="${RELEASES_BASE}/linux/${URL_ARCH}"

    if [ "$KIOSK_MODE" = "y" ]; then
      success "Mode: ${BOLD}Kiosk deployment${NC} (dedicated device)"
      if [ "$DISPLAY_MODE" = "gnome" ]; then
        success "Display: ${BOLD}GNOME${NC} (existing desktop)"
      else
        success "Display: ${BOLD}Lightweight${NC} (minimal X11 + openbox)"
      fi
      success "SSH: ${BOLD}$([ "$SSH_CHOICE" = "y" ] && echo "enabled" || echo "disabled")${NC}"
      success "Security: firewall, auto-updates, USB block, core dump off"
    else
      success "Mode: ${BOLD}Standard install${NC}"
      if [ "$AUTO_START" = "y" ]; then
        success "Auto-start: ${BOLD}enabled${NC}"
      else
        info "Auto-start: disabled"
      fi
    fi

    success "Download: ${DIM}${DOWNLOAD_URL}${NC}"
  elif [ "$PLATFORM" = "mac" ]; then
    DOWNLOAD_URL="${RELEASES_BASE}/mac/${URL_ARCH}"
    success "Download: ${DIM}${DOWNLOAD_URL}${NC}"
    if [ "$AUTO_START" = "y" ]; then
      success "Auto-start: ${BOLD}enabled${NC} (Login Items)"
    else
      info "Auto-start: disabled"
    fi
  fi

  echo ""

  if ! ask_yn "Proceed with installation?" "y"; then
    info "Installation cancelled."
    exit 0
  fi
}

# ============================================================
#  Uninstall Functions
# ============================================================

uninstall_linux_standard() {
  TOTAL_STEPS=2
  step 1 "Removing Screentaem..."

  rm -f "$HOME/.local/bin/screentaem.AppImage"
  rm -f "$HOME/.config/autostart/screentaem.desktop"
  rm -f "$HOME/Desktop/screentaem.desktop"
  success "AppImage, autostart, and shortcut removed"

  step 2 "Cleanup..."
  success "Standard install removed"
}

uninstall_linux_kiosk() {
  TOTAL_STEPS=3

  step 1 "Preparing kiosk uninstall..."

  # Detect which kiosk mode was used
  local KIOSK_INSTALL_MODE="unknown"
  if [ -f /etc/gdm3/custom.conf ] && grep -q "AutomaticLogin=kiosk" /etc/gdm3/custom.conf 2>/dev/null; then
    KIOSK_INSTALL_MODE="gnome"
  elif [ -f /etc/systemd/system/getty@tty1.service.d/autologin.conf ]; then
    KIOSK_INSTALL_MODE="lightweight"
  fi

  info "Detected kiosk mode: ${BOLD}${KIOSK_INSTALL_MODE}${NC}"

  step 2 "Running kiosk uninstall (requires sudo)..."
  echo ""

  # Build the uninstall script with pre-answered choices
  local TMP_UNINSTALL
  TMP_UNINSTALL=$(mktemp /tmp/screentaem-uninstall.XXXXXX.sh)

  cat > "$TMP_UNINSTALL" << 'UNINSTALL_SCRIPT'
#!/bin/bash
set -e

KIOSK_USER="kiosk"
KIOSK_HOME="/home/$KIOSK_USER"
KIOSK_INSTALL_MODE="$1"
UNINSTALL_GPU="$2"
UNINSTALL_CHROME="$3"
UNINSTALL_X11="$4"
LOG="/tmp/screentaem-uninstall.log"
> "$LOG"
TOTAL=7

progress() {
    local step=$1
    local msg=$2
    local pct=$((step * 100 / TOTAL))
    local w=30
    local filled=$((pct * w / 100))
    local bar=""
    for ((i=0; i<w; i++)); do
        if [ $i -lt $filled ]; then bar+="█"; else bar+="░"; fi
    done
    printf "\r  [%s] %3d%%  %s — %-45s" "$bar" "$pct" "[$step/$TOTAL]" "$msg"
}

trap 'echo ""; echo ""; echo "  ✗ Uninstall failed. Log:"; echo "  ──────────────────────────────────────────────"; tail -15 "$LOG" 2>/dev/null | sed "s/^/  > /"; echo "  ──────────────────────────────────────────────"; echo "  Full log: $LOG"' ERR

echo ""

progress 1 "Stopping kiosk services..."
systemctl stop kiosk-watchdog.service >> "$LOG" 2>&1 || true
systemctl disable kiosk-watchdog.service >> "$LOG" 2>&1 || true
rm -f /etc/systemd/system/kiosk-watchdog.service
pkill -f "screentaem-launcher" >> "$LOG" 2>&1 || true
pkill -f "screentaem.AppImage" >> "$LOG" 2>&1 || true
systemctl daemon-reload >> "$LOG" 2>&1

progress 2 "Restoring auto-login configuration..."
if [ "$KIOSK_INSTALL_MODE" = "gnome" ] || [ "$KIOSK_INSTALL_MODE" = "unknown" ]; then
    GDM_CONF="/etc/gdm3/custom.conf"
    if [ -f "${GDM_CONF}.bak" ]; then
        mv "${GDM_CONF}.bak" "$GDM_CONF"
    elif [ -f "$GDM_CONF" ]; then
        cat > "$GDM_CONF" << 'GDMEOF'
[daemon]

[security]

[xdmcp]

[chooser]

[debug]
GDMEOF
    fi
fi
if [ "$KIOSK_INSTALL_MODE" = "lightweight" ] || [ "$KIOSK_INSTALL_MODE" = "unknown" ]; then
    rm -rf /etc/systemd/system/getty@tty1.service.d >> "$LOG" 2>&1 || true
    rm -f /etc/X11/Xwrapper.config >> "$LOG" 2>&1 || true
fi
systemctl daemon-reload >> "$LOG" 2>&1

progress 3 "Restoring power management..."
systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target >> "$LOG" 2>&1 || true
systemctl unmask ctrl-alt-del.target >> "$LOG" 2>&1 || true

progress 4 "Resetting firewall..."
ufw disable >> "$LOG" 2>&1 || true

progress 5 "Removing security hardening..."
rm -f /etc/modprobe.d/block-usb-storage.conf
sed -i '/^\* hard core 0$/d' /etc/security/limits.conf 2>/dev/null || true
rm -f /etc/sysctl.d/99-kiosk-security.conf
rm -f /etc/NetworkManager/conf.d/dns-fallback.conf
rm -f /etc/systemd/resolved.conf.d/fallback-dns.conf
systemctl restart systemd-resolved >> "$LOG" 2>&1 || true
systemctl restart NetworkManager >> "$LOG" 2>&1 || true

if [ "$KIOSK_INSTALL_MODE" = "gnome" ] || [ "$KIOSK_INSTALL_MODE" = "unknown" ]; then
    PAM_GDM="/etc/pam.d/gdm-autologin"
    if [ -f "${PAM_GDM}.screentaem-bak" ]; then
        mv "${PAM_GDM}.screentaem-bak" "$PAM_GDM"
    fi
fi

progress 6 "Removing kiosk user..."
if id "$KIOSK_USER" >> "$LOG" 2>&1; then
    pkill -u "$KIOSK_USER" >> "$LOG" 2>&1 || true
    sleep 1
    userdel -r "$KIOSK_USER" >> "$LOG" 2>&1 || true
fi

progress 7 "Removing optional packages..."
if [ "$UNINSTALL_GPU" = "y" ]; then
    apt remove -y nvidia-driver-* mesa-vulkan-drivers mesa-va-drivers intel-media-va-driver --autoremove >> "$LOG" 2>&1 || true
fi
if [ "$UNINSTALL_CHROME" = "y" ]; then
    apt remove -y google-chrome-stable --autoremove >> "$LOG" 2>&1 || true
fi
if [ "$UNINSTALL_X11" = "y" ]; then
    apt remove -y xorg xinit openbox --autoremove >> "$LOG" 2>&1 || true
fi

progress $TOTAL "Done!"
echo ""
echo ""
UNINSTALL_SCRIPT

  chmod +x "$TMP_UNINSTALL"
  sudo bash "$TMP_UNINSTALL" "$KIOSK_INSTALL_MODE" "${UNINSTALL_GPU:-n}" "${UNINSTALL_CHROME:-n}" "${UNINSTALL_X11:-n}"
  local UNINSTALL_EXIT=$?
  rm -f "$TMP_UNINSTALL"

  if [ "$UNINSTALL_EXIT" -ne 0 ]; then
    error "Kiosk uninstall failed (exit code $UNINSTALL_EXIT)."
    exit 1
  fi

  step 3 "Cleanup..."
  success "Kiosk install fully removed"
}

uninstall_mac() {
  TOTAL_STEPS=2
  step 1 "Removing Screentaem..."

  local MAC_APP
  MAC_APP=$(ls -d /Applications/Screentaem*.app 2>/dev/null | head -1)
  if [ -n "$MAC_APP" ]; then
    local APP_NAME
    APP_NAME=$(basename "$MAC_APP")
    rm -rf "$MAC_APP"
    # Remove from Login Items
    osascript -e "tell application \"System Events\" to delete login item \"${APP_NAME%.app}\"" 2>/dev/null || true
    success "Removed ${BOLD}${MAC_APP}${NC} and Login Items entry"
  fi

  step 2 "Cleanup..."
  success "macOS install removed"
}

# ============================================================
#  Install Functions
# ============================================================

install_linux_standard() {
  INSTALL_DIR="$HOME/.local/bin"
  APPIMAGE_PATH="$INSTALL_DIR/screentaem.AppImage"

  step 1 "Downloading Screentaem..."
  mkdir -p "$INSTALL_DIR"
  curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$APPIMAGE_PATH"
  chmod +x "$APPIMAGE_PATH"
  success "Downloaded to ${BOLD}${APPIMAGE_PATH}${NC}"

  if [ "$AUTO_START" = "y" ]; then
    step 2 "Setting up auto-start..."
    AUTOSTART_DIR="$HOME/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_DIR/screentaem.desktop" << DEOF
[Desktop Entry]
Type=Application
Name=Screentaem
Exec=$APPIMAGE_PATH --no-sandbox --kiosk
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
DEOF
    success "Autostart entry created"
  fi

  local NEXT_STEP=2
  if [ "$AUTO_START" = "y" ]; then NEXT_STEP=3; fi
  step $NEXT_STEP "Creating desktop shortcut..."
  DESKTOP_DIR="$HOME/Desktop"
  if [ -d "$DESKTOP_DIR" ]; then
    cat > "$DESKTOP_DIR/screentaem.desktop" << DEOF
[Desktop Entry]
Type=Application
Name=Screentaem
Exec=$APPIMAGE_PATH --no-sandbox --kiosk
Terminal=false
Icon=screentaem
DEOF
    chmod +x "$DESKTOP_DIR/screentaem.desktop"
    success "Desktop shortcut created"
  else
    info "No Desktop directory found, skipping shortcut"
  fi
}

# Run the kiosk provisioning script with a given AppImage path
run_kiosk_provision() {
  local APPIMAGE_FOR_PROVISION="$1"

  # Build the provisioning script with pre-answered choices baked in
  local TMP_PROVISION
  TMP_PROVISION=$(mktemp /tmp/screentaem-provision.XXXXXX.sh)

  # Write the kiosk provisioning script
  cat > "$TMP_PROVISION" << 'PROVISION_SCRIPT'
#!/bin/bash
set -euo pipefail

APPIMAGE_PATH="$1"
DISPLAY_MODE="$2"
SSH_CHOICE="$3"
DEB_ARCH="$4"
KIOSK_USER="kiosk"
KIOSK_HOME="/home/$KIOSK_USER"
LOG="/tmp/screentaem-install.log"
> "$LOG"

if [ "$DISPLAY_MODE" = "gnome" ]; then
    TOTAL=12
else
    TOTAL=11
fi

# --- Progress bar ---
progress() {
    local step=$1
    local msg=$2
    local pct=$((step * 100 / TOTAL))
    local w=30
    local filled=$((pct * w / 100))
    local bar=""
    for ((i=0; i<w; i++)); do
        if [ $i -lt $filled ]; then bar+="█"; else bar+="░"; fi
    done
    printf "\r  [%s] %3d%%  %s — %-45s" "$bar" "$pct" "[$step/$TOTAL]" "$msg"
}

# On error, show tail of log
trap 'echo ""; echo ""; echo "  ✗ Installation failed. Log:"; echo "  ──────────────────────────────────────────────"; tail -15 "$LOG" 2>/dev/null | sed "s/^/  > /"; echo "  ──────────────────────────────────────────────"; echo "  Full log: $LOG"' ERR

echo ""

# --- 1. System update + dependencies ---
progress 1 "Updating system & installing dependencies..."
apt update >> "$LOG" 2>&1 || true

IS_UBUNTU="n"
if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
    IS_UBUNTU="y"
fi

# Core packages (exist on all Debian-based distros)
if [ "$DISPLAY_MODE" = "gnome" ]; then
    apt install -y \
        fuse3 xdotool pulseaudio alsa-utils \
        wget curl pciutils \
        --no-install-recommends >> "$LOG" 2>&1 || true
else
    apt install -y \
        xorg xinit openbox xterm fuse3 \
        pulseaudio alsa-utils wget curl pciutils \
        dbus-x11 network-manager \
        --no-install-recommends >> "$LOG" 2>&1 || true
fi

# Electron dependencies — try standard names first, fall back to t64 variants (Debian Trixie+)
# Each package tried individually so one failure doesn't block the rest
for pkg in zlib1g libnss3 libdrm2 libgbm1 libpango-1.0-0 libcairo2 \
           libxcomposite1 libxdamage1 libxrandr2 libxkbcommon0; do
    apt install -y "$pkg" --no-install-recommends >> "$LOG" 2>&1 || true
done

# Packages that were renamed in the t64 transition
for pkg_pair in "libatk1.0-0:libatk1.0-0t64" "libatk-bridge2.0-0:libatk-bridge2.0-0t64" \
                "libcups2:libcups2t64" "libgtk-3-0:libgtk-3-0t64" "libfuse2:libfuse2t64"; do
    old="${pkg_pair%%:*}"
    new="${pkg_pair##*:}"
    apt install -y "$old" --no-install-recommends >> "$LOG" 2>&1 \
        || apt install -y "$new" --no-install-recommends >> "$LOG" 2>&1 \
        || true
done

if [ "$IS_UBUNTU" = "y" ]; then
    apt install -y ubuntu-drivers-common --no-install-recommends >> "$LOG" 2>&1 || true
fi

# Fix unversioned .so symlinks — AppImage may need libz.so but distro only ships libz.so.1
# Detect the lib directory for this architecture
LIB_DIR=$(ldconfig -p 2>/dev/null | grep "libz.so.1" | head -1 | sed 's/.*=> //' | xargs dirname 2>/dev/null || echo "/usr/lib")
for lib in libz libGLESv2 libEGL; do
    versioned=$(ldconfig -p 2>/dev/null | grep "${lib}.so\." | head -1 | sed 's/.*=> //' || true)
    if [ -n "$versioned" ] && [ ! -e "$LIB_DIR/${lib}.so" ]; then
        ln -sf "$versioned" "$LIB_DIR/${lib}.so" 2>/dev/null || true
        echo "Symlinked ${lib}.so -> $versioned" >> "$LOG"
    fi
done
ldconfig >> "$LOG" 2>&1 || true

# --- 2. Google Chrome ---
progress 2 "Installing Google Chrome..."
if command -v google-chrome >> "$LOG" 2>&1 || command -v google-chrome-stable >> "$LOG" 2>&1; then
    echo "Chrome already installed" >> "$LOG"
else
    if [ "$DEB_ARCH" = "amd64" ]; then
        wget -q -O /tmp/google-chrome.deb \
            "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" >> "$LOG" 2>&1
        apt install -y /tmp/google-chrome.deb >> "$LOG" 2>&1 || apt --fix-broken install -y >> "$LOG" 2>&1
        rm -f /tmp/google-chrome.deb
    else
        echo "Chrome not available for $DEB_ARCH (amd64 only), skipping" >> "$LOG"
    fi
fi

# --- 3. GPU drivers ---
progress 3 "Detecting GPU & installing drivers..."
GPU_INFO=$(lspci | grep -iE "vga|3d|display" || true)
echo "GPU: $GPU_INFO" >> "$LOG"

if echo "$GPU_INFO" | grep -qi "nvidia"; then
    if command -v ubuntu-drivers &>/dev/null; then
        ubuntu-drivers install --gpgpu nvidia >> "$LOG" 2>&1 || ubuntu-drivers autoinstall >> "$LOG" 2>&1 || true
    else
        apt install -y nvidia-driver >> "$LOG" 2>&1 || apt install -y nvidia-kernel-dkms >> "$LOG" 2>&1 || true
    fi
elif echo "$GPU_INFO" | grep -qi "amd\|radeon"; then
    apt install -y mesa-vulkan-drivers mesa-va-drivers --no-install-recommends >> "$LOG" 2>&1 || true
elif echo "$GPU_INFO" | grep -qi "intel"; then
    apt install -y intel-media-va-driver mesa-vulkan-drivers --no-install-recommends >> "$LOG" 2>&1 || true
fi

# --- 4. Network ---
progress 4 "Configuring network..."
systemctl enable NetworkManager >> "$LOG" 2>&1
systemctl start NetworkManager >> "$LOG" 2>&1

mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/fallback-dns.conf << 'DNSEOF'
[Resolve]
FallbackDNS=8.8.8.8 1.1.1.1
DNSEOF
systemctl restart systemd-resolved >> "$LOG" 2>&1 || true

# --- 5. Security updates ---
progress 5 "Configuring automatic security updates..."
apt install -y unattended-upgrades --no-install-recommends >> "$LOG" 2>&1
apt install -y apt-listchanges --no-install-recommends >> "$LOG" 2>&1 || true

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
UUEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
AUEOF

systemctl enable unattended-upgrades >> "$LOG" 2>&1

# --- Firewall capability probe ---
# Some embedded ARM kernels (e.g. Orange Pi Zero 3 / Armbian vendor builds) ship
# without netfilter modules, so `ufw enable` aborts. Dry-run UFW's actual rule
# files via `iptables-restore --test` and only commit if every file loads.
firewall_supported() {
    for mod in nf_conntrack iptable_filter ip6table_filter \
               xt_conntrack xt_LOG xt_addrtype xt_limit xt_REJECT \
               xt_state xt_recent; do
        modprobe "$mod" >> "$LOG" 2>&1 || true
    done

    local f failed=0
    for f in /etc/ufw/before.rules /etc/ufw/after.rules /etc/ufw/user.rules; do
        [ -f "$f" ] || continue
        if ! iptables-restore --test < "$f" >> "$LOG" 2>&1; then
            echo "WARN: iptables-restore --test failed on $f" >> "$LOG"
            failed=1
        fi
    done
    for f in /etc/ufw/before6.rules /etc/ufw/after6.rules /etc/ufw/user6.rules; do
        [ -f "$f" ] || continue
        if ! ip6tables-restore --test < "$f" >> "$LOG" 2>&1; then
            echo "WARN: ip6tables-restore --test failed on $f" >> "$LOG"
            failed=1
        fi
    done
    return $failed
}

# --- 6. Firewall ---
progress 6 "Configuring firewall..."
apt install -y ufw iptables --no-install-recommends >> "$LOG" 2>&1 || true

FIREWALL_ENABLED="n"
if firewall_supported; then
    ufw default deny incoming >> "$LOG" 2>&1
    ufw default allow outgoing >> "$LOG" 2>&1
    if ufw --force enable >> "$LOG" 2>&1; then
        FIREWALL_ENABLED="y"
    else
        echo "WARN: ufw --force enable failed despite dry-run passing; continuing without firewall" >> "$LOG"
    fi
else
    echo "WARN: kernel lacks netfilter extensions required by UFW; skipping host firewall" >> "$LOG"
    echo "WARN: device must rely on upstream/network firewall instead" >> "$LOG"
fi

# --- 7. SSH + hardening ---
progress 7 "Configuring SSH & security hardening..."
case "$SSH_CHOICE" in
    [yY]|[yY][eE][sS])
        [ "$FIREWALL_ENABLED" = "y" ] && ufw allow ssh >> "$LOG" 2>&1 || true
        ;;
    *)
        systemctl disable --now ssh >> "$LOG" 2>&1 || true
        [ "$FIREWALL_ENABLED" = "y" ] && ufw deny ssh >> "$LOG" 2>&1 || true
        ;;
esac

echo "* hard core 0" >> /etc/security/limits.conf
echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/99-kiosk-security.conf
echo "blacklist usb-storage" > /etc/modprobe.d/block-usb-storage.conf
sysctl -p /etc/sysctl.d/99-kiosk-security.conf >> "$LOG" 2>&1 || true

# --- 8. Kiosk user ---
progress 8 "Creating kiosk user..."
if ! id "$KIOSK_USER" >> "$LOG" 2>&1; then
    useradd -m -s /bin/bash "$KIOSK_USER"
fi
usermod -aG audio,video,input,plugdev,tty "$KIOSK_USER"
chmod 700 "$KIOSK_HOME"

# --- 9. AppImage ---
progress 9 "Deploying AppImage..."
mkdir -p "$KIOSK_HOME/app"
cp "$APPIMAGE_PATH" "$KIOSK_HOME/app/screentaem.AppImage"
chmod +x "$KIOSK_HOME/app/screentaem.AppImage"

mkdir -p "$KIOSK_HOME/.local/share/icons"
ICON_PATH="$KIOSK_HOME/.local/share/icons/screentaem.png"

cd /tmp
"$KIOSK_HOME/app/screentaem.AppImage" --appimage-extract "*.png" >> "$LOG" 2>&1 || true
if [ -f /tmp/squashfs-root/.DirIcon ]; then
    cp /tmp/squashfs-root/.DirIcon "$ICON_PATH"
elif [ -f /tmp/squashfs-root/icon.png ]; then
    cp /tmp/squashfs-root/icon.png "$ICON_PATH"
elif ls /tmp/squashfs-root/usr/share/icons/hicolor/256x256/apps/*.png >> "$LOG" 2>&1; then
    cp /tmp/squashfs-root/usr/share/icons/hicolor/256x256/apps/*.png "$ICON_PATH" 2>/dev/null || true
fi
rm -rf /tmp/squashfs-root

if [ ! -f "$ICON_PATH" ]; then
    ICON_PATH="application-x-executable"
fi

chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/app"
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.local"

# --- Launcher wrapper (shared) ---
cat > "$KIOSK_HOME/app/screentaem-launcher.sh" << 'LAUNCHEREOF'
#!/bin/bash
KIOSK_HOME="/home/kiosk"
CRASH_FLAG="$KIOSK_HOME/.app-crashed"
LOG_FILE="$KIOSK_HOME/app/screentaem.log"
APPIMAGE="$KIOSK_HOME/app/screentaem.AppImage"

rm -f "$CRASH_FLAG"

# Build Electron flags
ELECTRON_FLAGS="--no-sandbox --kiosk"

# Force X11 (Electron 28+ may auto-detect Wayland even when not running)
ELECTRON_FLAGS="$ELECTRON_FLAGS --ozone-platform=x11"

# ARM GPU compatibility (Mali, Panfrost, Lima, etc.)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ELECTRON_FLAGS="$ELECTRON_FLAGS --disable-gpu-sandbox"
    # If GPU acceleration causes crashes, fall back to software rendering
    if [ -f "$KIOSK_HOME/.disable-gpu" ]; then
        ELECTRON_FLAGS="$ELECTRON_FLAGS --disable-gpu"
    fi
fi

# Try running AppImage normally, fall back to extract-and-run if FUSE fails
if "$APPIMAGE" $ELECTRON_FLAGS 2>>"$LOG_FILE"; then
    EXIT_CODE=0
else
    EXIT_CODE=$?
    # If exit code 127 or AppImage can't mount (FUSE issue), try extract-and-run
    if [ $EXIT_CODE -eq 127 ] || [ $EXIT_CODE -eq 1 ]; then
        if ! grep -q "FUSE_RETRY_DONE" "$LOG_FILE" 2>/dev/null; then
            echo "[screentaem-launcher] Retrying with --appimage-extract-and-run..." >> "$LOG_FILE"
            echo "FUSE_RETRY_DONE" >> "$LOG_FILE"
            APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGE" $ELECTRON_FLAGS 2>>"$LOG_FILE"
            EXIT_CODE=$?
        fi
    fi
fi

if [ $EXIT_CODE -ne 0 ]; then
    echo "[screentaem-launcher] App exited with code $EXIT_CODE — see $LOG_FILE" | tee -a "$LOG_FILE"
    touch "$CRASH_FLAG"
fi

# Keep log file from growing indefinitely
if [ -f "$LOG_FILE" ] && [ "$(wc -c < "$LOG_FILE")" -gt 1048576 ]; then
    tail -c 524288 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi
LAUNCHEREOF
chmod +x "$KIOSK_HOME/app/screentaem-launcher.sh"
chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/app/screentaem-launcher.sh"

# --- Smoke test: verify AppImage can at least start ---
progress 9 "Verifying AppImage runs..."
SMOKE_LOG="$KIOSK_HOME/app/smoke-test.log"
SMOKE_FLAGS="--no-sandbox --ozone-platform=x11 --disable-gpu-sandbox --disable-gpu"

# Try to run it briefly — it will fail without a display but should at least load the binary
if DISPLAY=:99 timeout 5 "$KIOSK_HOME/app/screentaem.AppImage" $SMOKE_FLAGS > "$SMOKE_LOG" 2>&1; then
    echo "Smoke test: app exited cleanly" >> "$LOG"
else
    SMOKE_EXIT=$?
    # Timeout (exit 124) = good, it means the binary loaded and was still running
    # Exit 1 with "Display" error = good, binary works but no X display
    if [ $SMOKE_EXIT -eq 124 ]; then
        echo "Smoke test: OK (binary loaded, timed out as expected)" >> "$LOG"
    elif [ $SMOKE_EXIT -eq 139 ] || [ $SMOKE_EXIT -eq 134 ] || [ $SMOKE_EXIT -eq 11 ]; then
        # Segfault/abort when trying to connect to non-existent X display — binary loaded fine
        echo "Smoke test: OK (binary loaded, crashed on missing display as expected)" >> "$LOG"
    elif grep -qi "cannot open display\|display.*not found\|no display\|Failed to connect\|Missing X server\|platform failed to initialize" "$SMOKE_LOG" 2>/dev/null; then
        echo "Smoke test: OK (binary works, no display available during install)" >> "$LOG"
    else
        # Real failure — AppImage can't run at all
        echo ""
        echo ""
        echo "  ! AppImage failed to start. This may cause issues after reboot."
        echo "  Smoke test output:"
        tail -5 "$SMOKE_LOG" 2>/dev/null | sed "s/^/    /"
        echo ""
        echo "  If the app doesn't work after reboot, check:"
        echo "    cat /home/kiosk/app/screentaem.log"
        echo ""
    fi
fi
rm -f "$SMOKE_LOG"

# =================================================================
#  Session configuration (branched by display mode)
# =================================================================

if [ "$DISPLAY_MODE" = "gnome" ]; then

    # --- 10. Configure GDM3 auto-login ---
    progress 10 "Configuring GNOME auto-login..."

    GDM_CONF="/etc/gdm3/custom.conf"
    if [ -f "$GDM_CONF" ]; then
        cp "$GDM_CONF" "${GDM_CONF}.bak"
    fi

    cat > "$GDM_CONF" << GDMEOF
# GDM configuration — Screentaem kiosk
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$KIOSK_USER
WaylandEnable=false

[security]

[xdmcp]

[chooser]

[debug]
GDMEOF

    mkdir -p "$KIOSK_HOME/.config"
    echo "yes" > "$KIOSK_HOME/.config/gnome-initial-setup-done"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"
    # --- 11. Autostart, desktop shortcut, GNOME settings ---
    progress 11 "Setting up autostart & GNOME kiosk settings..."

    mkdir -p "$KIOSK_HOME/.config/autostart"
    mkdir -p "$KIOSK_HOME/Desktop"

    # Disable GNOME Keyring
    for keyring_desktop in /etc/xdg/autostart/gnome-keyring-*.desktop; do
        if [ -f "$keyring_desktop" ]; then
            cat > "$KIOSK_HOME/.config/autostart/$(basename "$keyring_desktop")" << KEOF
[Desktop Entry]
Hidden=true
KEOF
        fi
    done

    PAM_GDM="/etc/pam.d/gdm-autologin"
    if [ -f "$PAM_GDM" ]; then
        cp "$PAM_GDM" "${PAM_GDM}.screentaem-bak"
        sed -i '/pam_gnome_keyring\.so/s/^/#/' "$PAM_GDM"
    fi

    mkdir -p "$KIOSK_HOME/.config/systemd/user"
    ln -sf /dev/null "$KIOSK_HOME/.config/systemd/user/gnome-keyring-daemon.socket" 2>/dev/null || true
    ln -sf /dev/null "$KIOSK_HOME/.config/systemd/user/gnome-keyring-daemon.service" 2>/dev/null || true

    # Autostart desktop entry
    cat > "$KIOSK_HOME/.config/autostart/screentaem.desktop" << ASEOF
[Desktop Entry]
Type=Application
Name=Screentaem
Comment=Digital Signage Kiosk Display
Exec=$KIOSK_HOME/app/screentaem-launcher.sh
Icon=$ICON_PATH
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
ASEOF

    # Desktop shortcut
    cat > "$KIOSK_HOME/Desktop/screentaem.desktop" << DSEOF
[Desktop Entry]
Type=Application
Name=Screentaem
Comment=Launch Screentaem Kiosk Display
Exec=$KIOSK_HOME/app/screentaem-launcher.sh
Icon=$ICON_PATH
Terminal=false
Categories=Utility;
DSEOF
    chmod +x "$KIOSK_HOME/Desktop/screentaem.desktop"

    # Trust desktop file (GNOME 42+)
    cat > "$KIOSK_HOME/.config/autostart/trust-desktop-file.desktop" << 'TRUSTEOF'
[Desktop Entry]
Type=Application
Name=Trust Desktop Files
Exec=bash -c 'sleep 2; gio set ~/Desktop/screentaem.desktop metadata::trusted true 2>/dev/null; rm -f ~/.config/autostart/trust-desktop-file.desktop'
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=1
NoDisplay=true
TRUSTEOF

    # GNOME kiosk settings (one-shot)
    cat > "$KIOSK_HOME/app/gnome-kiosk-setup.sh" << 'SETUPEOF'
#!/bin/bash
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false 2>/dev/null || true
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing' 2>/dev/null || true
gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null || true
amixer -q sset Master 100% unmute 2>/dev/null || true
amixer -q sset PCM 100% unmute 2>/dev/null || true
pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null || true
pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true
touch "$HOME/.gnome-kiosk-setup-done"
SETUPEOF
    chmod +x "$KIOSK_HOME/app/gnome-kiosk-setup.sh"

    cat > "$KIOSK_HOME/.config/autostart/gnome-kiosk-setup.desktop" << GSEOF
[Desktop Entry]
Type=Application
Name=Kiosk GNOME Setup
Exec=bash -c 'if [ ! -f \$HOME/.gnome-kiosk-setup-done ]; then $KIOSK_HOME/app/gnome-kiosk-setup.sh; fi'
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=1
NoDisplay=true
GSEOF

    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/Desktop"
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/app/gnome-kiosk-setup.sh"

else
    # =============================================================
    #  LIGHTWEIGHT MODE: getty auto-login + xinit + openbox
    # =============================================================

    # --- 10. Configure getty auto-login on tty1 ---
    progress 10 "Configuring lightweight auto-login..."

    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << GETTYEOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $KIOSK_USER --noclear %I \$TERM
GETTYEOF

    mkdir -p /etc/X11
    echo "allowed_users=anybody" > /etc/X11/Xwrapper.config

    # --- 11. Create .xinitrc, .bash_profile, and openbox config ---
    progress 11 "Creating X11 session & kiosk settings..."

    mkdir -p "$KIOSK_HOME/.config/openbox"

    # Auto-start X on tty1 login
    # Write to both .profile and .bash_profile for cross-distro compatibility
    # (some systems source .profile, others .bash_profile)
    STARTX_BLOCK='# Auto-start X on tty1 (kiosk mode)
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi'
    echo "$STARTX_BLOCK" > "$KIOSK_HOME/.bash_profile"
    echo "$STARTX_BLOCK" > "$KIOSK_HOME/.profile"

    # .xinitrc: the entire kiosk session
    cat > "$KIOSK_HOME/.xinitrc" << 'XINITRC_EOF'
#!/bin/bash
# Screentaem Kiosk — Lightweight X11 Session

LOG="/home/kiosk/app/screentaem.log"
echo "[xinitrc] Session starting at $(date)" >> "$LOG"

# Start D-Bus session (needed for Electron powerSaveBlocker)
if command -v dbus-launch &>/dev/null; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Start PulseAudio
pulseaudio --start 2>/dev/null || true

# Disable screen blanking, DPMS, and screensaver
xset s off 2>/dev/null
xset s noblank 2>/dev/null
xset -dpms 2>/dev/null

# Set volume to maximum
amixer -q sset Master 100% unmute 2>/dev/null || true
amixer -q sset PCM 100% unmute 2>/dev/null || true
pactl set-sink-volume @DEFAULT_SINK@ 100% 2>/dev/null || true
pactl set-sink-mute @DEFAULT_SINK@ 0 2>/dev/null || true

# Start openbox (minimal window manager) in the background
openbox &
OPENBOX_PID=$!

# Wait a moment for the window manager to initialize
sleep 1

# Main loop: launch app
# Clean exit (code 0) → open terminal for debugging
# Crash (code != 0) → auto-restart
FAIL_COUNT=0
while true; do
    echo "[xinitrc] Launching app (attempt $((FAIL_COUNT + 1)))..." >> "$LOG"
    /home/kiosk/app/screentaem-launcher.sh
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        # Clean exit — drop to terminal for maintenance/debugging
        FAIL_COUNT=0
        echo "[xinitrc] App exited cleanly, opening terminal..." >> "$LOG"
        xterm -fullscreen -fa "Monospace" -fs 14 \
            -e bash -c 'echo "=== Screentaem Kiosk Shell ==="; echo "Type \"relaunch\" to restart the app, or \"reboot\" to reboot."; echo "Log: cat ~/app/screentaem.log"; echo ""; alias relaunch="exit 0"; exec bash' \
            2>/dev/null
        # When xterm closes, loop back and relaunch the app
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "[xinitrc] App crashed (exit=$EXIT_CODE, fails=$FAIL_COUNT)" >> "$LOG"

        # After 5 consecutive failures, try disabling GPU acceleration
        if [ $FAIL_COUNT -eq 5 ]; then
            echo "[xinitrc] Too many crashes, disabling GPU acceleration..." >> "$LOG"
            touch /home/kiosk/.disable-gpu
        fi

        # After 10 consecutive failures, wait longer to avoid CPU spin
        if [ $FAIL_COUNT -ge 10 ]; then
            echo "[xinitrc] Persistent failures, waiting 30s..." >> "$LOG"
            sleep 30
        else
            sleep 5
        fi
    fi
done
XINITRC_EOF
    chmod +x "$KIOSK_HOME/.xinitrc"

    # Openbox config: maximize all windows, no decorations
    cat > "$KIOSK_HOME/.config/openbox/rc.xml" << 'RCEOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc"
                xmlns:xi="http://www.w3.org/2001/XInclude">
  <resistance><strength>0</strength><screen_edge_strength>0</screen_edge_strength></resistance>
  <focus><followMouse>no</followMouse></focus>
  <desktops><number>1</number></desktops>
  <keyboard/>
  <mouse/>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
</openbox_config>
RCEOF

    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.bash_profile"
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.profile"
    chown "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.xinitrc"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"
fi

# =================================================================
#  Watchdog + final hardening (shared)
# =================================================================

progress $TOTAL "Enabling watchdog & final hardening..."

systemctl mask ctrl-alt-del.target >> "$LOG" 2>&1

if [ "$DISPLAY_MODE" = "gnome" ]; then
    WATCHDOG_TARGET="graphical.target"
else
    WATCHDOG_TARGET="multi-user.target"
fi

cat > /etc/systemd/system/kiosk-watchdog.service << WDEOF
[Unit]
Description=Screentaem Kiosk Crash Watchdog
After=$WATCHDOG_TARGET

[Service]
Type=simple
User=$KIOSK_USER
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$KIOSK_USER/.Xauthority
ExecStart=/bin/bash -c 'while true; do sleep 30; if [ -f /home/kiosk/.app-crashed ]; then rm -f /home/kiosk/.app-crashed; echo "[watchdog] Crash detected, restarting app..."; /home/kiosk/app/screentaem-launcher.sh; fi; done'
Restart=always
RestartSec=10

[Install]
WantedBy=$WATCHDOG_TARGET
WDEOF

systemctl daemon-reload >> "$LOG" 2>&1
systemctl enable kiosk-watchdog.service >> "$LOG" 2>&1

# Final progress — 100%
progress $TOTAL "Done!"
echo ""
echo ""
PROVISION_SCRIPT

  chmod +x "$TMP_PROVISION"
  local PROVISION_EXIT=0
  sudo bash "$TMP_PROVISION" "$APPIMAGE_FOR_PROVISION" "$DISPLAY_MODE" "$SSH_CHOICE" "$DEB_ARCH" || PROVISION_EXIT=$?

  rm -f "$TMP_PROVISION"

  if [ "$PROVISION_EXIT" -ne 0 ]; then
    error "Kiosk provisioning failed (exit code $PROVISION_EXIT)."
    exit 1
  fi
}

install_linux_kiosk() {
  step 1 "Downloading Screentaem AppImage..."
  local TMP_APPIMAGE="/tmp/screentaem-installer.AppImage"
  curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_APPIMAGE"
  chmod +x "$TMP_APPIMAGE"
  success "AppImage downloaded"

  step 2 "Running kiosk provisioning (requires sudo)..."
  run_kiosk_provision "$TMP_APPIMAGE"
  rm -f "$TMP_APPIMAGE"

  step 3 "Done!"
  success "Kiosk provisioning complete"
}

install_mac() {
  local TMP_DMG="/tmp/screentaem-installer.dmg"

  step 1 "Downloading Screentaem..."
  curl -fSL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DMG"
  success "DMG downloaded"

  step 2 "Installing to /Applications..."
  MOUNT_OUTPUT=$(hdiutil attach "$TMP_DMG" -nobrowse -quiet 2>&1)
  MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | tail -1 | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ *$//')

  if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    MOUNT_POINT=$(ls -d /Volumes/Screentaem* 2>/dev/null | head -1)
  fi

  if [ -z "$MOUNT_POINT" ]; then
    error "Failed to mount DMG"
    rm -f "$TMP_DMG"
    exit 1
  fi

  APP_BUNDLE=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
  if [ -z "$APP_BUNDLE" ]; then
    error "No .app bundle found in DMG"
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rm -f "$TMP_DMG"
    exit 1
  fi

  APP_NAME_INSTALLED=$(basename "$APP_BUNDLE")
  cp -R "$APP_BUNDLE" /Applications/
  success "Installed to ${BOLD}/Applications/${APP_NAME_INSTALLED}${NC}"

  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
  rm -f "$TMP_DMG"

  if [ "$AUTO_START" = "y" ]; then
    step 3 "Enabling auto-start..."
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${APP_NAME_INSTALLED}\", hidden:true}" 2>/dev/null || true
    success "Added to Login Items"
  fi
}

# ============================================================
#  PHASE 5: Done
# ============================================================

print_done_install() {
  echo ""
  echo -e "  ${BOLD}${GREEN}┌─────────────────────────────────────────┐${NC}"
  echo -e "  ${BOLD}${GREEN}│                                         │${NC}"
  echo -e "  ${BOLD}${GREEN}│     ✓ Installation Complete!             │${NC}"
  echo -e "  ${BOLD}${GREEN}│                                         │${NC}"
  echo -e "  ${BOLD}${GREEN}└─────────────────────────────────────────┘${NC}"
  echo ""

  if [ "$PLATFORM" = "linux" ]; then
    if [ "$KIOSK_MODE" = "y" ]; then
      if [ "$DISPLAY_MODE" = "gnome" ]; then
        info "On reboot: GDM3 auto-login → GNOME → Screentaem fullscreen"
        info "Clean exit: falls back to GNOME desktop (double-click icon to relaunch)"
        info "Crash: watchdog restarts within 30 seconds"
      else
        info "On reboot: tty1 auto-login → X11 + openbox → Screentaem fullscreen"
        info "Clean exit (via PIN): drops to a bash terminal for debugging"
        info "Crash: auto-restarts within 5 seconds"
        info "Debug log: /home/kiosk/app/screentaem.log"
      fi
      echo ""
      info "Network settings: Press Esc → enter PIN → Network Settings"
      echo ""

      # Auto-reboot countdown
      info "Rebooting in 10 seconds... (Ctrl+C to cancel)"
      for i in 10 9 8 7 6 5 4 3 2 1; do
        printf "\r  ${BOLD}    %2d...${NC}  " "$i"
        sleep 1
      done
      echo ""
      sudo reboot
    else
      info "Launch the app:"
      echo -e "     ${BOLD}${APPIMAGE_PATH} --kiosk${NC}"
      if [ "$AUTO_START" = "y" ]; then
        echo ""
        info "The app will auto-start on your next login."
      fi
    fi
  elif [ "$PLATFORM" = "mac" ]; then
    info "Launch the app:"
    echo -e "     ${BOLD}open '/Applications/${APP_NAME_INSTALLED}'${NC}"
    if [ "$AUTO_START" = "y" ]; then
      echo ""
      info "The app will auto-start on your next login."
    fi
  fi

  echo ""
  info "Once launched, a pairing code will appear on screen."
  info "Enter it at ${BOLD}https://app.screentaem.com${NC} to connect your display."
  echo ""
}

print_done_uninstall() {
  echo ""
  echo -e "  ${BOLD}${GREEN}┌─────────────────────────────────────────┐${NC}"
  echo -e "  ${BOLD}${GREEN}│                                         │${NC}"
  echo -e "  ${BOLD}${GREEN}│     ✓ Uninstall Complete!                │${NC}"
  echo -e "  ${BOLD}${GREEN}│                                         │${NC}"
  echo -e "  ${BOLD}${GREEN}└─────────────────────────────────────────┘${NC}"
  echo ""
  info "Screentaem has been removed from this system."
  if [ "$EXISTING_INSTALL" = "kiosk" ]; then
    info "You may want to reboot: ${BOLD}sudo reboot${NC}"
  fi
  echo ""
}

# ============================================================
#  Main
# ============================================================

print_banner
detect_platform

info "Detected ${BOLD}${PLATFORM}${NC} (${ARCH})"
echo ""

detect_existing_install
ask_questions

# Calculate total steps for outer progress
calc_install_steps() {
  if [ "$PLATFORM" = "linux" ]; then
    if [ "$KIOSK_MODE" = "y" ]; then
      TOTAL_STEPS=3
    elif [ "$AUTO_START" = "y" ]; then
      TOTAL_STEPS=3
    else
      TOTAL_STEPS=2
    fi
  elif [ "$PLATFORM" = "mac" ]; then
    if [ "$AUTO_START" = "y" ]; then
      TOTAL_STEPS=3
    else
      TOTAL_STEPS=2
    fi
  fi
}

if [ "$ACTION" = "uninstall" ]; then
  if [ "$EXISTING_INSTALL" = "kiosk" ]; then
    TOTAL_STEPS=3
  else
    TOTAL_STEPS=2
  fi
elif [ "$ACTION" = "repair" ]; then
  TOTAL_STEPS=2  # provisioning + done
else
  calc_install_steps
fi

print_summary

echo ""

# --- Execute ---

if [ "$ACTION" = "uninstall" ]; then
  # Uninstall only
  if [ "$EXISTING_INSTALL" = "kiosk" ]; then
    uninstall_linux_kiosk
  elif [ "$EXISTING_INSTALL" = "standard" ]; then
    uninstall_linux_standard
  elif [ "$EXISTING_INSTALL" = "mac" ]; then
    uninstall_mac
  fi
  print_done_uninstall
  exit 0

elif [ "$ACTION" = "reinstall" ]; then
  # Uninstall first
  if [ "$EXISTING_INSTALL" = "kiosk" ]; then
    uninstall_linux_kiosk
  elif [ "$EXISTING_INSTALL" = "standard" ]; then
    uninstall_linux_standard
  elif [ "$EXISTING_INSTALL" = "mac" ]; then
    uninstall_mac
  fi
  echo ""
  info "Uninstall complete. Starting fresh install..."
  echo ""
  calc_install_steps

elif [ "$ACTION" = "repair" ]; then
  # Repair: skip download, re-run provisioning with existing AppImage
  TOTAL_STEPS=2

  step 1 "Running kiosk repair (requires sudo)..."

  # Copy existing AppImage to tmp (kiosk home is chmod 700, can't read directly)
  TMP_APPIMAGE="/tmp/screentaem-repair.AppImage"
  sudo cp /home/kiosk/app/screentaem.AppImage "$TMP_APPIMAGE" 2>/dev/null || true
  sudo chmod +x "$TMP_APPIMAGE" 2>/dev/null || true

  run_kiosk_provision "$TMP_APPIMAGE"
  rm -f "$TMP_APPIMAGE"

  step 2 "Done!"
  success "Kiosk repair complete"
  print_done_install
  exit 0
fi

# Fresh install or reinstall (install phase)
if [ "$PLATFORM" = "linux" ]; then
  if [ "$KIOSK_MODE" = "y" ]; then
    install_linux_kiosk
  else
    install_linux_standard
  fi
elif [ "$PLATFORM" = "mac" ]; then
  install_mac
fi

print_done_install
