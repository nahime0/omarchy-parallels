<p align="center">
  <img src="assets/omarchy-mark.png" alt="Omarchy logo" width="120">
</p>

<h1 align="center">Omarchy on Parallels</h1>

<p align="center">
  <em>A tested ARM64 path for running Omarchy on Apple Silicon Macs.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Apple_Silicon-ARM64-9ECE6A?style=flat-square&logo=apple&logoColor=white" alt="Apple Silicon ARM64">
  <img src="https://img.shields.io/badge/Parallels_Desktop-26.4.1-9ECE6A?style=flat-square&logo=parallels&logoColor=white" alt="Parallels Desktop 26.4.1">
  <img src="https://img.shields.io/badge/Omarchy_MX_Mac-4.0.0--mac.11-9ECE6A?style=flat-square&logo=archlinux&logoColor=white" alt="Omarchy MX Mac 4.0.0-mac.11">
  <img src="https://img.shields.io/badge/Hyprland-0.56.1-9ECE6A?style=flat-square&logo=hyprland&logoColor=white" alt="Hyprland 0.56.1">
</p>

<p align="center">
  <strong>Native ARM64 &middot; Signed release verification &middot; Parallels Tools &middot; Dynamic resolution</strong>
</p>

<p align="center">
  A reproducible guide and two companion scripts for installing Omarchy in a Parallels VM on Apple Silicon while preserving the Arch Linux ARM kernel, systemd-boot, and virtio hardware support.
</p>

---

> [!TIP]
> **Preconfigured template:** [Download it from Google Drive](https://drive.google.com/file/d/15PJMQ7fadooj_Hgonk4FX7B-34qD5GAO/view?usp=drive_link).
>
> - Username: `omarchy`
> - Password: `omarchy`
> - Root password: `omarchy`

## Read this first

This is a tested VM adaptation, not an officially supported Omarchy installation path.

- The official Omarchy ISO is x86_64 and cannot be virtualized natively on an Apple Silicon Mac.
- This guide installs Arch Linux ARM (`aarch64`) first, then adapts the signed Omarchy MX Mac release to generic Parallels/virtio hardware.
- Omarchy MX Mac explicitly targets Asahi Linux and states that it is not intended for Parallels or non-Asahi ARM systems. The companion bootstrap keeps Arch Linux ARM's kernel, repositories, systemd-boot, and virtio hardware support instead of installing the Asahi hardware stack.
- Create snapshots at the checkpoints below. Take another snapshot before every future Omarchy upgrade.

The procedure documented here produced a working Hyprland desktop with accelerated virtio graphics, an automatic graphical login screen, SSH, active Parallels Tools services, mounted SmartMount shares, and dynamic window resolution.

## Tested configuration

| Component | Tested value |
|---|---|
| Host | Apple Silicon Mac |
| Hypervisor | Parallels Desktop 26.4.1 (57516) |
| Guest architecture | `aarch64` / ARM64 |
| Parallels OS profile | Manjaro Linux |
| Firmware | EFI ARM64, Secure Boot disabled |
| CPU | 4 virtual CPUs |
| Memory | 8 GB |
| Disk | 64 GB expanding SATA disk |
| Graphics | virtio, highest 3D acceleration |
| Network | Shared network, virtio adapter |
| Base system | Arch Linux ARM installed with Archboot |
| Root filesystem | Btrfs |
| Bootloader | systemd-boot |
| Omarchy | Omarchy MX Mac 4.0.0-mac.11, signed bundle sequence 15 |
| Desktop | Hyprland 0.56.1 |

## Files supplied with this guide

When this guide asks you to copy a bundled script, run that command from the repository root. The relevant files are:

- [`README.md`](README.md) — this guide.
- [`scripts/omarchy-parallels-arm64-bootstrap.sh`](scripts/omarchy-parallels-arm64-bootstrap.sh) — installs the signed ARM64 Omarchy bundle on a prepared Arch Linux ARM VM.
- [`scripts/install-parallels-hyprland-dynamic-resolution.sh`](scripts/install-parallels-hyprland-dynamic-resolution.sh) — adds the Hyprland bridge needed for Parallels dynamic resolution.

The scripts contain no usernames, passwords, email addresses, or other personal credentials.

## 1. Download and verify Archboot ARM64

Open the [latest Archboot AArch64 ISO directory](https://release.archboot.com/aarch64/latest/iso/). Download:

1. The medium AArch64 image whose name ends in `-aarch64-ARCH-aarch64.iso`.
2. The matching `.iso.sig` file.

The medium image was approximately 473 MB in the tested installation. The smaller `latest` image downloads more packages during setup; the larger `local` image includes more packages. The medium image is a practical default.

Archboot ISOs are signed by Tobias Powalowski. His current fingerprint is published on the [Arch Linux developer page](https://archlinux.org/people/developers/):

```text
5B7E3FB71B7F10329A1C03AB771DF6627EDF681F
```

On macOS, with GnuPG installed, verify the download:

```bash
cd ~/Downloads
gpg --keyserver hkps://keyserver.ubuntu.com \
  --recv-keys 5B7E3FB71B7F10329A1C03AB771DF6627EDF681F
gpg --fingerprint 5B7E3FB71B7F10329A1C03AB771DF6627EDF681F
gpg --verify archboot-*.iso.sig archboot-*.iso
```

Do not continue unless the full fingerprint matches and `gpg` reports a good signature.

## 2. Create the Parallels VM

1. Open Parallels Desktop and choose **File → New**.
2. Select **Install Windows or another OS from a DVD or image file**.
3. Select the downloaded Archboot AArch64 ISO.
4. If Parallels asks for the operating-system type, select **Manjaro Linux**. This is the profile used by the tested VM.
5. Enable **Customize settings before installation**.
6. Set the VM name, for example `Omarchy`.
7. Set the VM location. To keep it on an external drive, select a folder on that volume before completing the wizard. The tested VM was stored as a `.pvm` bundle on an external APFS volume.
8. Configure:
   - 4 CPUs
   - 8 GB RAM
   - 64 GB expanding disk
   - Shared networking
   - Highest available 3D acceleration
   - EFI ARM64
   - Secure Boot off
9. Start the VM.

Parallels may initially identify the ISO as an unknown Linux distribution. That is acceptable as long as the VM uses the ARM64 firmware and hardware profile.

## 3. Install the Arch Linux ARM base

Use Archboot's interactive installer. Its current documentation is available on the [Archboot website](https://archboot.com/).

Recommended selections:

1. Configure networking with DHCP.
2. Select `/dev/sda` as the installation disk.
3. Use GPT partitioning.
4. Use a 512 MB FAT32 EFI System Partition mounted at `/boot`.
5. Use Btrfs for the remaining root filesystem.
6. A small swap partition is optional. The tested layout contained 256 MB of swap, but the Omarchy VM bootstrap disables it.
7. Select the `linux-aarch64` kernel.
8. Choose the systemd-based initramfs when prompted.
9. Choose **systemd-boot** as the bootloader.
10. Set the hostname, locale, timezone, root password, and a regular user.

The tested final partition layout was:

```text
sda1     2 MB   BIOS_GRUB
sda2   512 MB   FAT32 / EFI System Partition, mounted at /boot
sda3   256 MB   swap
sda4    rest    Btrfs, mounted at /
```

The root filesystem used a Btrfs subvolume named `root`. The small `BIOS_GRUB` partition was created by the guided partitioner and is not used by EFI systemd-boot.

When Archboot finishes:

1. Shut down or reboot the VM.
2. Disconnect the Archboot ISO from the virtual CD/DVD drive.
3. Confirm that the VM boots from its virtual disk into Arch Linux ARM.

## 4. Prepare Arch and enable SSH

Log in as `root` and update the base system:

```bash
pacman -Syu --needed \
  curl gnupg git base-devel sudo openssh xdg-user-dirs
systemctl enable --now sshd
```

If you did not create a regular user during Archboot, create one now. Replace `youruser` with a lowercase Linux username:

```bash
useradd -m -G wheel -s /bin/bash youruser
passwd youruser
```

Confirm the VM's IP address:

```bash
ip -br address
```

From macOS, test the connection:

```bash
ssh youruser@VM_IP_ADDRESS
```

### Snapshot checkpoint 1

Shut down the VM and create a Parallels snapshot named something like **Clean Arch ARM base**. Start the VM again before continuing.

## 5. Copy and run the Omarchy VM bootstrap

The companion bootstrap does the following:

- verifies that the guest is `aarch64`;
- verifies the Omarchy release key fingerprint;
- verifies the signed installer, release descriptor, manifest, package signatures, checksums, and pinned source commits;
- excludes Asahi-only kernel and hardware packages;
- preserves Arch Linux ARM repositories and systemd-boot;
- builds the ARM packages that are unavailable from the binary repositories;
- installs and provisions Omarchy for the selected regular user;
- enables SDDM and the graphical boot target;
- disables Archboot's leftover `kmsconvt@tty1.service`, which otherwise competes with SDDM;
- reboots after successful verification.

From the repository root on the Mac, copy it to the guest:

```bash
scp scripts/omarchy-parallels-arm64-bootstrap.sh \
  youruser@VM_IP_ADDRESS:/tmp/
```

Connect to the VM, become root, and install the script:

```bash
ssh youruser@VM_IP_ADDRESS
su -
install -m 0700 /tmp/omarchy-parallels-arm64-bootstrap.sh \
  /root/omarchy-parallels-arm64-bootstrap.sh
```

Run it with the existing regular username and display name:

```bash
OMARCHY_USER=youruser \
OMARCHY_FULL_NAME="Your Full Name" \
  bash /root/omarchy-parallels-arm64-bootstrap.sh
```

The installation downloads roughly 1 GB of repository packages and builds several pinned ARM packages locally. Do not interrupt package transactions. Progress and failure details are written to:

```text
/root/omarchy-vm-install.log
/root/omarchy-vm-install.state
```

The VM reboots automatically after all verification checks pass.

### Important trust boundary

The upstream Omarchy MX Mac project signs an Asahi-targeted release. The adapter verifies those signed artifacts first, then locally changes only the Asahi hardware eligibility, repository, bootloader, and package-selection steps required for a generic ARM VM. The resulting VM is therefore not an upstream-supported configuration, even though the installed release packages and pinned source inputs are verified.

The companion script currently follows the latest signed Quattro channel. It was validated with release `4.0.0-mac.11`, sequence `15`, source commit `dec29fa90afc3d16a7e0c487c1869c7e512282ca`. If upstream changes the installer structure, review the script before retrying rather than bypassing a failed check.

## 6. Verify the Omarchy desktop

After the reboot, the SDDM login screen should appear. Sign in with the regular user created earlier.

From a terminal, verify:

```bash
uname -m
cat /usr/share/omarchy/version
systemctl is-enabled sddm
systemctl is-active sddm
systemctl get-default
test -f ~/.local/state/omarchy/done/finalize-user && echo 'user setup complete'
```

Expected essentials:

```text
aarch64
4.0.0-mac.11        # or a later tested signed release
enabled
active
graphical.target
user setup complete
```

If the VM remains on a text console or SDDM immediately stops, run:

```bash
sudo systemctl disable --now kmsconvt@tty1.service
sudo systemctl restart sddm
```

This fixes the Archboot virtual-console service competing with the graphical login manager on `tty1`.

## 7. Install Parallels Tools

### Snapshot checkpoint 2

Create a snapshot named **Omarchy before Parallels Tools**.

With the VM running, choose **Actions → Install Parallels Tools** in Parallels Desktop. The ARM64 Tools ISO should be attached and mounted automatically.

Find the installer:

```bash
find "/run/media/$USER" -maxdepth 2 -name install -print
```

Run it:

```bash
sudo "/run/media/$USER/Parallels Tools/install"
```

If the ISO is not mounted automatically:

```bash
sudo mkdir -p /mnt/prltools
sudo mount /dev/sr0 /mnt/prltools
sudo /mnt/prltools/install
```

Allow the installer to add its required packages. Reboot after it reports success:

```bash
sudo reboot
```

Verify after reboot:

```bash
systemctl is-enabled prltoolsd
systemctl is-active prltoolsd
```

On the Mac, the following should report `GuestTools: state=installed`:

```bash
prlctl list -i "Omarchy" | grep GuestTools
```

The tested installation used Parallels Tools `26.4.1-57516`. Parallels documents the expected Linux integrations, including dynamic resolution, in its [Parallels Tools overview](https://docs.parallels.com/landing/pdfm-ug/v26-en-us/parallels-desktop-for-mac-26-users-guide/advanced-topics/installing-and-updating-parallels-tools/parallels-tools-overview).

## 8. Enable dynamic resolution under Hyprland

Parallels Tools receives window resize requests under Wayland, but its Linux agent attempts to apply them through GNOME's `org.gnome.Mutter.DisplayConfig` interface. Hyprland does not provide that GNOME interface. The observable failure in `/var/log/parallels.log` is:

```text
Dynamic Resolution: ---->> NEW DYN RES: WIDTHxHEIGHTx0
Error: Dynamic Resolution: can not read heads config from GNOME
```

When the native Wayland agent fails, it also omits the display-configuration confirmation expected by the host. Parallels then suppresses later resize requests until an approximately 60-second timeout expires, which makes resizing appear intermittent.

The supplied installer addresses both layers:

- its bridge reads the first mode published by the Parallels virtio display, atomically updates only the mode in the active monitor rule in `~/.config/hypr/monitors.lua`, reloads Hyprland, and verifies that the compositor actually switched to the requested mode;
- it runs the Parallels Control Center's dynamic-resolution component through XWayland with a one-second confirmation timeout, bypassing the unsupported GNOME-only Wayland path;
- it runs the Parallels clipboard, drag-and-drop, and shared-profile helpers separately as native Wayland services.

The bridge does not impose a display scale. It preserves scale changes made with Omarchy's monitor panel or `omarchy-hyprland-monitor-scaling`, records the user's preference in `~/.local/state/omarchy/parallels-monitor-scale`, and carries that preference across later window resizes. Hyprland accepts only scales that produce whole logical pixels; when necessary, the bridge applies the nearest valid scale using the same calculation as Omarchy, while retaining the original preference for a later compatible resolution.

From the repository root on macOS, copy the installer to the guest:

```bash
scp scripts/install-parallels-hyprland-dynamic-resolution.sh \
  youruser@VM_IP_ADDRESS:/tmp/
```

Run it as the regular desktop user, not as root:

```bash
install -m 0700 /tmp/install-parallels-hyprland-dynamic-resolution.sh \
  ~/.local/bin/install-parallels-hyprland-dynamic-resolution
~/.local/bin/install-parallels-hyprland-dynamic-resolution
```

The services start with the graphical session and the bridge uses `1920x1080` only as a fallback. In Parallels, leave **View > Retina Resolution > More Space** selected for native Retina rendering. Parallels coalesces intermediate sizes while the window edge is being dragged; release the pointer and allow approximately two seconds for the final size to be applied.

Verify:

```bash
systemctl --user is-enabled parallels-dynamic-resolution.service
systemctl --user is-active parallels-dynamic-resolution.service
systemctl --user is-active parallels-prlcc-x11.service
systemctl --user is-active parallels-prldnd-wayland.service
systemctl --user is-active parallels-prlcp-wayland.service
systemctl --user is-active parallels-prlshprof-wayland.service
systemctl --user status parallels-dynamic-resolution.service
hyprctl monitors all
```

The installer keeps timestamped backups when it replaces an earlier bridge or service unit. The bridge preserves the rest of `monitors.lua`, keeps Omarchy's user-editable monitor-scale variable, and changes only the GDK scale plus mode in the first active `hl.monitor(...)` rule. Hyprland's monitor syntax is documented in the [Hyprland monitor guide](https://wiki.hypr.land/Configuring/Basics/Monitors/).

## 9. SSH quality-of-life and firewall behavior

Omarchy enables UFW and rate-limits SSH. Several new SSH connections in rapid succession can temporarily produce `Connection refused`. Wait roughly 30 seconds rather than weakening the firewall.

For repeated administration from the Mac, install your key and use one persistent connection:

```bash
ssh-copy-id youruser@VM_IP_ADDRESS

ssh -M -S /tmp/omarchy-ssh -fnNT \
  -o ControlPersist=10m youruser@VM_IP_ADDRESS

ssh -S /tmp/omarchy-ssh youruser@VM_IP_ADDRESS
```

Close the persistent connection when finished:

```bash
ssh -S /tmp/omarchy-ssh -O exit youruser@VM_IP_ADDRESS
```

## 10. Troubleshooting reference

### The desktop returns to 1024×768

Confirm that Parallels Tools and the dynamic-resolution service are active:

```bash
systemctl is-active prltoolsd
systemctl --user is-active parallels-dynamic-resolution.service
sed -n '1p' /sys/class/drm/card0-Virtual-1/modes
hyprctl monitors all
```

Restart only the user bridge if necessary:

```bash
systemctl --user restart \
  parallels-prlcc-x11.service \
  parallels-dynamic-resolution.service
```

### Parallels reports a new size, but Hyprland does not change

Compare the Parallels request, DRM mode, and active Hyprland mode:

```bash
tail -n 100 /var/log/parallels.log | grep 'NEW DYN RES' | tail -n 1
sed -n '1p' /sys/class/drm/card0-Virtual-1/modes
hyprctl monitors all
```

The DRM mode may be rounded by a few pixels. For example, a Parallels request for `1276x1356` can become an available virtio mode of `1272x1356`; the bridge applies the valid mode.

### Parallels Tools ISO is still connected

After a successful installation and reboot, eject/disconnect the Tools ISO in Parallels. Leaving it mounted is normally harmless, but it should not remain ahead of the disk in the active boot path.

### Installation failed before reboot

Do not blindly rerun or reboot during a package transaction. Inspect:

```bash
less /root/omarchy-vm-install.log
cat /root/omarchy-vm-install.state
less /var/log/pacman.log
```

Restore **Clean Arch ARM base** if the package database or system configuration is left in an uncertain state.

### Useful logs

```text
/root/omarchy-vm-install.log       VM adapter and signed bundle installation
/var/log/omarchy-install.log       Omarchy system setup
/var/log/pacman.log                Package transactions
/var/log/parallels-tools-install.log
/var/log/parallels.log             Parallels guest agent and dynamic resolution
```

## 11. Updates and snapshots

Because the upstream fork does not support Parallels:

1. Create a snapshot before `omarchy update` or a full `pacman -Syu`.
2. Read the Omarchy MX Mac release notes for changes to the kernel, bootloader, package manifest, or Asahi hardware checks.
3. Confirm that `linux-aarch64`, systemd-boot, NetworkManager, SDDM, and Parallels Tools remain installed after an update.
4. Verify a real reboot before deleting the snapshot.

Recommended post-update checks:

```bash
uname -m
pacman -Q linux-aarch64 omarchy-dev omarchy-settings-dev hyprland
systemctl is-active NetworkManager sddm prltoolsd
systemctl --user is-active \
  parallels-dynamic-resolution.service \
  parallels-prlcc-x11.service \
  parallels-prldnd-wayland.service \
  parallels-prlcp-wayland.service \
  parallels-prlshprof-wayland.service
cat /usr/share/omarchy/version
```

## Sources

- [Archboot](https://archboot.com/)
- [Latest Archboot AArch64 ISO directory](https://release.archboot.com/aarch64/latest/iso/)
- [Arch Linux developer key directory](https://archlinux.org/people/developers/)
- [Omarchy MX Mac](https://github.com/maralcbr/omarchy-mx-mac)
- [Omarchy MX Mac 4.0.0-mac.11 release](https://github.com/maralcbr/omarchy-mx-mac/releases/tag/v4.0.0-mac.11)
- [Omarchy ARM64 package repository documentation](https://github.com/omacom-io/omarchy-pkgs/blob/master/README.md)
- [Parallels Tools overview](https://docs.parallels.com/landing/pdfm-ug/v26-en-us/parallels-desktop-for-mac-26-users-guide/advanced-topics/installing-and-updating-parallels-tools/parallels-tools-overview)
- [Hyprland monitor configuration](https://wiki.hypr.land/Configuring/Basics/Monitors/)
- [Community discussion: Installing Omarchy in a VM on an Apple Silicon Mac](https://github.com/basecamp/omarchy/discussions/452)

---

This guide records a configuration that was installed and verified in a real Parallels ARM64 VM. It should be treated as a reproducible experimental path, not as an upstream support commitment.
