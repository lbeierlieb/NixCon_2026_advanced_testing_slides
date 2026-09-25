---
theme: default
title: 'Advanced NixOS Integration Test Scenarios'
info: |
  ## Advanced NixOS Integration Test Scenarios
  USB Passthrough, Xen, and FDO — NixCon 2026
drawings:
  persist: false
transition: slide-left
mdc: true
layout: cover
---

# Advanced NixOS Integration Test Scenarios

USB Passthrough, Xen, and FDO

---

## `$ whoami`

- Lukas Beierlieb
- Software Engineer at Cyberus Technology
  - Virtualization
  - Nix
  - Rust
- PhD Student at University of Würzburg
  - Xen hypercall interface
  - Virtual machine introspection

<!--
today's testing examples are real use cases from work and research
-->

---

## NixOS Integration Tests

- One or multiple virtual machines
- Python script controlling the VMs

```nix
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.testers.nixosTest {
  name = "minimal-test";

  nodes.machine = {
    services.gitea.enable = true;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("gitea.service")
    machine.wait_for_open_port(3000)
    machine.succeed("curl localhost:3000")
  '';
}
```

<!--
machine.start() is optional
-->

---


## NixOS Integration Tests: Multiple VMs

```nix
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.testers.nixosTest {
  name = "server-client-test";

  nodes = {
    server = {
      services.gitea.enable = true;
      networking.firewall.allowedTCPPorts = [ 3000 ];
    };

    client = { };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("gitea.service")
    server.wait_for_open_port(3000)
    client.succeed("curl server:3000")
  '';
}
```

---
layout: section
---

## Example 1: Integration Tests of usbvfiod

---
class: compact
---

## <a href="https://github.com/cyberus-technology/usbvfiod">github:cyberus-technology/usbvfiod</a>

<img src="/img/usbvfiod_repo.png" class="mx-auto max-h-115" />

---

## usbvfiod

<img src="/diagrams/usbvfiod-basic.svg" class="mx-auto max-h-85" />

---

## usbvfiod Context: USB Passthrough with QEMU

- QEMU has a builtin USB-controller emulation
- QEMU can emulate connected USB devices
- The controller emulation can passthrough real USB devices

<img src="/diagrams/qemu-usb-native.svg" class="mx-auto max-h-70" />

---

## usbvfiod Context: cloud-hypervisor and USB devices

- cloud-hypervisor targets VMs running cloud workloads
  - virtio devices for network, storage, ...
  - no video output
  - no USB controller
- Missing features are a feature
  - smaller code base
  - device-emulation code is attack surface

---

## usbvfiod Context: cloud-hypervisor Outside The Cloud

- Security benefits of cloud-hypervisor's design also intrigue fields outside the cloud

<figure class="mx-auto text-center">
  <img src="/img/secunet_edge.png" class="mx-auto max-h-70" />
  <figcaption class="text-sm text-gray-500 mt-1">
    Source: <a href="https://www.secunet.com/loesungen/secunet-edge">secunet.com/loesungen/secunet-edge</a>
  </figcaption>
</figure>

---

## usbvfiod Context: cloud-hypervisor Inside secunet edge

- Workloads might require USB devices
  - Serial/FTDI connection to sensors
  - Webcam
  - Passport scanner
- PCI Passthrough of USB controller possible, but not ideal

---

## USB Passthrough for cloud-hypervisor with usbvfiod

<img src="/diagrams/usbvfiod-chv.svg" class="mx-auto max-h-85" />

---

## usbvfiod Integration Tests

- Goal: Check that a cloud-hypervisor guest can properly use USB device that usbvfiod passes through
- How can a NixOS integration test execute this scenario?
- We have a lot to cover

---

## Prerequisite: Nested Virtualization

```bash
$ cat /sys/module/kvm_amd/parameters/nested
1
```

---

## cloud-hypervisor Guest

- cloud-hypervisor supports direct kernel boot and raw/qcow image booting (needs additional firmware)
- Simplest solution: direct kernel boot of a netboot "image"

```nix
# nixosSystem for cloud-hypervisor guest
{ modulesPath, ... }:
{
  imports = [
    "${modulesPath}/installer/netboot/netboot-minimal.nix"
  ];
  config = {
    # system configuration goes here
  };
}
```

---

## cloud-hypervisor Guest

```nix
{
  pkgs,
  guest-config,
}:
let
  config = guest-config.config;
  kernel = "${config.system.build.kernel}/${pkgs.linux.target}";
  initrd = "${config.system.build.netbootRamdisk}/initrd";
  cmdline = "init=${config.system.build.toplevel}/init " + builtins.toString config.boot.kernelParams;
in
{
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    ExecStart = ''
      ${pkgs.lib.getExe pkgs.cloud-hypervisor} --memory size=2G \
        --kernel ${kernel} \
        --initramfs ${initrd} \
        --cmdline ${pkgs.lib.escapeShellArg cmdline}
    '';
  };
}
```

---

## cloud-hypervisor Guest

<img src="/diagrams/nested-chv-1-boot.svg" class="mx-auto max-h-85" />

---

## cloud-hypervisor Guest: Test Script Access

- How does the test script execute commands in VMs?
- We'll cover in the second example in detail.
- We use SSH

<img src="/diagrams/nested-chv-2-ssh.svg" class="mx-auto max-h-70" />

---

## cloud-hypervisor Guest: Test Script Access

- The test script can run commands
```python
(status, out) = vm_host.execute(
    "ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "
    "root@192.168.100.2 '" + command + "'"
)
```
- and with the right Python abstractions
```python
vm_host.succeed("whoami")
cloud_hypervisor.wait_until_succeeds("sfdisk -l | grep /dev/sda")
cloud_hypervisor.succeed("echo ',,L' | sfdisk --label=gpt /dev/sda")
cloud_hypervisor.succeed("mkfs.ext4 /dev/sda1")
```

---

## cloud-hypervisor with usbvfiod USB Controller

- Run usbvfiod as a service in the QEMU VM
- Run cloud-hypervisor service afterwards, with access to usbvfiod's socket

<img src="/diagrams/nested-chv-3-usbvfiod.svg" class="mx-auto max-h-70" />

---

## USB Devices in NixOS Tests

- QEMU can provide emulated USB devices
- We can modify QEMU parameters in the configuration of `vm_host`

```nix
{
  virtualisation.qemu.options = [
    "-device qemu-xhci,id=xhci,addr=10"
    "-drive if=none,id=xhci-testdevice,format=raw,file=/tmp/image-blockdevice-usb-3-testdevice.img -device usb-storage,bus=xhci.0,port=1,drive=xhci-testdevice"
  ];
}
```

---

## The Whole Integration-Test Setup for usbvfiod

<img src="/diagrams/nested-chv-4-full.svg" class="mx-auto max-h-85" />

---

## usbvfiod Test Scenarios

- Full-speed, high-speed, super-speed USB block devices
- Keyboard (test script sends keystrokes through QMP)
- USB serial
- Attach-detach looping
- Forceful device removal (also through QMP)

---

## usbvfiod Testing Optimizations

- CI uses a non-virtualized runner (to avoid triple nesting)
- logging cloud-hypervisor guest's kernel log to file, only print if necessary
- run logs through virtio console instead of serial
- trade-off between log details and test-suite execution time

---
layout: section
---

## Example 2: Booting Xen Hypervisor inside NixOS Test

---

## Xen in NixOS Test: Context

- A scenario from my PhD research
- The topic is centered around Xen's hypercall interface
- Static analysis (which hypercalls/arguments exist)
- Mostly dynamic analysis using Virtual Machine Introspection (which hypercalls actually happen)
- Interesting, optional topic: Benchmarking hypercall execution times across Xen versions

---

## <a href="https://github.com/lbeierlieb/xenmux">xenmux</a>: Easily Selectable Xen Versions for NixOS

- Idea: NixOS module to easily configure older Xen versions
- I brought this project to Ocean Sprint 2026

<img src="/img/xenmux.png" class="mx-auto max-h-70" />

---

## xenmux Integration Tests

- There is a simple test for every supported Xen version
- Test sequence
  - Boot
  - Check Xen version
- The challenge is usually building Xen before the tests runs at all

---

## Minimal Xen-Boot Test

```nix
{
  pkgs ? import <nixpkgs> { },
}:
pkgs.testers.nixosTest {
  name = "minimal-test";

  nodes.machine = {
    virtualisation.xen.enable = true;
    boot.loader.systemd-boot.enable = true;
  };

  testScript = ''
    machine.start()
    machine.succeed("xl info")
  '';
}
```

---

## Minimal Xen-Boot Test

```bash
$ nix build --file xen_minimal.nix
```
- Evaluates fine, boots the VM, but fails the check
```text
> machine: Guest shell says: b'Spawning backdoor root shell...\n'
> machine: connected to guest root shell
> machine: (connecting took 17.35 seconds)
> machine: (finished: waiting for the VM to finish booting, in 17.35 seconds)
> machine # xencall: error: Could not obtain handle on privileged command interface: No such file or directory
> machine # libxl: error: libxl.c:102:libxl_ctx_alloc: cannot open libxc handle: No such file or directory
> machine # cannot init xl context
> machine: output:
> !!! Traceback (most recent call last):
> !!!   File "<string>", line 2, in <module>
> !!!     machine.succeed("xl version")
> !!! 
> !!! RequestedAssertionFailed: command `xl version` failed (exit code 1)
```
- Looks like Xen is not running

---

## Xen-Boot Failure Investigation

- The commands to start nodes come from `node-configuration.system.build.vm`
```bash
$ nix build --file xen_minimal.nix nodes.machine.system.build.vm
$ cat result/bin/run-machine-vm
<...>
# Start QEMU.
exec /nix/store/<...>-qemu-host-cpu-only-for-vm-tests-10.2.4/bin/qemu-system-x86_64 <...>
    <...>
    -virtfs local,path=/nix/store,security_model=none,mount_tag=nix-store \
    -virtfs local,path="${SHARED_DIR:-$TMPDIR/xchg}",security_model=none,mount_tag=shared \
    -virtfs local,path="$TMPDIR"/xchg,security_model=none,mount_tag=xchg \
    -drive cache=writeback,file="$NIX_DISK_IMAGE",<...>
    <...>
    -kernel ${NIXPKGS_QEMU_KERNEL_machine:-/nix/store/<...>-nixos-system-machine-test/kernel} \
    -initrd /nix/store/<...>-initrd-linux-6.18.52/initrd \
    <...>
```
- Direct kernel boot!

---

## Xen-Boot: Avoiding Direct Kernel Boot

- The configuration declared systemd-boot as the bootloader, which will boot Xen
- `system.build.vm` completely skips the bootloader
- We can force disk-image building and booting
```nix
{
  virtualisation.useBootLoader = true;
  virtualisation.installBootLoader = true;
  virtualisation.useEFIBoot = true;
}
```

---

## Xen-Boot: Confirming the Avoidance of Direct Kernel Boot

```bash
$ nix build --file xen_minimal.nix nodes.machine.system.build.vm
$ cat result/bin/run-machine-vm
<...>
# Start QEMU.
exec /nix/store/<...>-qemu-host-cpu-only-for-vm-tests-10.2.4/bin/qemu-system-x86_64<...>
    <...>
    -virtfs local,path="${SHARED_DIR:-$TMPDIR/xchg}",security_model=none,mount_tag=shared \
    -virtfs local,path="$TMPDIR"/xchg,security_model=none,mount_tag=xchg \
    -drive cache=writeback,file="$NIX_DISK_IMAGE",id=drive1,if=none,<...>
    <...>
    -drive if=pflash,format=raw,unit=0,readonly=on,file=/nix/store/<...>-OVMF-202602-fd/FV/OVMF_CODE.fd \
    -drive if=pflash,format=raw,unit=1,readonly=off,file=$NIX_EFI_VARS \
    <...>
```

---

## Xen-Boot: Trying again

- The VM starts, the logs confirm the presence of Xen
```text
machine # [    0.000000] efi: EFI v2.7 by EDK II
machine # [    0.000000] efi: SMBIOS=0x3f93d000 ACPI=0x3fb7e000 ACPI 2.0=0x3fb7e014 (MEMATTR=0x3eb72018 unusable)
machine # [    0.000000] SMBIOS 2.8 present.
machine # [    0.000000] DMI: QEMU Standard PC (i440FX + PIIX, 1996), BIOS unknown 02/02/2022
machine # [    0.000000] DMI: Memory slots populated: 1/1
machine # [    0.000000] Hypervisor detected: Xen PV
machine # [    0.000030] Xen PV: Detected 1 vCPUS
```
- Test script is stuck at `waiting for the VM to finish booting`

---

## How the Test Driver Interacts with VMs (no Xen)

<img src="/diagrams/test-driver-console-noxen.svg" class="mx-auto max-h-70" />

- Bootloader, Xen, kernel log are visible through serial
- The VM configuration contains `backdoor.service`, which prints `connecting to host...` on `/dev/hvc0` and then runs a bash shell on this device

---

## How Xen Breaks the Interaction

<img src="/diagrams/test-driver-console-xen.svg" class="mx-auto max-h-70" />

- `backdoor.service` uses the wrong console device!

---

## Establishing Test-Driver--Nested-Guest Communication

- Forcing different enumeration order? Maybe
- Make console-device name configurable in `backdoor.service`? Added complexity, use case is too niche
- Just rename the devices
```nix
{
  systemd.services.renamehvc = {
    wantedBy = [ "backdoor.service" ];
    requires = [ "dev-hvc0.device" "dev-hvc1.device" ];
    before = [ "backdoor.service" ];
    serviceConfig.Type = "oneshot";
    script = "mv /dev/hvc1 /dev/hvc0";
  };
}
```

---
layout: section
---

## Example 3: FIDO Device Onboarding (FDO)

---

## FDO Context

- The second example from the context of secunet edge
- Important feature: Zero-touch deployment
  - Plug in power cable
  - Plug in network cable
  - Device automatically connects to correct central management service
- Provisioning management-service information in the factory does not scale well

---

## FDO Context

- The FDO protocol is a solution for this problem

<img src="/diagrams/fdo-protocol.svg" class="mx-auto max-h-70" />

---

## go-fdo: An FDO Implementation

- I was investigating https://github.com/fido-device-onboard/go-fdo-server

<img src="/img/go-fdo-repo.png" class="mx-auto max-h-70" />

---

## go-fdo: An FDO Implementation

- The repository offers a quick-start guide, walking through device intialization and onboarding

<img src="/img/go-fdo-quickstart.png" class="mx-auto max-h-70" />

---

## go-fdo: Quick-Start Guide with Nix

- Packaging the go-fdo-server and go-fdo-client applications was trivial

```nix
{
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "go-fdo-client";
  version = "1.0.0";
  src = fetchFromGitHub {
    owner = "fido-device-onboard";
    repo = "go-fdo-client";
    rev = "v${finalAttrs.version}";
    hash = "sha256-nPSaL+s/XIGtx3eWRnmUxQFWKFYW+H6XIoVSz18iRzI=";
  };

  vendorHash = "sha256-9TnzTjEBU8C3tO8/OSxfkwwUL17q5CMhSE8F5J97jbg=";

  meta.mainProgram = "go-fdo-client";
})
```

---

## go-fdo: Quick-Start Guide with Nix

- I built the sequence of the quick-start guide into an integration test
```nix
pkgs.testers.runNixOSTest {
  name = "fdo-check";
  nodes = {
    manufacturer = <...>;
    rendezvous = <...>;
    owner = <...>;
    client = <...>;
  };
  testScript = <...>;
```
- The nodes need cryptographic keys, information how to reach each other, services running the go-fdo binaries

---

## go-fdo: Quick-Start Guide with Nix

```python
manufacturer.start()
owner.start()
rendezvous.start()

# wait until servers ready
manufacturer.wait_until_succeeds("curl -X GET 'http://manufacturer:8080/api/v1/rvinfo' | grep rendezvous")
owner.wait_until_succeeds("curl -f -X GET 'http://owner:8080/api/v1/owner/redirect'")
rendezvous.wait_until_succeeds("curl -X GET 'http://rendezvous:8080/api/v1/device-ca' | grep CERTIFICATE")
<...>
```

---

## go-fdo: Quick-Start Guide with Nix

```python
<...>
# boot device at the manufacturer--creates device identity (and OV at the manufacturer server)
client.start()

# confirm by seeing the credential file
client.wait_until_succeeds("test -f /var/cred.bin")

# extract GUID; needed to retrieve OV later
guid = client.succeed("go-fdo-client print --blob /var/cred.bin | grep -oE '[0-9a-fA-F]{32}' | head -n1").strip()

# turn off client (and ship to customer)
client.shutdown()
<...>
```

---

## go-fdo: Quick-Start Guide with Nix

```python
<...>
# extract OV from manufacturer server
manufacturer.succeed(f"curl -f -v 'http://manufacturer:8080/api/v1/vouchers/{guid}' > /tmp/ownervoucher")

# and send OV to owner (also triggers TO0)
manufacturer.succeed("curl -f -X POST 'http://owner:8080/api/v1/owner/vouchers' --data-binary @/tmp/ownervoucher")
<...>
```

---

## go-fdo: Quick-Start Guide with Nix

```python
<...>
# boot device at the customer. Performs TO1 and TO2
client.start()

# check that onboarding succeeded
client.wait_until_succeeds("journalctl -u go-fdo-client.service | grep 'FIDO Device Onboard Complete'")
client.succeed("grep 'address of cloud management service' /var/onboard-payload")
'';
}
```

---

## Summary

- cloud-hypervisor running netboot image
- SSH into cloud-hypervisor guest for test-script interactions
- Add emulated USB devices to test machines
- Build VM image instead of direct kernel boot to test Xen (or bootloaders)
- Fixing `/dev/hvc0` backdoor
- You can also shut machines down!

---
layout: statement
class: text-center
---

<h2 class="mb-16">Thank you for your attention!</h2>

# Questions?

<simple-icons-nixos class="nix-spin mx-auto mt-12" style="font-size: 5rem; color: #5277c3" />

<style>
.nix-spin {
  transform-origin: center;
  animation: nix-spin-anim 6s linear infinite;
}
@keyframes nix-spin-anim {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
</style>
