#!/usr/bin/env bash

set -Eeuo pipefail

if (( EUID == 0 )); then
  echo 'Run this installer as the regular Omarchy desktop user, not as root.' >&2
  exit 2
fi

BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
AUTOSTART_DIR="$HOME/.config/autostart"
BRIDGE="$BIN_DIR/parallels-hyprland-dynamic-resolution"
UNIT="$UNIT_DIR/parallels-dynamic-resolution.service"
PRLCC_UNIT="$UNIT_DIR/parallels-prlcc-x11.service"
PRLDND_UNIT="$UNIT_DIR/parallels-prldnd-wayland.service"
PRLCP_UNIT="$UNIT_DIR/parallels-prlcp-wayland.service"
PRLSHPROF_UNIT="$UNIT_DIR/parallels-prlshprof-wayland.service"
PRLCC_AUTOSTART="$AUTOSTART_DIR/prlcc.desktop"
STAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BIN_DIR" "$UNIT_DIR" "$AUTOSTART_DIR"

for file in \
  "$BRIDGE" \
  "$UNIT" \
  "$PRLCC_UNIT" \
  "$PRLDND_UNIT" \
  "$PRLCP_UNIT" \
  "$PRLSHPROF_UNIT" \
  "$PRLCC_AUTOSTART"; do
  if [[ -e $file ]]; then
    cp -p "$file" "$file.backup-$STAMP"
  fi
done

for tool in prlcc prldnd prlcp prlshprof; do
  if [[ ! -x /usr/bin/$tool ]]; then
    echo "Missing /usr/bin/$tool. Install Parallels Tools before running this installer." >&2
    exit 1
  fi
done

install -m 0755 /dev/stdin "$BRIDGE" <<'BRIDGE_SCRIPT'
#!/usr/bin/env bash

# Bridge the dynamic mode published by Parallels Tools to Hyprland.

OUTPUT="Virtual-1"
CONNECTOR="/sys/class/drm/card0-Virtual-1"
CONFIG_FILE="$HOME/.config/hypr/monitors.lua"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
SCALE_STATE="$STATE_DIR/parallels-monitor-scale"
SCALE_LOG="$STATE_DIR/monitor-scaling.log"
FALLBACK_MODE="1920x1080"
POLL_INTERVAL="0.25"
VERIFY_INTERVAL=5
XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export XDG_RUNTIME_DIR

find_hyprland_instance() {
  local socket dir

  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] &&
     [[ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ]]; then
    return 0
  fi

  HYPRLAND_INSTANCE_SIGNATURE=""
  for socket in "$XDG_RUNTIME_DIR"/hypr/*/.socket.sock; do
    [[ -S $socket ]] || continue
    dir=${socket%/.socket.sock}
    HYPRLAND_INSTANCE_SIGNATURE=${dir##*/}
    export HYPRLAND_INSTANCE_SIGNATURE
    return 0
  done

  return 1
}

desired_mode() {
  local mode width height

  mode=""
  if [[ -r "$CONNECTOR/modes" ]]; then
    IFS= read -r mode < "$CONNECTOR/modes" || true
  fi

  if [[ $mode =~ ^([0-9]{3,5})x([0-9]{3,5})$ ]]; then
    width=${BASH_REMATCH[1]}
    height=${BASH_REMATCH[2]}
    if (( width >= 800 && height >= 600 && width <= 8192 && height <= 8192 )); then
      printf '%s\n' "$mode"
      return 0
    fi
  fi

  printf '%s\n' "$FALLBACK_MODE"
}

current_state() {
  find_hyprland_instance || return 1
  hyprctl monitors all 2>/dev/null | awk -v output="$OUTPUT" '
    $1 == "Monitor" && $2 == output { found = 1; next }
    found && $1 == "Monitor" { exit }
    found && active_mode == "" && $1 ~ /^[0-9]+x[0-9]+@/ {
      split($1, mode, "@"); active_mode = mode[1]
    }
    found && $1 == "scale:" && active_mode != "" {
      print active_mode "|" $2; exit
    }
  '
}

valid_scale() {
  [[ ${1:-} =~ ^[0-9]+([.][0-9]+)?$ ]] &&
    awk -v scale="$1" 'BEGIN { exit !(scale >= 1 && scale <= 4) }'
}

normalize_scale() {
  awk -v scale="$1" 'BEGIN { printf "%g\n", scale }'
}

clean_scale() {
  local requested=$1 mode=$2 width height

  width=${mode%x*}
  height=${mode#*x}
  awk -v scale="$requested" -v width="$width" -v height="$height" '
    function gcd(a, b, t) { while (b) { t = a % b; a = b; b = t } return a }
    BEGIN {
      g = gcd(width * 120, height * 120)
      k = int(scale * 120 + 0.5)
      if (k > g) k = g
      while (g % k != 0) k++
      printf "%g\n", k / 120
    }'
}

logged_scale_preference() {
  [[ -r $SCALE_LOG ]] || return 1
  awk -F '\t' -v output="$OUTPUT" '
    {
      requested = new_scale = monitor = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^requested=/) { requested = $i; sub(/^requested=/, "", requested) }
        if ($i ~ /^new=/) { new_scale = $i; sub(/^new=/, "", new_scale) }
        if ($i ~ /^monitor=/) { monitor = $i; sub(/^monitor=/, "", monitor) }
      }
      if (monitor == output) {
        if (requested ~ /^[0-9]+([.][0-9]+)?$/) preference = requested
        else if (new_scale ~ /^[0-9]+([.][0-9]+)?$/) preference = new_scale
      }
    }
    END { if (preference != "") print preference; else exit 1 }
  ' "$SCALE_LOG"
}

load_scale_preference() {
  local scale=""

  if [[ -r $SCALE_STATE ]] && { [[ ! -e $SCALE_LOG ]] || [[ $SCALE_STATE -nt $SCALE_LOG ]]; }; then
    IFS= read -r scale < "$SCALE_STATE" || true
  elif [[ -r $SCALE_LOG ]]; then
    scale=$(logged_scale_preference || true)
  fi

  if ! valid_scale "$scale"; then
    scale=${1:-2}
  fi
  valid_scale "$scale" || scale=2
  normalize_scale "$scale"
}

save_scale_preference() {
  local scale=$1 tmp

  mkdir -p "$STATE_DIR"
  tmp=$(mktemp "$STATE_DIR/.parallels-monitor-scale.XXXXXX") || return 1
  printf '%s\n' "$(normalize_scale "$scale")" > "$tmp"
  mv -f "$tmp" "$SCALE_STATE"
}

scale_log_signature() {
  stat -c '%Y:%s' "$SCALE_LOG" 2>/dev/null || printf 'missing\n'
}

update_config() {
  local mode=$1 scale=$2 gdk_scale has_monitor_scale tmp

  [[ -r $CONFIG_FILE ]] || return 1
  scale=$(normalize_scale "$scale")
  gdk_scale=$(awk -v scale="$scale" 'BEGIN { printf "%d", int(scale + 0.5) }')
  if grep -q '^local omarchy_monitor_scale = ' "$CONFIG_FILE"; then
    has_monitor_scale=1
  else
    has_monitor_scale=0
  fi
  tmp=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX") || return 1

  if ! awk -v mode="${mode}@60" -v scale="$scale" -v gdk_scale="$gdk_scale" \
    -v has_monitor_scale="$has_monitor_scale" '
    /^local omarchy_gdk_scale = / {
      $0 = "local omarchy_gdk_scale = " gdk_scale
      updated_gdk_scale = 1
      print
      if (!has_monitor_scale) {
        print "local omarchy_monitor_scale = " scale
        updated_monitor_scale = 1
      }
      next
    }
    /^local omarchy_monitor_scale = / {
      $0 = "local omarchy_monitor_scale = " scale
      updated_monitor_scale = 1
    }
    /^hl\.monitor\(\{/ && !updated_monitor {
      if (!sub(/mode = "[^"]+"/, "mode = \"" mode "\"")) exit 3
      if (!sub(/scale = ("auto"|[0-9.]+|[A-Za-z_][A-Za-z0-9_]*)/, \
               "scale = omarchy_monitor_scale")) exit 4
      updated_monitor = 1
    }
    { print }
    END {
      if (!updated_gdk_scale || !updated_monitor_scale || !updated_monitor) exit 2
    }
  ' "$CONFIG_FILE" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  chmod --reference="$CONFIG_FILE" "$tmp"
  if cmp -s "$tmp" "$CONFIG_FILE"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$CONFIG_FILE"
  fi
}

apply_mode() {
  local mode=$1 scale=$2 state active_mode attempt

  update_config "$mode" "$scale" || return 1
  find_hyprland_instance || return 1
  hyprctl reload >/dev/null || return 1

  for attempt in {1..30}; do
    sleep 0.1
    state=$(current_state || true)
    active_mode=${state%%|*}
    [[ $active_mode == "$mode" ]] && return 0
  done

  return 1
}

last_candidate=""
last_applied=""
stable_reads=0
next_verify=0
initial_state=$(current_state || true)
initial_scale=${initial_state#*|}
[[ $initial_state == *'|'* ]] || initial_scale=2
preferred_scale=$(load_scale_preference "$initial_scale")
save_scale_preference "$preferred_scale"
last_log_signature=$(scale_log_signature)
last_observed_scale=$initial_scale
last_managed_scale=""

while true; do
  candidate=$(desired_mode)
  active=$(current_state || true)
  active_mode=${active%%|*}
  active_scale=${active#*|}
  [[ $active == *'|'* ]] || active_scale=""

  log_signature=$(scale_log_signature)
  log_changed=0
  if [[ $log_signature != "$last_log_signature" ]]; then
    last_log_signature=$log_signature
    logged_scale=$(logged_scale_preference || true)
    if valid_scale "$logged_scale"; then
      preferred_scale=$(normalize_scale "$logged_scale")
      save_scale_preference "$preferred_scale"
      log_changed=1
    fi
  fi

  if (( !log_changed )) && [[ $active_mode == "$candidate" ]] &&
    valid_scale "$active_scale" && [[ -n $last_observed_scale ]] &&
    [[ $active_scale != "$last_observed_scale" ]] &&
    [[ $active_scale != "$last_managed_scale" ]]; then
    preferred_scale=$(normalize_scale "$active_scale")
    save_scale_preference "$preferred_scale"
  fi
  valid_scale "$active_scale" && last_observed_scale=$active_scale

  if [[ $candidate != "$last_candidate" ]]; then
    last_candidate=$candidate
    stable_reads=0
  else
    (( stable_reads < 2 )) && (( stable_reads += 1 ))
  fi

  if (( stable_reads >= 2 )) &&
     { [[ $candidate != "$last_applied" ]] || (( SECONDS >= next_verify )); }; then
    if [[ $active_mode != "$candidate" || $candidate != "$last_applied" ]]; then
      scale=$(clean_scale "$preferred_scale" "$candidate")
      if apply_mode "$candidate" "$scale"; then
        applied_state=$(current_state || true)
        applied_scale=${applied_state#*|}
        [[ $applied_state == *'|'* ]] || applied_scale=$scale
        printf 'Applied Parallels resolution %s at scale %s to %s (user preference %s)\n' \
          "$candidate" "$applied_scale" "$OUTPUT" "$preferred_scale"
        last_managed_scale=$applied_scale
        last_observed_scale=$applied_scale
        last_applied=$candidate
      else
        printf 'Could not apply Parallels resolution %s; retrying\n' "$candidate" >&2
        sleep 1
      fi
    else last_applied=$candidate
    fi
    next_verify=$((SECONDS + VERIFY_INTERVAL))
  fi

  sleep "$POLL_INTERVAL"
done
BRIDGE_SCRIPT

install -m 0644 /dev/stdin "$UNIT" <<'SYSTEMD_UNIT'
[Unit]
Description=Apply Parallels dynamic resolution to Hyprland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/parallels-hyprland-dynamic-resolution
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
SYSTEMD_UNIT

# The stock Parallels Wayland dynamic-resolution backend assumes GNOME/Mutter.
# Disable its combined autostart entry and run only prlcc through XWayland.  The
# Wayland-native clipboard, drag-and-drop, and shared-profile helpers remain
# separate so their integrations are preserved.
install -m 0644 /dev/stdin "$PRLCC_AUTOSTART" <<'AUTOSTART_ENTRY'
[Desktop Entry]
Type=Application
Name=Parallels Control Center (managed for Hyprland)
Hidden=true
AUTOSTART_ENTRY

install -m 0644 /dev/stdin "$PRLCC_UNIT" <<'PRLCC_SYSTEMD_UNIT'
[Unit]
Description=Parallels Control Center dynamic resolution through XWayland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=DISPLAY=:0
Environment=XDG_SESSION_TYPE=x11
Environment=GDK_BACKEND=x11
UnsetEnvironment=WAYLAND_DISPLAY
ExecStart=/usr/bin/prlcc -r 100 -t 1000 -s 1
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
PRLCC_SYSTEMD_UNIT

install -m 0644 /dev/stdin "$PRLDND_UNIT" <<'PRLDND_SYSTEMD_UNIT'
[Unit]
Description=Parallels drag and drop for Wayland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=GDK_BACKEND=wayland
ExecStart=/usr/bin/prldnd
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
PRLDND_SYSTEMD_UNIT

install -m 0644 /dev/stdin "$PRLCP_UNIT" <<'PRLCP_SYSTEMD_UNIT'
[Unit]
Description=Parallels shared clipboard for Wayland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=GDK_BACKEND=wayland
ExecStart=/usr/bin/prlcp
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
PRLCP_SYSTEMD_UNIT

install -m 0644 /dev/stdin "$PRLSHPROF_UNIT" <<'PRLSHPROF_SYSTEMD_UNIT'
[Unit]
Description=Parallels shared profile for Wayland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=GDK_BACKEND=wayland
ExecStart=/usr/bin/prlshprof
Restart=on-failure
RestartSec=1

[Install]
WantedBy=graphical-session.target
PRLSHPROF_SYSTEMD_UNIT

bash -n "$BRIDGE"
systemd-analyze --user verify \
  "$UNIT" \
  "$PRLCC_UNIT" \
  "$PRLDND_UNIT" \
  "$PRLCP_UNIT" \
  "$PRLSHPROF_UNIT"
systemctl --user stop \
  app-prlcc@autostart.service \
  prlcc-x11-test.service \
  prlcc-x11-fast.service 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now \
  parallels-dynamic-resolution.service \
  parallels-prlcc-x11.service \
  parallels-prldnd-wayland.service \
  parallels-prlcp-wayland.service \
  parallels-prlshprof-wayland.service
systemctl --user restart \
  parallels-dynamic-resolution.service \
  parallels-prlcc-x11.service

echo
echo 'Dynamic resolution bridge installed.'
echo 'Resize the Parallels window, release the pointer, and allow about two seconds for the guest mode to follow.'
echo 'Check it with: systemctl --user status parallels-dynamic-resolution.service'
