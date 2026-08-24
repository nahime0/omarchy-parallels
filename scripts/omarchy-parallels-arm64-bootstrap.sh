#!/bin/bash

set -Eeuo pipefail

LOG=/root/omarchy-vm-install.log
STATE=/root/omarchy-vm-install.state
WORK=/root/omarchy-vm-setup
FINGERPRINT=5983B1CA32CB778F4D74D24ECFF35022CA5B5959
STABLE=https://github.com/maralcbr/omarchy-mx-mac/releases/latest/download
CHANNEL=https://github.com/maralcbr/omarchy-pkgs/releases/download/asahi-quattro-channel
TARGET_USER=${OMARCHY_USER:-}
TARGET_FULL_NAME=${OMARCHY_FULL_NAME:-${OMARCHY_USER:-}}

if (( EUID != 0 )); then
  echo 'Run this installer as root.' >&2
  exit 2
fi

if [[ ! $TARGET_USER =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo 'Set OMARCHY_USER to an existing regular Linux username.' >&2
  exit 2
fi

if [[ -z $TARGET_FULL_NAME ]]; then
  echo 'Set OMARCHY_FULL_NAME to the user display name.' >&2
  exit 2
fi

exec > >(tee -a "$LOG") 2>&1

on_error() {
  local status=$?
  printf 'FAILED status=%s line=%s time=%s\n' "$status" "${BASH_LINENO[0]:-unknown}" "$(date -Is)" >"$STATE"
  echo
  echo '============================================================'
  echo "OMARCHY VM INSTALLATION FAILED (status $status)"
  echo "See $LOG"
  echo '============================================================'
  exit "$status"
}
trap on_error ERR

phase() {
  printf 'phase=%s time=%s\n' "$1" "$(date -Is)" >"$STATE"
  echo
  echo '============================================================'
  echo "OMARCHY VM: $1"
  echo '============================================================'
}

[[ $(uname -m) == aarch64 ]]
getent passwd "$TARGET_USER" >/dev/null

phase verify-signed-release
rm -rf "$WORK"
mkdir -p "$WORK/verified"
cd "$WORK"

curl --proto '=https' --tlsv1.2 --fail --location --retry 3 -o omarchy-release.gpg \
  "$STABLE/omarchy-release.gpg"
actual_fingerprint=$(gpg --batch --show-keys --with-colons omarchy-release.gpg |
  sed -n 's/^fpr:::::::::\([^:]*\):$/\1/p' | head -1)
[[ $actual_fingerprint == "$FINGERPRINT" ]]

curl --proto '=https' --tlsv1.2 --fail --location --retry 3 -o install-asahi-quattro \
  "$CHANNEL/install-asahi-quattro"
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 -o install-asahi-quattro.sig \
  "$CHANNEL/install-asahi-quattro.sig"
gpgv --keyring ./omarchy-release.gpg install-asahi-quattro.sig install-asahi-quattro

cp install-asahi-quattro install-asahi-quattro.vm
sed -i \
  -e '/^\[\[ -r \/proc\/device-tree\/compatible \]\] || fail /c\true # VM-only hardware boundary' \
  -e "/^grep -aq 'apple,' \/proc\/device-tree\/compatible || fail /c\\true # VM-only hardware boundary" \
  -e '/^required_packages=/,/^done$/d' \
  -e '/^for repository in /,/^done$/d' \
  -e "s#^trap 'rm -rf \"\$work_dir\"' EXIT#trap ':' EXIT#" \
  install-asahi-quattro.vm

TMPDIR="$WORK/verified" bash install-asahi-quattro.vm --fresh --user "$TARGET_USER" --verify-only
verified_dir=$(find "$WORK/verified" -mindepth 1 -maxdepth 1 -type d -name 'asahi-quattro.*' -print -quit)
[[ -n $verified_dir && -d $verified_dir/bundle ]]

release="$verified_dir/asahi-quattro-release"
release_sequence=$(sed -n 's/^sequence=//p' "$release")
release_tag=$(sed -n 's/^release_tag=//p' "$release")
source_commit=$(sed -n 's/^source_commit=//p' "$release")
package_source_commit=$(sed -n 's/^package_source_commit=//p' "$release")
[[ $release_sequence =~ ^[1-9][0-9]*$ ]]
[[ $release_tag =~ ^asahi-quattro-[0-9a-f]{8}$ ]]
[[ $source_commit =~ ^[0-9a-f]{40}$ ]]
[[ $package_source_commit =~ ^[0-9a-f]{40}$ ]]

install -d -m 0755 /var/lib/omarchy
install -m 0644 "$release" /var/lib/omarchy/vm-verified-release
printf '%s\n' "$actual_fingerprint" >/var/lib/omarchy/vm-release-key-fingerprint
sha256sum install-asahi-quattro install-asahi-quattro.vm \
  >/var/lib/omarchy/vm-adapter.sha256

phase prepare-arch
swapoff -a || true
if [[ -f /etc/fstab ]]; then
  sed -i '/[[:space:]]swap[[:space:]]/s/^/# omarchy-vm-disabled-swap /' /etc/fstab
fi
usermod --comment "$TARGET_FULL_NAME" "$TARGET_USER"
usermod -aG wheel "$TARGET_USER"
install -Dm440 /dev/stdin /etc/sudoers.d/10-omarchy-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF

omarchy_archive=$(find "$verified_dir/bundle" -maxdepth 1 -type f -name 'omarchy-dev-*.pkg.tar.*' ! -name '*.sig' -print -quit)
[[ -n $omarchy_archive ]]

mapfile -t runtime_packages < <(
  bsdtar -xOf "$omarchy_archive" usr/share/omarchy/install/omarchy-base-asahi.packages |
    sed 's/#.*//' |
    awk 'NF == 1 { print $1 }'
)

source_packages=(
  aether
  cliamp
  localsend
  mise
  python-terminaltexteffects
  ttf-ia-writer
  ufw-docker
  xdg-terminal-exec
  yaru-icon-theme
  yay
)
release_packages=(
  omarchy-keyring
  omarchy-settings-dev
  omarchy-dev
  omarchy-nvim
  quickshell-git
  ttf-jetbrains-mono-nerd-basic
)
vm_hardware_exclusions=(
  asahi-desktop-meta
  asahi-fwextract
  linux-asahi
  linux-asahi-headers
  m1n1
  widevine
)

repo_packages=()
for package in "${runtime_packages[@]}"; do
  [[ " ${source_packages[*]} " == *" $package "* ]] && continue
  [[ " ${release_packages[*]} " == *" $package "* ]] && continue
  [[ " ${vm_hardware_exclusions[*]} " == *" $package "* ]] && continue
  repo_packages+=("$package")
done

missing=()
for package in "${repo_packages[@]}"; do
  pacman -Si "$package" >/dev/null 2>&1 || missing+=("$package")
done
if ((${#missing[@]})); then
  echo "Unexpected packages missing from signed ARM repository set: ${missing[*]}"
  false
fi

phase install-repository-packages
pacman -Syu --needed --noconfirm base-devel sudo xdg-user-dirs "${repo_packages[@]}"

phase install-signed-omarchy-packages
archives=()
for package in "${release_packages[@]}"; do
  archive=$(find "$verified_dir/bundle" -maxdepth 1 -type f -name "$package-*.pkg.tar.*" ! -name '*.sig' -print -quit)
  [[ -n $archive ]]
  archives+=("$archive")
done
pacman -U --needed --noconfirm "${archives[@]}"

phase build-pinned-arm-packages
build_user=omarchy-vm-build
package_checkout=/var/cache/omarchy-vm-pkgbuilds
package_repo=$package_checkout/repo
build_sudoers=/etc/sudoers.d/09-omarchy-vm-build

cleanup_build() {
  rm -f "$build_sudoers"
  if getent passwd "$build_user" >/dev/null 2>&1; then
    userdel "$build_user" || true
  fi
  rm -rf "$package_checkout"
}
cleanup_build
trap 'cleanup_build; on_error' ERR

useradd --system --user-group --home-dir "$package_checkout" --shell /usr/bin/nologin "$build_user"
install -d -m 0711 "$package_checkout"
install -d -m 0700 -o "$build_user" -g "$build_user" "$package_repo"
runuser -u "$build_user" -- git clone --filter=blob:none --no-checkout \
  https://github.com/maralcbr/omarchy-pkgs.git "$package_repo"
runuser -u "$build_user" -- git -C "$package_repo" fetch origin --no-tags "$package_source_commit"
runuser -u "$build_user" -- git -C "$package_repo" reset --hard "$package_source_commit"
[[ $(runuser -u "$build_user" -- git -C "$package_repo" rev-parse HEAD) == "$package_source_commit" ]]

install -Dm440 /dev/stdin "$build_sudoers" <<EOF
$build_user ALL=(root) NOPASSWD: /usr/bin/pacman
EOF

for package in "${source_packages[@]}"; do
  pacman -Q "$package" >/dev/null 2>&1 && continue
  echo "Building pinned ARM package: $package"
  # $1 is intentionally expanded by the child bash process.
  # shellcheck disable=SC2016
  runuser -u "$build_user" -- env HOME="$package_repo" \
    bash -c 'cd "$1" && makepkg --syncdeps --noconfirm' \
    bash "$package_repo/pkgbuilds/$package"
  package_archives=()
  for candidate in "$package_repo/pkgbuilds/$package"/*.pkg.tar.*; do
    [[ -f $candidate && $candidate != *.sig ]] || continue
    metadata=$(bsdtar -xOf "$candidate" .PKGINFO 2>/dev/null || true)
    grep -Fxq "pkgname = $package" <<<"$metadata" && package_archives+=("$candidate")
  done
  ((${#package_archives[@]} == 1))
  pacman -U --needed --noconfirm "${package_archives[0]}"
done
cleanup_build
trap on_error ERR

phase configure-system
# This is an ARM VM, not Asahi hardware: keep the working Arch Linux ARM
# repository configuration, skip Snapper/Limine coupling, and let generic
# virtio hardware detection run.
config_all=/usr/share/omarchy/install/config/all.sh
post_pacman=/usr/share/omarchy/install/post-install/pacman.sh
cp --preserve=all "$config_all" "$WORK/config-all.original"
cp --preserve=all "$post_pacman" "$WORK/post-pacman.original"
sed -i 's/^if ! omarchy-hw-apple-silicon; then$/if false; then # VM keeps systemd-boot and Arch Linux ARM repos/' "$config_all"
sed -i 's/^if ! omarchy-hw-apple-silicon; then$/if false; then # VM keeps Arch Linux ARM pacman configuration/' "$post_pacman"

OMARCHY_PATH=/usr/share/omarchy \
  OMARCHY_INSTALL=/usr/share/omarchy/install \
  omarchy-apply-system --install-user "$TARGET_USER" --first-install

cp --preserve=all "$WORK/config-all.original" "$config_all"
cp --preserve=all "$WORK/post-pacman.original" "$post_pacman"

phase configure-user
target_home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
[[ -n $target_home && -d $target_home ]]
cp -af /etc/skel/. "$target_home/"
chown -R "$TARGET_USER:$TARGET_USER" "$target_home"
runuser -u "$TARGET_USER" -- env \
  HOME="$target_home" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
  OMARCHY_PATH=/usr/share/omarchy \
  OMARCHY_INSTALL=/usr/share/omarchy/install \
  OMARCHY_SETUP_CONTEXT=fresh-install \
  PATH='/usr/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/bin' \
  omarchy-provision-user --force --first-install

install -d -m 0755 -o sddm -g sddm /var/lib/sddm 2>/dev/null || install -d -m 0755 /var/lib/sddm
cat >/var/lib/sddm/state.conf <<EOF
[Last]
Session=omarchy.desktop
User=$TARGET_USER
EOF
chown sddm:sddm /var/lib/sddm /var/lib/sddm/state.conf 2>/dev/null || true

ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl set-default graphical.target

# Archboot's kmscon VT service can compete with SDDM for tty1 in the VM.
systemctl disable kmsconvt@tty1.service 2>/dev/null || true

# One boot without a password lets us verify the compositor. The cleanup unit
# removes both itself and the autologin setting, so later boots require login.
install -d -m 0755 /etc/sddm.conf.d
cat >/etc/sddm.conf.d/50-omarchy-firstboot-autologin.conf <<EOF
[Autologin]
User=$TARGET_USER
Session=omarchy
EOF
cat >/etc/systemd/system/omarchy-firstboot-autologin-cleanup.service <<'EOF'
[Unit]
Description=Remove one-time Omarchy VM autologin
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 120; rm -f /etc/sddm.conf.d/50-omarchy-firstboot-autologin.conf /etc/systemd/system/multi-user.target.wants/omarchy-firstboot-autologin-cleanup.service /etc/systemd/system/omarchy-firstboot-autologin-cleanup.service'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable omarchy-firstboot-autologin-cleanup.service

phase verify-installation
[[ $(</usr/share/omarchy/version) == 4.* ]]
[[ -f "$target_home/.local/state/omarchy/done/finalize-user" ]]
for unit in NetworkManager.service sddm.service systemd-resolved.service; do
  systemctl is-enabled --quiet "$unit"
done
pacman -Q omarchy-dev omarchy-settings-dev omarchy-nvim quickshell-git mise yay >/dev/null
pacman -Qkk omarchy-dev | grep -Fq '0 altered files'
[[ " $(id -nG "$TARGET_USER") " == *' wheel '* ]]
[[ " $(id -nG "$TARGET_USER") " == *' docker '* ]]

cat >"$STATE" <<EOF
complete=yes
version=$(</usr/share/omarchy/version)
release_tag=$release_tag
release_sequence=$release_sequence
source_commit=$source_commit
package_source_commit=$package_source_commit
user=$TARGET_USER
full_name=$TARGET_FULL_NAME
completed_at=$(date -Is)
EOF

echo
echo '============================================================'
echo "OMARCHY $(</usr/share/omarchy/version) INSTALLATION COMPLETE"
echo 'Rebooting into the graphical environment...'
echo '============================================================'
sleep 5
systemctl reboot
