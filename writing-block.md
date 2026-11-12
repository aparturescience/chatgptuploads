# COMPLETE TECHNICAL HANDOFF — REDMI 9A UEFI PORT

**Project:** EDK2 UEFI port for Xiaomi Redmi 9A  
**Device codename:** dandelion / blossom  
**SoC:** MediaTek MT6762G / MT6765 family  
**Date of investigation:** 12 November 2026

You are continuing an ongoing low-level firmware development and hardware research project.

Your task is to help investigate, design, and eventually develop a UEFI implementation for the Xiaomi Redmi 9A using EDK2 and an existing MediaTek MT6765 reference implementation.

This document contains the complete accumulated investigation, including hardware information, repository research, diagnostics, kernel-source findings, confirmed conclusions, hypotheses, unresolved questions, and the next steps.

**Read the entire document before proposing changes.**

Do not silently turn hypotheses into facts. Distinguish:
- Confirmed by device diagnostics.
- Confirmed by source-code inspection.
- Corroborated by multiple independent sources.
- Inferred or likely.
- Unknown or unverified.

The immediate priority is continuing the kernel-source and framebuffer audit, followed by the wider EDK2 platform audit.

---

# 1. Project objective

The primary objective is to port UEFI to the Redmi 9A.

The project uses an existing EDK2 implementation for another MediaTek MT6765-family device as its starting point.

The longer-term objective is to establish a UEFI environment capable of booting alternative operating systems. Windows ARM64 is a possible future target.

Immediate priorities:

- Memory initialization and memory-map correctness.
- LK-to-UEFI handoff.
- BootShim behavior.
- Device Tree interpretation.
- CPU topology and ACPI.
- GICv3 configuration.
- ARM architectural timers.
- UART and debugging.
- Display controller and framebuffer.
- GOP implementation.
- Preserving reserved memory.
- Identifying the actual Redmi 9A hardware initialization sequence.

The investigation should remain read-only unless explicitly authorized otherwise.

**Do not flash firmware, overwrite partitions, modify the user's repositories, commit changes, or perform destructive operations.**

---

# 2. Target hardware

| Property | Value |
|---|---|
| Device | Xiaomi Redmi 9A |
| Codename | dandelion |
| Alternate hardware name | blossom |
| SoC | MediaTek MT6762G |
| DT compatible | `mediatek,MT6765` |
| Architecture | ARM64 |
| CPU cores | 8 |
| CPU architecture | Cortex-A53 |
| RAM | 2 GiB |
| Display resolution | 720 × 1600 |
| Display refresh | 60 Hz |

Fastboot information:

```text
product: dandelion
version-bootloader: k62v1_64_bsp-c7050c70a-20220413232423-20220622193638
unlocked: yes
secure: no
```

Known partition sizes:

| Partition | Size |
|---|---:|
| lk | 2 MiB |
| lk2 | 2 MiB |
| boot | 64 MiB |
| dtbo | 8 MiB |

The installed LK and LK2 appear to be stock/unmodified.

SHA256:

```text
870b074fe65afd45d082f02669d808a5970aafb512935361201d08a972696b74
```

Recovery properties:

```text
ro.product.device=blossom
ro.boot.hardware=mt6762
ro.boot.hwname=dandelion
ro.boot.ddrsize=2
```

---

# 3. Repositories

## 3.1 EDK2 reference

https://github.com/xiaomi-blossom-dev/edk2-mt6765

This is the main reference implementation.

Important: it targets the Nokia 3.1 Plus (`roo`), not the Redmi 9A.

Its README reports that it reaches the EDK2 UEFI Shell and supports UART output, but its framebuffer driver is reportedly broken.

Treat it as a reference implementation, not a device-identical solution.

## 3.2 User's EDK2 repository

https://github.com/aparturescience/chatgptuploads

The user has connected GitHub and authorized inspection.

Previously obtained files include:

- `dandelion-recovery-live.dtb`
- `lk2-installed.img`
- `fe`

DTB details:

```text
File: dandelion-recovery-live.dtb
Size: 283,537 bytes
Blob SHA: e6a02da7317bdfac4552f87c5f6debfa4eb1908b
```

The DTB has already been obtained and parsed. Do not ask the user to upload it again.

The user has authorized revisiting the repository, but has not authorized modifications or commits.

## 3.3 Custom kernel source

The user supplied:

https://github.com/dre698/Nadeko-kernel

This is described as the closest available custom kernel source for the Redmi 9A.

It has already been inspected, particularly:

```text
drivers/misc/mediatek/video/mt6765/videox/mtkfb.c
```

This repository is an important source of hardware implementation information.

However, do not automatically assume its exact source revision matches the kernel installed on the phone.

Source-derived conclusions must be qualified accordingly.

No files have been modified or committed.

---

# 4. User's development environment

The user frequently works directly inside Android shell or recovery shell.

Example:

```text
blossom:/ $
```

When providing commands for this environment, do not prepend `adb shell`.

The user also uses Windows PowerShell:

```text
PS C:\Users\aperturescience>
```

Clearly identify which environment each command targets.

The user prefers multiline shell sequences enclosed in a single parenthesized block:

```sh
(
  command1
  command2
  command3
)
```

Prefer read-only diagnostics.

Do not recommend flashing LK/LK2, overwriting partitions, or performing destructive firmware operations.

---

# 5. Previous operating-system experiments

The user has successfully booted alternative operating systems and GSIs on the Redmi 9A.

Notable experiments:

- ColorOS 15 GSI.
- ColorOS 16 GSI.
- OpenHarmony GSI.

ColorOS 16 successfully booted after patching components.

A separate Android display-scaling problem was observed:

```text
Physical size: 720x1600
Physical density: 480
Override density: 300
StableDisplayWidth=1440
StableDisplayHeight=3216
```

This is a separate Android display-configuration investigation.

The user has also investigated a built-in screen failure where the device remained usable through scrcpy.

These experiments demonstrate that alternative software can boot on the hardware, but do not prove UEFI compatibility.

---

# 6. Physical RAM

Confirmed:

```text
Physical RAM base: 0x40000000
Physical RAM size: 0x80000000
Exclusive end:      0xC0000000
```

The target EDK2 system-memory configuration should therefore use:

```ini
gArmTokenSpaceGuid.PcdSystemMemoryBase|0x40000000
gArmTokenSpaceGuid.PcdSystemMemorySize|0x80000000
```

Important: `PcdSystemMemorySize` is a size, not an exclusive end address.

Do not use `0xC0000000` as the size.

The reference device has 3 GiB of RAM. Its memory map cannot simply be copied.

`/proc/meminfo` reported:

```text
MemTotal: 1926688 kB
```

The difference between physical RAM and Linux-visible RAM is expected due to reserved regions and kernel usage.

---

# 7. Reserved-memory regions

The Redmi 9A DTB contains the following reservations.

Preserve them unless their ownership and safe handling are established.

| Region | Base | Size | Purpose |
|---|---:|---:|---|
| DRAMC RK0 | `0xBFFFF000` | `0x1000` | DRAM controller |
| RAM console | `0x47C80000` | `0x10000` | Persistent RAM console |
| Pstore | `0x47C90000` | `0xE0000` | Persistent logs |
| Mini ramdump | `0x47D70000` | `0x10000` | Ramdump |
| ATF reserved | `0x47D80000` | `0x50000` | ARM Trusted Firmware |
| ATF ramdump | `0xBFF70000` | `0x80000` | ATF ramdump |
| ATF log | `0xBFE00000` | `0x40000` | ATF logging |
| Framebuffer | `0x7EC50000` | `0xFB0000` | Display framebuffer reservation |
| Log store | `0x7FFC0000` | `0x40000` | Log storage |
| TEE secure memory | `0x7FC00000` | `0x200000` | Trusted execution |
| SSPM | `0x7FF00000` | `0xC0000` | System power management |
| TEEI | `0x70000000` | `0x3C00000` | Secure memory |
| TEE log | `0xBFC00000` | `0x20000` | Secure logging |
| Ramoops | `0xB0000000` | `0x400000` | Persistent crash logging |

Other pools:

- SCP shared memory: 3 MiB.
- SSPM shared memory: approximately `0x110000`.
- Soter shared memory: 6 MiB.
- WiFi reserved memory: 3 MiB.
- CMA-related memory.

Other DTB nodes include:

```text
consys-reserve-memory
ion-carveout-heap
zone-movable-cma-memory
reserve-memory-scp_share
reserve-memory-sspm_share
soter-shared-mem
wifi-reserve-memory
```

Their exact properties and ownership should be inspected before designing the complete EDK2 memory map.

Preserve Device Tree `no-map` semantics.

---

# 8. MemoryInitPeiLib findings

Reference source:

```text
MT6765Pkg/Library/MemoryInitPeiLib/MemoryInitPeiLib.c
```

Important discovery:

**The reference `NoHob` option still adds the memory descriptor to the MMU mapping table.**

It skips HOB generation, but does not prevent mapping.

Therefore, `NoHob` does not preserve Device Tree `no-map` semantics.

A proposed design improvement is an explicit `NoMap` descriptor option.

Intended behavior:

- Keep the region reserved.
- Generate an appropriate reserved resource HOB.
- Do not add the region to normal MMU mapping.

This is a design proposal, not an implemented patch.

Verify the exact EDK2 revision, memory descriptor structures, HOB types, and MMU mapping code before implementing it.

The framebuffer, TEE, and other reserved regions must not accidentally become ordinary mapped or allocatable RAM.

---

# 9. BootShim findings

Reference file:

```text
BootShim/BootShim.S
```

The reference BootShim copies a fixed 2 MiB payload from an appended image to:

```text
UEFI_BASE = 0x50000000
```

It then branches to the copied payload.

Reference build setting:

```text
UEFI_SIZE=0x00200000
```

This is a fixed-size copy, not a dynamically validated payload size.

Reference boot-image offsets:

```text
--base 0x40078000
--kernel_offset 0x00008000
--ramdisk_offset 0x11a88000
--second_offset 0x00e88000
--tags_offset 0x07808000
--dtb_offset 0x07808000
```

These are donor-specific and must not be blindly reused.

The actual Redmi 9A boot image layout must be independently inspected.

---

# 10. Candidate UEFI payload location

Candidate:

```text
0x50000000
```

With a 2 MiB payload:

```text
Start: 0x50000000
End:   0x50200000
```

The Android `/proc/iomem` output showed this candidate inside:

```text
0x47DD0000 - 0x70000000 : System RAM
```

A nested reserved region exists:

```text
0x51B00000 - 0x54011FFF : reserved
```

The candidate 2 MiB area does not overlap that nested reservation.

There is approximately 25 MiB between the candidate payload end and the beginning of that reserved range.

The candidate also does not overlap the previously identified fixed DTB reservations.

Conclusion:

`0x50000000` is plausible, but not proven safe.

The Linux runtime memory map does not prove that LK leaves this area free during the earlier bootloader handoff.

Actual LK memory ownership remains unknown.

Do not approve this address as definitively safe without more investigation.

---

# 11. CPU topology

The target has eight Cortex-A53 cores in two clusters.

Expected MPIDR affinity values:

Cluster 0:

```text
0x000
0x001
0x002
0x003
```

Cluster 1:

```text
0x100
0x101
0x102
0x103
```

Reference source:

```text
MT6765Pkg/Library/MT6765PkgLib/MT6765Pkg.c
MT6765Pkg/AcpiTables/Madt.aslc
MT6765Pkg/Include/Configuration/CommonDsc.dsc.inc
```

The reference currently configures only one active CPU.

It uses:

```text
PcdCoreCount=1
PcdClusterCount=1
```

Only one active GICC is present in the reference MADT.

The DSDT describes CPU0 only.

The target needs:

- Eight correctly described CPU cores.
- Two clusters.
- Correct MPIDR values.
- Consistent CPU UIDs.
- Eight appropriate MADT GICC entries.
- Correct DSDT CPU declarations.
- Correct PCD values.
- Verified CPU startup behavior.

Changing only the PCD values is insufficient.

---

# 12. PSCI

The target reports:

```text
PSCI enabled
Conduit: SMC
PSCI version: 1.0
```

This is relevant to CPU initialization and secondary-core startup.

Verify that the reference PSCI implementation and CPU startup mechanism match the target firmware.

---

# 13. GICv3

Known addresses:

```text
GIC Distributor:   0x0C000000
GIC Redistributor: 0x0C100000
```

The redistributor length is not conclusively established.

A rough estimate for eight 128 KiB frames would be:

```text
8 × 0x20000 = 0x100000
```

This is only an estimate.

Inspect the target DTB for the exact GICR range.

The reference MADT may use `PcdGicInterruptInterfaceBase` as a GICC base.

Do not blindly copy it.

For GICv3 using the system-register CPU interface, verify the ACPI MADT GICv3 fields and address semantics.

---

# 14. ARM architectural timers

The reference implementation uses interrupt values:

```text
0x12
0x13
```

These have not been verified against the Redmi 9A DTB.

Inspect:

```text
arm,armv8-timer
```

Validate:

- Secure physical timer.
- Non-secure physical timer.
- Virtual timer.
- Hypervisor timer where applicable.
- Interrupt numbers.
- Trigger and polarity flags.
- GTDT contents.

Do not assume the reference timer values are correct.

---

# 15. UART

Target addresses:

```text
UART0: 0x11002000
UART1: 0x11003000
```

Kernel command line includes:

```text
console=ttyS0,921600n1
mtk_printk_ctrl.disable_uart=1
```

The disable flag may explain the absence of Linux UART logs, but does not prove LK or EDK2 cannot use UART.

Reference UART implementation:

```text
UART0 base: 0x11002000
TX status register: 0x11002014
```

The address matches the target.

However, the reference UART library:

- Lacks input support.
- Lacks timeout handling.
- Assumes UART is already initialized.

Reference ACPI concerns:

- `Spcr.aslc` describes PL011.
- The target uses MediaTek UART.
- SPCR was commented out in `AcpiTables.inf`.
- DBG2 advertises zero debug ports.

Do not enable PL011 SPCR on the target.

Verify the MTK UART register layout, clock, baud rate, and initialization sequence.

---

# 16. Display hardware

Known target addresses:

| Component | Address |
|---|---:|
| DSI controller | `0x14014000` |
| Display configuration | `0x14000000` |
| Display mutex | `0x14001000` |
| Overlay | `0x1400B000` |
| RDMA | `0x1400D000` |
| Display PWM | `0x1100E000` |

A previous DTB investigation identified:

```text
nt35695B_fhd_dsi_cmd_auo_rt5081_drv
```

as a panel-related name.

However, the newly discovered packed ATAG contains a different name:

```text
nt36525b_vdo_hdp_boe_xinli_drv
```

This discrepancy must be interpreted using the actual kernel parser, as described in the framebuffer section.

Do not assume the older name is the active panel driver.

---

# 17. FRAMEBUFFER INVESTIGATION — COMPLETE FINDINGS

This is one of the most important parts of the project.

The objective is to establish the physical framebuffer location, its size, its layout, and whether UEFI can reuse it through GOP.

## 17.1 Linux framebuffer device

The device reports:

```text
0 mtkfb
```

Driver:

```text
mtkfb
```

Device Tree node:

```text
/mtkfb@0
```

Compatible:

```text
mediatek,mtkfb
```

Sysfs:

```text
/sys/class/graphics/fb0
```

The device's `uevent` reports:

```text
DRIVER=mtkfb
OF_NAME=mtkfb
OF_FULLNAME=/mtkfb@0
OF_COMPATIBLE_0=mediatek,mtkfb
OF_COMPATIBLE_N=1
```

The node is enabled:

```text
status = okay
```

The `/mtkfb@0` node does not contain:

- `reg`
- `memory-region`
- An explicit framebuffer address.

Therefore, the framebuffer physical address is not obtained directly from that platform node.

## 17.2 Confirmed framebuffer geometry

Direct sysfs results:

```text
/sys/class/graphics/fb0/virtual_size
736,3200
```

```text
/sys/class/graphics/fb0/bits_per_pixel
32
```

```text
/sys/class/graphics/fb0/stride
2944
```

```text
/sys/class/graphics/fb0/name
mtkfb
```

The directory does not expose `smem_start` or `smem_len`.

Confirmed geometry:

| Property | Value |
|---|---:|
| Visible width | 720 |
| Visible height | 1600 |
| Virtual width | 736 |
| Virtual height | 3200 |
| Bits per pixel | 32 |
| Bytes per pixel | 4 |
| Stride | 2944 bytes |

The stride is consistent:

```text
736 × 4 = 2944 bytes
```

The virtual framebuffer footprint implied by the geometry is:

```text
2944 × 3200 = 9,420,800 bytes
```

This is approximately 8.98 MiB.

The virtual height is twice the visible height.

This is consistent with a double-height framebuffer arrangement, but it does not independently prove active page flipping.

## 17.3 DTB framebuffer reservation

The DTB contains:

```text
/reserved-memory/mblock-13-framebuffer
```

Its properties were inspected directly.

```text
compatible = mediatek,framebuffer
name = mblock-13-framebuffer
no-map = present
```

The raw `reg` bytes:

```text
00 00 00 00 7e c5 00 00
00 00 00 00 00 fb 00 00
```

The parent uses:

```text
#address-cells = 2
#size-cells = 2
```

Decoded:

```text
Base: 0x7EC50000
Size: 0x00FB0000
```

Exclusive end:

```text
0x7FC00000
```

This confirms the DTB reservation:

```text
0x7EC50000 - 0x7FBFFFFF
```

It is marked `no-map`.

The reservation ends exactly where the TEE secure-memory reservation begins:

```text
0x7FC00000
```

This is strong evidence of the intended framebuffer region.

## 17.4 Chosen-node ATAG information

The user inspected:

```text
/sys/firmware/devicetree/base/chosen
```

The chosen node contains:

```text
atag,videolfb
atag,videolfb-fb_base_h
atag,videolfb-fb_base_l
atag,videolfb-fps
atag,videolfb-islcm_inited
atag,videolfb-islcmfound
atag,videolfb-lcmname
atag,videolfb-vramSize
```

The important raw properties:

### Packed `atag,videolfb`

```text
00 00 c5 7e 00 00 00 00
01 00 00 00
b6 17 00 00
00 00 fb 00
6e 74 33 36 35 32 35 62 5f 76 64 6f 5f
68 64 70 5f 62 6f 65 5f 78 69 6e 6c 69
5f 64 72 76 00 00
```

The source defines this vendor-specific structure:

```c
struct tag_video_lfb {
    u64 fb_base;
    u32 islcmfound;
    u32 fps;
    u32 vram;
    char lcmname[1];
};
```

The kernel directly interprets this packed property as a native C structure.

On the target's little-endian ARM64 architecture, the packed bytes decode as:

| Field | Value |
|---|---|
| `fb_base` | `0x000000007EC50000` |
| `islcmfound` | `1` |
| `fps` | `6070` |
| `vram` | `0x00FB0000` |
| `lcmname` | `nt36525b_vdo_hdp_boe_xinli_drv` |

The FPS value is 6070 in the packed property, not 6000.

Do not confuse the byte interpretation of this vendor-specific packed binary structure with the normal big-endian Device Tree cell representation.

### Separate fallback properties

The user also found:

```text
atag,videolfb-fb_base_h:
00 00 00 00
```

```text
atag,videolfb-fb_base_l:
5e 60 50 00
```

```text
atag,videolfb-fps:
00 00 17 70
```

```text
atag,videolfb-islcm_inited:
00 00 00 00
```

```text
atag,videolfb-islcmfound:
00 00 00 01
```

```text
atag,videolfb-lcmname:
nt35695B_fhd_dsi_cmd_auo_rt5081_drv
```

```text
atag,videolfb-vramSize:
01 7b b0 00
```

These separate properties are parsed using `of_read_number()`, so their 32-bit cells are interpreted in Device Tree big-endian order.

Therefore:

```text
fb_base_h = 0
fb_base_l = 0x5E605000
fallback base = 0x5E605000
```

And:

```text
fallback fps = 6000
fallback vramSize = 0x017BB000
```

Do not decode the fallback base as `0x0050605E`.

## 17.5 Critical kernel parser discovery

The custom kernel source contains:

```text
drivers/misc/mediatek/video/mt6765/videox/mtkfb.c
```

Relevant source functions:

```c
__parse_tag_videolfb()
__parse_tag_videolfb_extra()
_parse_tag_videolfb()
mtkfb_get_fb_base()
mtkfb_get_fb_size()
```

The packed structure is defined as:

```c
struct tag_video_lfb {
    u64 fb_base;
    u32 islcmfound;
    u32 fps;
    u32 vram;
    char lcmname[1];
};
```

The packed parser reads:

```c
videolfb_tag =
    (struct tag_video_lfb *)of_get_property(
        node, "atag,videolfb", (int *)&size);
```

When this property exists, it assigns:

```c
lcd_fps = videolfb_tag->fps;
islcmconnected = videolfb_tag->islcmfound;
vramsize = videolfb_tag->vram;
fb_base = videolfb_tag->fb_base;
is_lcm_inited = 1;
```

It also obtains the panel name from:

```c
videolfb_tag->lcmname
```

The separate-property parser:

```c
__parse_tag_videolfb_extra()
```

is attempted only if the packed property is absent or fails.

The control flow in `_parse_tag_videolfb()` is:

1. Find `/chosen` or `/chosen@0`.
2. Try parsing packed `atag,videolfb`.
3. If successful, go directly to the success path.
4. Only if packed parsing fails, try the separate properties.

Therefore, in this kernel source, **the packed ATAG is preferred over the separate fallback properties**.

This explains the different values.

The fallback values are not evidence that the driver simultaneously uses another framebuffer.

## 17.6 Framebuffer mapping in the kernel driver

The `mtkfb_probe()` function contains:

```c
disp_hal_allocate_framebuffer(
    fb_base,
    (fb_base + vramsize - 1),
    (unsigned long *)(&fbdev->fb_va_base),
    &fb_pa
);

fbdev->fb_pa_base = fb_base;
```

It then calls:

```c
primary_display_set_frame_buffer_address(
    (unsigned long)(fbdev->fb_va_base),
    fb_pa,
    fb_base
);
```

It subsequently initializes the display:

```c
primary_display_init(
    mtkfb_find_lcm_driver(),
    lcd_fps,
    is_lcm_inited
);
```

The driver later sets:

```c
fix->smem_len = fbdev->fb_size_in_byte;
fix->smem_start = fbdev->fb_pa_base;
```

And the probe assigns:

```c
fbdev->fb_size_in_byte = MTK_FB_SIZEV;
```

The key conclusion:

**This driver uses the physical framebuffer base supplied by the LK-provided packed ATAG.**

The allocation/mapping path is:

```text
/chosen/atag,videolfb
        |
        v
__parse_tag_videolfb()
        |
        v
fb_base = 0x7EC50000
vramsize = 0x00FB0000
        |
        v
mtkfb_probe()
        |
        v
disp_hal_allocate_framebuffer(
    fb_base,
    fb_base + vramsize - 1,
    ...
)
        |
        v
fbdev->fb_pa_base = fb_base
        |
        v
fix.smem_start = fbdev->fb_pa_base
```

This is strong source-level evidence that the kernel maps a pre-existing framebuffer region supplied by LK.

It is not an ordinary allocation from general Linux RAM using `dma_alloc_coherent()`.

The exact internal implementation of `disp_hal_allocate_framebuffer()` still needs inspection.

## 17.7 Important distinction: reserved VRAM versus fbdev smem_len

The driver maps the range:

```text
[fb_base, fb_base + vramsize - 1]
```

For the packed ATAG:

```text
fb_base = 0x7EC50000
vramsize = 0x00FB0000
```

But the driver reports:

```c
fix->smem_len = fbdev->fb_size_in_byte;
```

And:

```c
fbdev->fb_size_in_byte = MTK_FB_SIZEV;
```

The macro is:

```c
#define MTK_FB_SIZEV \
    (MTK_FB_LINE * ALIGN_TO(MTK_FB_YRES, MTK_FB_ALIGNMENT) \
    * MTK_FB_PAGES)
```

Where:

```c
#define MTK_FB_LINE \
    (ALIGN_TO(MTK_FB_XRES, MTK_FB_ALIGNMENT) * MTK_FB_BYPP)
```

Therefore:

- The ATAG `vramsize` is the reserved/mapped VRAM range.
- The fbdev `smem_len` is calculated from the display dimensions, alignment, bytes per pixel, and page count.
- These values need not be equal.

Do not assume `smem_len` equals `0x00FB0000`.

Do not assume the visible virtual geometry alone proves the exact internal page count.

The source contains:

```c
static u32 MTK_FB_PAGES;
```

and obtains it through:

```c
MTK_FB_PAGES = DISP_GetPages();
```

The exact implementation of `DISP_GetPages()` and the target's `MTK_FB_ALIGNMENT` must be inspected.

## 17.8 Framebuffer reservation and capacity

Confirmed DTB reservation:

```text
Base: 0x7EC50000
Size: 0x00FB0000
End:  0x7FC00000 (exclusive)
```

Packed ATAG:

```text
Base: 0x7EC50000
VRAM size: 0x00FB0000
```

These match exactly.

The virtual framebuffer geometry implies:

```text
2944 × 3200 = 9,420,800 bytes
```

This fits inside the reserved 16,449,536-byte region.

The reservation is larger than the virtual framebuffer footprint.

However, the actual fbdev size must be obtained from `MTK_FB_SIZEV` and the driver's runtime configuration.

## 17.9 Framebuffer GOP requirements

The reference driver is:

```text
MT6765Pkg/Drivers/SimpleFbDxe/SimpleFbDxe.c
```

It assumes tightly packed rows:

```c
LineLength = Width * 4;
PixelsPerScanLine = Width;
FrameBufferSize = LineLength * Height;
```

This is unsuitable for the Redmi 9A if it uses the observed 736-pixel stride.

The target GOP mode should advertise:

```text
HorizontalResolution = 720
VerticalResolution = 1600
PixelsPerScanLine = 736
```

Pixel depth:

```text
32 bits
4 bytes per pixel
```

Correct row stride:

```text
736 × 4 = 2944 bytes
```

The GOP framebuffer base is strongly corroborated as:

```text
0x7EC50000
```

The driver should preserve the framebuffer reservation as `no-map` in the normal EDK2 memory-map design.

However, a framebuffer device mapping may still be required with appropriate memory attributes. Do not confuse "no-map in the normal system RAM map" with "UEFI is forbidden from mapping the framebuffer at all."

The framebuffer must be mapped deliberately with appropriate device/normal-memory attributes and cacheability after examining the hardware and display-controller access requirements.

Do not let the normal memory allocator use this region.

## 17.10 False positive in earlier /proc/iomem search

An earlier search returned:

```text
47cfb000-47cfbfff : persistent_ram
```

This was a false positive caused by matching `fb0` inside the hexadecimal address `47cfb000`.

It was not framebuffer evidence.

Do not cite it as such.

## 17.11 Framebuffer status

<status>Strongly corroborated</status>

| Property | Value | Evidence |
|---|---|---|
| Physical base | `0x7EC50000` | Packed ATAG, DTB reservation, kernel parser |
| Reserved VRAM size | `0x00FB0000` | Packed ATAG and DTB reservation |
| Exclusive end | `0x7FC00000` | Calculated from base + size |
| `no-map` | Present | DTB |
| Visible width | 720 | Linux framebuffer diagnostics |
| Visible height | 1600 | Linux framebuffer diagnostics |
| Virtual width | 736 | Linux framebuffer diagnostics |
| Virtual height | 3200 | Linux framebuffer diagnostics |
| Pixel depth | 32 bpp | Linux framebuffer diagnostics |
| Stride | 2944 bytes | Linux framebuffer diagnostics |
| Driver | `mtkfb` | Linux sysfs |
| ATAG parser | Packed property first | Kernel source |
| Framebuffer mapping | LK-provided range | Kernel source |

Still unknown:

- Whether this exact source revision matches the installed kernel.
- Exact implementation of `disp_hal_allocate_framebuffer()`.
- Exact `DISP_GetPages()` result.
- Exact `MTK_FB_ALIGNMENT`.
- Exact runtime `fbdev->fb_size_in_byte`.
- Whether the actual framebuffer is actively double-buffered.
- Exact pixel channel order as exposed by the current kernel.
- Whether LK leaves the panel and display controller fully initialized for UEFI.
- Whether UEFI can safely reuse the existing scanout without reinitializing the panel.

---

# 18. Panel-name investigation

This is another important discovery.

The packed ATAG name:

```text
nt36525b_vdo_hdp_boe_xinli_drv
```

The separate fallback name:

```text
nt35695B_fhd_dsi_cmd_auo_rt5081_drv
```

These are different names.

The custom kernel source resolves which name its parser prefers.

When packed `atag,videolfb` exists, it copies:

```c
videolfb_tag->lcmname
```

into:

```c
mtkfb_lcm_name
```

It sets:

```c
is_lcm_inited = 1;
```

It does not use the separate `atag,videolfb-lcmname` property in that path.

The fallback parser reads the separate name only if the packed structure is missing or unavailable.

The probe calls:

```c
primary_display_init(
    mtkfb_find_lcm_driver(),
    lcd_fps,
    is_lcm_inited
);
```

And:

```c
mtkfb_find_lcm_driver()
```

calls `_parse_tag_videolfb()` and returns `mtkfb_lcm_name`.

Therefore, for this kernel source, the packed name is the one passed into the display initialization path when the packed ATAG is present.

**Do not treat the separate LCM name as the active panel driver merely because it appears in the chosen node.**

However, this is source-derived behavior, not definitive proof of the physical panel identity or the exact kernel currently running.

Next investigate:

- Whether the driver `nt36525b_vdo_hdp_boe_xinli_drv` exists in the source.
- Whether it is compiled into the kernel.
- Its resolution, timing, DSI mode, lane configuration, and initialization sequence.
- Whether the actual running kernel logs identify this driver.
- Whether the separate fallback name is used only for a different boot configuration, such as the reported FPGA configuration.

The previous investigation reported that `custom_common.dtsi` describes the separate properties as FPGA-related fallback data. Verify that source file before treating that explanation as established.

Also note:

The packed parser unconditionally sets `is_lcm_inited = 1`, despite the separate property reporting zero.

Do not use the separate `atag,videolfb-islcm_inited` value to override the packed parser's effective value without understanding the parser path.

---

# 19. Kernel-source follow-up tasks

The next investigation should focus on:

Repository:

```text
https://github.com/dre698/Nadeko-kernel
```

Already inspected:

```text
drivers/misc/mediatek/video/mt6765/videox/mtkfb.c
```

Investigate the following symbols and definitions:

```text
disp_hal_allocate_framebuffer
DISP_GetPages
MTK_FB_ALIGNMENT
MTK_FB_SIZEV
primary_display_init
primary_display_set_frame_buffer_address
mtkfb_fbinfo_init
```

Search likely locations:

```text
drivers/misc/mediatek/video/mt6765/
drivers/misc/mediatek/video/
drivers/misc/mediatek/
```

Questions:

1. How exactly does `disp_hal_allocate_framebuffer()` map the physical range?
2. Does it use `ioremap`, `ioremap_wc`, or another mapping mechanism?
3. Does it perform any cache maintenance?
4. What is the returned virtual address?
5. Does it modify or reserve the supplied physical region?
6. What is the actual `DISP_GetPages()` implementation?
7. What is the target `MTK_FB_ALIGNMENT`?
8. What is the actual `MTK_FB_SIZEV`?
9. Is the fbdev virtual geometry 736×3200 consistent with the calculated `MTK_FB_SIZEV`?
10. What is the exact pixel format and channel order?
11. Does the display initialization path reinitialize the panel even when LK already initialized it?
12. Does the display driver preserve LK's existing scanout?
13. What is the exact panel driver selected by the packed ATAG?
14. Which display clocks, regulators, GPIOs, and reset sequences are required if UEFI must initialize the panel independently?

Do not make assumptions about these functions without inspecting their definitions.

---

# 20. CPU and ACPI work still required

Reference files:

```text
MT6765Pkg/Library/MT6765PkgLib/MT6765Pkg.c
MT6765Pkg/AcpiTables/Madt.aslc
MT6765Pkg/Include/Configuration/CommonDsc.dsc.inc
```

Work required:

- Eight CPU entries.
- Two cluster topology.
- Verified MPIDR values.
- Eight MADT GICC entries.
- Correct DSDT CPU declarations.
- Correct CPU UIDs.
- Secondary-core startup.
- PSCI integration.
- Correct PCD configuration.

Do not simply uncomment donor CPU entries without checking the target's actual topology.

---

# 21. Memory map and platform structure

Keep the `roo` configuration intact.

Create a separate target configuration.

Suggested structure:

```text
MT6765Pkg/
├── Devices/
│   ├── roo.dsc
│   └── dandelion.dsc
├── Include/
│   └── Configuration/
│       ├── DeviceMemoryMap.h
│       └── DandelionMemoryMap.h
├── Library/
├── Drivers/
└── AcpiTables/
```

The target should have its own memory map and device configuration.

Initial proposed PCDs, pending verification:

```ini
[PcdsFixedAtBuild.common]
  gArmTokenSpaceGuid.PcdSystemMemoryBase|0x40000000
  gArmTokenSpaceGuid.PcdSystemMemorySize|0x80000000
  gArmPlatformTokenSpaceGuid.PcdCoreCount|8
  gArmPlatformTokenSpaceGuid.PcdClusterCount|2
  gArmTokenSpaceGuid.PcdGicDistributorBase|0x0C000000
```

Verify the PCD names and definitions in the actual EDK2 revision.

Do not add guessed redistributor PCDs.

---

# 22. Previous /proc/iomem diagnostic

The user provided this Linux runtime memory-map excerpt:

```text
40000000-47c7ffff : System RAM
  40080000-416effff : Kernel code
  416f0000-4179ffff : reserved
  417a0000-41d02fff : Kernel data
  47880000-478c5fff : reserved
47c90000-47c90fff : persistent_ram
...
47dd0000-6fffffff : System RAM
  51b00000-54011fff : reserved
73c00000-7ec4ffff : System RAM
7fe00000-7fefffff : System RAM
7ffc0000-8effffff : System RAM
  7ffc0000-7fffffff : reserved
8f300000-8f9fffff : System RAM
90000000-9feeffff : System RAM
a0000000-bdffffff : System RAM
  b0000000-b03fffff : reserved
  bc000000-bdffffff : reserved
be400000-beffffff : System RAM
bf300000-bfbfffff : System RAM
  bfa00000-bfbfffff : reserved
bfc20000-bfdfffff : System RAM
  bfc40000-bfdfffff : reserved
bfe40000-bff6ffff : System RAM
  bfece000-bfecefff : reserved
  bfed1000-bfed1fff : reserved
  bfed2000-bfed2fff : reserved
  bfed3000-bfed4fff : reserved
  bfed5000-bfedefff : reserved
  bfedf000-bff6ffff : reserved
bfff0000-bfffefff : System RAM
  bfff0000-bfffefff : reserved
```

This is a Linux runtime map, not a complete representation of LK's earlier memory ownership.

Treat all extra reserved ranges as unavailable until their ownership is understood.

---

# 23. Kernel command line and diagnostic details

Kernel command line included:

```text
console=tty0 console=ttyS0,921600n1
ramoops.mem_address=0x47c90000
ramoops.mem_size=0xe0000
androidboot.hardware=mt6765
androidboot.ddrsize=2
androidboot.hwname=dandelion
mtk_printk_ctrl.disable_uart=1
```

Other boot arguments were present.

The user searched kernel logs for memory, reservations, framebuffer, TEE, SSPM, SCP, and related terms.

The retained logs mostly showed SCP/sensorHub not-ready messages.

No useful early memory reservation logs were found.

`/proc/bootconfig` was empty.

---

# 24. Remaining unknowns

## Bootloader and memory

1. What exact memory map does LK use before handing control to the kernel?
2. Is `0x50000000` safe for UEFI during the LK handoff?
3. What are the exact Redmi 9A boot-image offsets?
4. Does BootShim need target-specific register or handoff handling?
5. What is the actual UEFI payload size?
6. Should the fixed 2 MiB BootShim copy be replaced by a validated size mechanism?
7. What are the exact dynamic shared-memory allocations and their owners?

## Memory initialization

8. How should every `no-map` reservation be represented in EDK2?
9. What exact HOB and MMU behavior is required?
10. Which regions can safely be mapped as device memory?
11. Which regions must remain unmapped?
12. How should the framebuffer be mapped deliberately without making it normal allocatable RAM?

## CPU and ACPI

13. Are the expected MPIDR values correct?
14. What exact secondary-core startup sequence is required?
15. What are the correct GICv3 MADT fields?
16. What are the exact GICR base and length?
17. What are the correct timer interrupt numbers and flags?
18. Does the reference PSCI implementation match the target?

## UART

19. What clock and initialization values are required for UART0?
20. Is UART initialized by LK when BootShim starts?
21. Can the reference UART library work reliably without modification?
22. What is the appropriate ACPI debugging representation?

## Framebuffer and display

23. Does the installed kernel use the same framebuffer code as Nadeko-kernel?
24. What is the exact `disp_hal_allocate_framebuffer()` implementation?
25. What is the exact `DISP_GetPages()` result?
26. What is the target `MTK_FB_ALIGNMENT`?
27. What is the exact runtime `fb_size_in_byte`?
28. Is the virtual height of 3200 actually used for two framebuffer pages?
29. What is the exact pixel channel layout?
30. Can UEFI reuse the existing framebuffer without reinitializing DSI?
31. Does LK leave the panel and scanout active?
32. Which panel driver is actually used by the running kernel?
33. What panel initialization steps are required if UEFI must initialize the screen itself?
34. What memory attributes should be used for framebuffer mapping?

---

# 25. Work already completed

The following work has been performed:

- Identified target hardware and SoC family.
- Established the 2 GiB physical RAM range.
- Inspected the reference EDK2 repository.
- Identified donor-specific memory-map differences.
- Inspected BootShim's fixed 2 MiB copy.
- Identified CPU topology limitations.
- Identified GICv3 and timer configuration questions.
- Inspected the reference UART implementation.
- Identified the PL011 SPCR mismatch.
- Inspected the reference framebuffer GOP driver.
- Retrieved and parsed the Redmi 9A recovery DTB.
- Identified target reserved-memory regions.
- Investigated Linux `/proc/iomem`.
- Evaluated `0x50000000` as a possible UEFI payload location.
- Inspected the `mtkfb` sysfs device.
- Confirmed visible and virtual framebuffer geometry.
- Confirmed framebuffer stride and bit depth.
- Inspected the `/mtkfb@0` Device Tree node.
- Inspected `mblock-13-framebuffer`.
- Confirmed the framebuffer reservation base, size, and `no-map`.
- Inspected `/chosen` ATAG properties.
- Decoded the packed `atag,videolfb` structure.
- Found the different fallback ATAG values.
- Inspected Nadeko-kernel's `mtkfb.c`.
- Confirmed the packed ATAG parser takes priority over the fallback parser.
- Confirmed the source passes the packed framebuffer base and VRAM range into `disp_hal_allocate_framebuffer()`.
- Confirmed the source sets `fix.smem_start` from the ATAG-derived framebuffer base.
- Identified the difference between the mapped VRAM range and the fbdev `smem_len` calculation.
- Identified the panel-name parsing discrepancy and its fallback explanation.

No source files have been modified or committed.

No firmware partitions have been flashed or written.

---

# 26. Exact next steps

Continue in this order.

## Step 1 — Finish the kernel framebuffer source audit

Inspect:

```text
disp_hal_allocate_framebuffer()
DISP_GetPages()
MTK_FB_ALIGNMENT
MTK_FB_SIZEV
```

Determine:

- Mapping mechanism.
- Cache attributes.
- Actual framebuffer page count.
- Actual allocation footprint.
- Exact framebuffer pixel format.
- Whether the display driver resets or preserves the display hardware.

## Step 2 — Verify the active panel driver

Inspect the panel driver named by the packed ATAG:

```text
nt36525b_vdo_hdp_boe_xinli_drv
```

Compare it with the fallback name:

```text
nt35695B_fhd_dsi_cmd_auo_rt5081_drv
```

Find out which driver is actually selected and whether its initialization runs when the kernel starts.

## Step 3 — Translate framebuffer findings into EDK2 requirements

Design GOP around:

```text
Base: 0x7EC50000
Visible: 720×1600
Stride: 736 pixels
Pixel depth: 32 bpp
```

Use the confirmed physical reservation size as the boundary for the reserved region, but separately establish the valid framebuffer footprint and memory attributes.

Do not blindly reuse the reference tightly packed framebuffer driver.

## Step 4 — Continue the platform audit

Return to:

- BootShim handoff.
- LK memory ownership.
- MemoryInitPeiLib.
- CPU topology.
- GICv3.
- GTDT.
- UART.
- ACPI.
- Target-specific EDK2 configuration.

---

# 27. Working rules

- Be technically rigorous.
- Do not invent addresses, PCD names, register values, or hardware behavior.
- Verify source before making claims about implementation.
- Distinguish source-derived behavior from the installed device's observed behavior.
- Do not assume Nadeko-kernel exactly matches the installed kernel.
- Use the target DTB rather than donor-device assumptions.
- Preserve reserved-memory regions.
- Do not confuse Linux runtime memory maps with LK handoff ownership.
- Do not assume a DTB reservation alone proves active driver use; in this case, use the packed ATAG and kernel source as additional corroboration.
- Do not assume `smem_len` equals the ATAG VRAM size.
- Do not assume virtual height proves page flipping.
- Do not assume fallback ATAG properties override a present packed ATAG.
- Do not assume the fallback panel name identifies the active panel.
- Do not blindly reuse donor boot-image offsets.
- Do not blindly reuse donor CPU, GIC, timer, UART, or display configuration.
- Keep the `roo` reference configuration intact.
- Prefer a separate `dandelion` configuration.
- Do not modify or commit repository files without explicit permission.
- Do not flash or write firmware.
- Prefer safe, read-only diagnostics.
- When giving Android shell commands, do not prepend `adb shell`.
- Put multiline shell commands inside one parenthesized block.
- Explain what each diagnostic establishes and what it cannot establish.

**The immediate next objective is to finish inspecting the Nadeko-kernel framebuffer allocation and display initialization implementation, then use those findings to design a correct Redmi 9A-specific GOP driver and memory map.**