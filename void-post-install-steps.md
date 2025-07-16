# Void Linux Post-Install Steps

## Wayland + GDM Support

To get Wayland working properly with GDM, create a udev rule:

```bash
sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
```

---

## NVIDIA DRM Modeset (Optional for Newer Drivers)

Enable DRM modeset for NVIDIA:

1. Add the following to the `GRUB_CMDLINE_LINUX_DEFAULT` line in `/etc/default/grub`:

    ```
    nvidia_drm.modeset=1
    ```

2. Then run:

    ```bash
    sudo update-grub
    ```

---

## Blacklist Nouveau (Required for NVIDIA Driver)

Prevent the open-source `nouveau` driver from loading:

1. Create a blacklist config file:

    ```bash
    sudo nano /etc/modprobe.d/disable-nouveau.conf
    ```

2. Add the following lines:

    ```
    blacklist nouveau
    options nouveau modeset=0
    ```

3. Regenerate initramfs:

    ```bash
    sudo xbps-reconfigure -f linux$(uname -r)
    ```

4. Reboot:

    ```bash
    sudo reboot
    ```

---

## NVIDIA Driver Kernel Module Options (Enhanced)

Create a config file for NVIDIA driver tweaks:

```bash
sudo nano /etc/modprobe.d/nvidia.conf
```

Add the following lines:

```
options nvidia NVreg_InitializeSystemMemoryAllocations=0 NVreg_EnableResizableBar=1 NVreg_RegistryDwords="RMIntrLockingMode=1"
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
```

Then regenerate your initramfs:

```bash
sudo xbps-reconfigure -f linux$(uname -r)
```

And reboot:

```bash
sudo reboot
```

---

## Flatpak + Flathub

Enable Flatpak and add the Flathub repository:

```bash
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```

---

## Esync Compatibility (Game Performance)

### Modify `ulimits`:

Append this line to the bottom of `/etc/security/limits.conf`:

```
username_here hard nofile 524288
```

### Tweak `sysctl` values:

Create or edit `/etc/sysctl.d/80-gamecompatibility.conf` with:

```
vm.max_map_count=2147483642
vm.swappiness=10
```

---

## Fstab Optimization

Edit `/etc/fstab` and add `noatime` next to the `defaults` parameter (e.g., change `defaults` to `defaults,noatime`).

---

## Gamemode Setup

Install `gamemode`, then add your user to the `gamemode` group:

```bash
sudo usermod -aG gamemode username_here
```

