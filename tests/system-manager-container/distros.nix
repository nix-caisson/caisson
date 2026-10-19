# SPDX-License-Identifier: MIT
#
# The root filesystems the system-manager container test runs in, by
# the name of the distribution and its version.
#
# The images of Ubuntu and Debian 13 are those of system-manager's
# container test driver. The others are the cloud images the
# distributions publish, pinned by URL and hash, unpacked into a root
# filesystem with the driver's `makeRootfs`. A cloud image is an
# installation of the distribution as it ships, with the systemd, the
# PAM configuration and the default services of the distribution, which
# is what the test runs against.
{ inputs, pkgs }:
let
  containerTest = inputs.system-manager.lib.containerTest;
  driverImages = containerTest.distros { inherit pkgs; };
  inherit ((containerTest.makeRootfs { inherit pkgs; })) buildRootfs;

  # The units that cannot run in a container, or that wait in one for
  # what it does not have, so that the boot never finishes:
  #
  # - cloud-init waits for the data source of a cloud;
  # - the first-boot wizard of systemd asks on the console for what a
  #   cloud would have provided;
  # - audit needs the audit of the kernel;
  # - systemd-networkd, systemd-resolved and the wait for the network of
  #   NetworkManager wait for a network the driver does not give;
  # - the NFS RPC pipe and the SELinux relabel need the kernel.
  #
  # `makeRootfs` applies a pattern as a `tar` exclusion to a qcow2 image
  # and as a shell glob under the root to a disk tarball, so each
  # pattern is a path from the root.
  units = [
    "systemd-firstboot.service"
    "auditd.service"
    "audit-rules.service"
    "systemd-networkd.service"
    "systemd-networkd.socket"
    "systemd-networkd-wait-online.service"
    "systemd-resolved.service"
    "NetworkManager-wait-online.service"
    "var-lib-nfs-rpc_pipefs.mount"
    "rpc_pipefs.target"
    "selinux-autorelabel-mark.service"
  ];
  excludePatterns = [
    "etc/systemd/system/network-online.target.wants/*"
    "etc/systemd/system/cloud-init.target.wants/*"
    "etc/systemd/system/multi-user.target.wants/cloud-*"
    "usr/lib/systemd/system/cloud-*"
    "usr/lib/systemd/system/systemd-remount-fs.service"
    "usr/lib/systemd/system/proc-sys-fs-binfmt_misc.automount"
    "usr/lib/systemd/system/sys-kernel-*"
    "usr/lib/systemd/system/tpm-udev.service"
  ]
  ++ builtins.concatMap (unit: [
    "usr/lib/systemd/system/${unit}"
    "usr/lib/systemd/system/*.wants/${unit}"
    "etc/systemd/system/*.wants/${unit}"
  ]) units;

  cloudImage =
    {
      name,
      url,
      hash,
      format,
    }:
    buildRootfs {
      inherit name excludePatterns;
      cloudImg = pkgs.fetchurl { inherit url hash; };
      cloudImgFormat = format;
    };
in
{
  ubuntu-22_04 = driverImages.ubuntu-22_04.rootfs;
  ubuntu-24_04 = driverImages.ubuntu-24_04.rootfs;
  ubuntu-26_04 = driverImages.ubuntu-26_04.rootfs;
  debian-13 = driverImages.debian-13.rootfs;

  debian-12 = cloudImage {
    name = "debian-12";
    url = "https://cloud.debian.org/images/cloud/bookworm/20261018-2635/debian-12-genericcloud-amd64-20261018-2635.tar.xz";
    hash = "sha256-Iy+sX6a2WqenvidBlmF7UZQ/DA2kloX/klmBNiEdD0s=";
    format = "disk-tarball";
  };

  fedora-43 = cloudImage {
    name = "fedora-43";
    url = "https://dl.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-43-1.6.x86_64.qcow2";
    hash = "sha256-hGV0yKl80tjcHyMQYtcxB8yFy7vaVjNeJkpG46bIqy8=";
    format = "qcow2";
  };

  fedora-44 = cloudImage {
    name = "fedora-44";
    url = "https://dl.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2";
    hash = "sha256-KGgP5bNxpaguv0OjGSbghqFo5ZlJ0DlpxQk+cHH5C38=";
    format = "qcow2";
  };

  rocky-9 = cloudImage {
    name = "rocky-9";
    url = "https://dl.rockylinux.org/vault/rocky/9.7/images/x86_64/Rocky-9-GenericCloud-Base-9.7-20251123.2.x86_64.qcow2";
    hash = "sha256-FdgdNDSymBQrL92PtUrvJmJoTbXAgswZHDx5di7WNgw=";
    format = "qcow2";
  };

  rocky-10 = cloudImage {
    name = "rocky-10";
    url = "https://dl.rockylinux.org/vault/rocky/10.1/images/x86_64/Rocky-10-GenericCloud-Base-10.1-20251116.0.x86_64.qcow2";
    hash = "sha256-KGKKvwihNMb54ezLysPyiYcVkZptopSuLGzWbWvDR60=";
    format = "qcow2";
  };

  arch = cloudImage {
    name = "arch";
    url = "https://geo.mirror.pkgbuild.com/images/v20261015.611680/Arch-Linux-x86_64-cloudimg-20261015.611680.qcow2";
    hash = "sha256-CHVOKNkbFoAIbGIR703xNVnnZv/3zbQAZImxS10oHwg=";
    format = "qcow2";
  };
}
