#!/usr/bin/env bash
# XFCE + TigerVNC + noVNC (browser desktop), similar to Cursor Cloud Agent.
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

DESKTOP_USER="${SUDO_USER:-${DESKTOP_USER:-}}"
if [[ -z "$DESKTOP_USER" || "$DESKTOP_USER" == "root" ]]; then
  DESKTOP_USER="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')"
fi
if [[ -z "$DESKTOP_USER" ]]; then
  echo "Set desktop user: DESKTOP_USER=ubuntu sudo bash $0"
  exit 1
fi

DESKTOP_HOME="$(getent passwd "$DESKTOP_USER" | cut -d: -f6)"
NOVNC_PORT="${NOVNC_PORT:-6080}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
VNC_GEOM="${VNC_GEOM:-1920x1080}"
PUBLIC_IP="${PUBLIC_IP:-$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  xfce4 xfce4-goodies dbus-x11 \
  tigervnc-standalone-server tigervnc-common \
  novnc python3-websockify curl

install -d -o "$DESKTOP_USER" -g "$DESKTOP_USER" "$DESKTOP_HOME/.vnc"

cat >"$DESKTOP_HOME/.vnc/xstartup" <<'EOF'
#!/bin/bash
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
export GDK_SCALE=1 GDK_DPI_SCALE=1 QT_SCALE_FACTOR=1 XCURSOR_SIZE=24
export LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
exec /usr/bin/startxfce4
EOF
chmod +x "$DESKTOP_HOME/.vnc/xstartup"
chown -R "$DESKTOP_USER:$DESKTOP_USER" "$DESKTOP_HOME/.vnc"

if [[ -n "${VNC_PASSWORD:-}" ]]; then
  printf '%s\n%s\nn\n' "$VNC_PASSWORD" "$VNC_PASSWORD" | runuser -u "$DESKTOP_USER" -- vncpasswd
else
  echo "Set VNC password for user $DESKTOP_USER (min 6 chars):"
  runuser -u "$DESKTOP_USER" -- vncpasswd
fi

runuser -u "$DESKTOP_USER" -- vncserver -kill ":$VNC_DISPLAY" >/dev/null 2>&1 || true
runuser -u "$DESKTOP_USER" -- vncserver ":$VNC_DISPLAY" \
  -geometry "$VNC_GEOM" -depth 24 -localhost yes -dpi 96 \
  -desktop "VPS Desktop" -SecurityTypes VncAuth

cat >/etc/systemd/system/novnc.service <<EOF
[Unit]
Description=noVNC browser access to TigerVNC
After=network.target

[Service]
Type=simple
User=$DESKTOP_USER
Environment=HOME=$DESKTOP_HOME
ExecStart=/usr/bin/websockify --web=/usr/share/novnc ${NOVNC_PORT} localhost:$((5900 + VNC_DISPLAY))
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now novnc.service

echo ""
echo "=============================================="
echo " Desktop ready (XFCE + VNC + noVNC)"
echo "=============================================="
echo " User:      $DESKTOP_USER"
echo " Browser:   http://${PUBLIC_IP}:${NOVNC_PORT}/vnc.html"
echo "             (click Connect, enter VNC password)"
echo " VNC local: localhost:$((5900 + VNC_DISPLAY))  (only via noVNC/SSH)"
echo ""
echo " Open port if using firewall:"
echo "   ufw allow ${NOVNC_PORT}/tcp"
echo " Safer: ssh -L ${NOVNC_PORT}:127.0.0.1:${NOVNC_PORT} ${DESKTOP_USER}@${PUBLIC_IP}"
echo "        then open http://127.0.0.1:${NOVNC_PORT}/vnc.html"
echo "=============================================="
