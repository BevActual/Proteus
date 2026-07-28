---
doc: hardware
role: reference
audience: architects, contributors, hardware / driver planners
last_updated: "2026-07-26"
doc_status: active
scope: Device classes we target + capability/module catalog (sensors, I/O, compute, radios)
related:
  - POSTURES.md
  - APPLICATIONS.md
  - COMPOSITOR.md
  - ARCHITECTURE.md
  - CURRENT.md
status_legend:
  p0: Target for early resolver / desktop spine
  p1: Needed for second postures (media / host / home)
  p2: Wearable / XR / vehicle — later
  stretch: Speculative; don’t block architecture
---

# Hardware targets — device classes & modules

The posture/app model needs a **concrete inventory**: what kinds of machines we
care about, and which **sensors / modules / interfaces** become capability
flags. Without this, “capabilities” stay abstract.

Axes reminder ([POSTURES.md](./POSTURES.md), [APPLICATIONS.md](./APPLICATIONS.md)):

```
device class  ×  modules present  →  capability flags  ×  posture  ×  session
```

This doc is the **target catalog**, not a promise that every module ships in v1.

## Document map

| Section | Contents |
|---------|----------|
| [1. Device classes](#1-device-classes) | What we target |
| [2. Module catalog](#2-module-catalog) | Sensors, I/O, compute, radios |
| [3. Baseline kits](#3-baseline-kits) | Expected modules per class |
| [4. Capability IDs](#4-capability-ids) | Normalized flags apps/OS use |
| [5. Probe sources (planned)](#5-probe-sources-planned) | How we discover modules |
| [6. Priority](#6-priority) | What to implement first |
| [7. Non-goals](#7-non-goals) | Out of catalog scope |

---

## 1. Device classes

Physical product categories Proteus should **recognize** (class ≠ posture).

| Class ID | What it is | Typical postures | Priority |
|----------|------------|------------------|----------|
| `desktop` | Tower / SFF workstation | desktop, host | `p0` |
| `laptop` | Clamshell portable | desktop | `p0` |
| `phone` | Pocket slab, cellular | personal compact chrome | `p1` |
| `tablet` | Large touch slate | desktop-ish / media | `p1` |
| `tv` | Living-room display / STB | media | `p1` |
| `htpc` | Living-room PC | media, host | `p1` |
| `watch` | Wrist display companion | wearable | `p2` |
| `band` | Wrist/body sensor, little/no display | wearable | `p2` |
| `xr_headset` | HMD | xr | `p2` |
| `vehicle_hu` | Head unit / cluster companion | vehicle | `p2` |
| `hub` | Always-on house brain (may be headless) | home, host | `p1` |
| `server` | Rack/NUC lab box (often headless) | host | `p1` |
| `kiosk` | Fixed-purpose panel | home / custom | `stretch` |

A single machine has **one primary class** (probed or sticky override) plus a
**module set**.

---

## 2. Module catalog

Modules are discoverable hardware (or firm abstractions). Presence → capability
flags (§4).

### 2.1 Display & graphics

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `display.panel` | Local pixel output | `p0` |
| `display.multi` | ≥2 outputs | `p0` |
| `display.hdr` | HDR-capable pipeline | `p2` |
| `gpu.vulkan` / `gpu.gl` | Accelerated rendering | `p0` |
| `gpu.virt` | GPU for guests (host) | `p1` |

### 2.2 Input

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `input.keyboard` | Physical or reliable virtual KB | `p0` |
| `input.pointer` | Mouse / trackpad | `p0` |
| `input.touch` | Touchscreen | `p1` |
| `input.tablet_pen` | Stylus | `p2` |
| `input.gamepad` | Game controller | `p1` |
| `input.remote` | IR/Bluetooth TV remote / CEC | `p1` |
| `input.crown` / `input.dial` | Watch crown / volume knob | `p2` |
| `input.wheel` | Vehicle controls | `p2` |

### 2.3 Audio

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `audio.speaker` | Local playback | `p0` |
| `audio.headphones` | Jack / BT audio sink | `p0` |
| `audio.mic` | Capture | `p0` |
| `audio.hdmi` | AV over display link | `p1` |

### 2.4 Camera / optical

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `camera.user` | Webcam / phone selfie | `p1` |
| `camera.world` | Rear / scene camera | `p1` |
| `camera.passthrough` | XR passthrough | `p2` |
| `camera.depth` | Depth / LiDAR-class | `p2` / `stretch` |

### 2.5 Body / environment sensors

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `sensor.hr` | Heart rate | `p2` |
| `sensor.spo2` | Blood oxygen | `p2` |
| `sensor.temp_skin` | Skin temperature | `p2` |
| `sensor.eda` | Electrodermal (stress) | `stretch` |
| `sensor.imu` | Accel / gyro / mag | `p1` (phones) / `p2` |
| `sensor.baro` | Barometer / altitude | `p2` |
| `sensor.light` | Ambient light | `p1` |
| `sensor.proximity` | Proximity | `p1` |
| `sensor.gps` | GNSS | `p1` |
| `sensor.haptics` | Vibration actuator | `p1` |

Aggregate capability `vitals` = any of `sensor.hr` / `spo2` / related streams.

### 2.6 Radios & networking

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `net.ethernet` | Wired | `p0` |
| `net.wifi` | Wi-Fi | `p0` |
| `net.cellular` | WWAN / 5G | `p1` |
| `net.bt` | Bluetooth | `p0` |
| `net.ble` | Bluetooth LE (sensors, bands) | `p1` |
| `net.thread` / `net.zigbee` / `net.zwave` | Home mesh | `p1` |
| `net.matter` | Matter controller path | `p1` |
| `net.can` | Vehicle bus | `p2` |

### 2.7 Power & chassis

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `power.battery` | Battery present | `p0` |
| `power.ac` | On wall power | `p0` |
| `chassis.lid` | Lid switch | `p0` |
| `chassis.dock` | Dock / port replicator | `p1` |

### 2.8 Compute role modules (host / home)

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `virt.kvm` | Hardware virtualization | `p1` |
| `virt.gpu` | Mediated / passthrough GPU | `p2` |
| `container.engine` | Podman/Docker available | `p1` |
| `storage.pool` | Large disk / ZFS / LVM pool | `p1` |
| `home.radio` | Speaks to house devices (via net.* above) | `p1` |

### 2.9 Presence / session (soft modules)

Not always silicon — still part of the environment probe:

| Module ID | Meaning | Priority |
|-----------|---------|----------|
| `session.local_seat` | Local keyboard/display seat | `p0` |
| `session.ssh` | Remote terminal access | `p0` |
| `session.graphical_remote` | RDP/Waypipe/etc. (later) | `p1` |
| `session.headless` | No local interactive seat | `p1` |

---

## 3. Baseline kits

What we **expect** when targeting a class (not every unit has optionals).

| Class | Baseline modules | Common optionals |
|-------|------------------|------------------|
| `desktop` / `laptop` | display, keyboard, pointer, audio, net, gpu | multi-display, touch, battery (laptop), camera |
| `phone` | display, touch, cellular, wifi, bt, imu, battery, mic, speaker, cameras, gps, haptics, light/proximity | pen (rare), uwb (`stretch`) |
| `tablet` | display, touch, wifi, battery, imu | cellular, pen, keyboard dock |
| `tv` / `htpc` | display (or HDMI out), audio, remote/cec, net | gamepad, tuner (`stretch`) |
| `watch` | display (small), haptics, bt/ble, battery, imu, hr | spo2, gps, mic/speaker, wifi |
| `band` | ble, battery, hr (± spo2), imu | no display |
| `xr_headset` | display(s), imu, speakers/mic, cameras/passthrough | hand tracking, depth |
| `vehicle_hu` | display, audio, wheel/input, net; often `net.can` | cameras, mic |
| `hub` | net + home radios; often headless | display+touch panel, speaker/mic |
| `server` | net, storage, virt; often headless | local display seat, gpu.virt |

---

## 4. Capability IDs

Normalized flags for apps/OS (derived from modules). Keep this list small for
contracts; expand modules underneath.

| Capability | Derived from (examples) |
|------------|-------------------------|
| `display` | `display.panel` or active graphical seat |
| `headless` | `session.headless` / no local seat |
| `touch` / `pointer` / `keyboard` / `remote` / `gamepad` | matching `input.*` |
| `mic` / `speaker` | `audio.*` |
| `camera` | `camera.*` |
| `vitals` | `sensor.hr` / `spo2` / … |
| `imu` / `gps` / `haptics` | matching sensors |
| `battery` | `power.battery` |
| `cellular` / `wifi` / `bt` | `net.*` |
| `home_control` | `home.radio` or Matter/Thread/Zigbee present |
| `libvirt` / `containers` | `virt.kvm` / `container.engine` |
| `tiling` / `multi_monitor` | compositor policy + `display.multi` |
| `qs_hyprland` / `qs_pipewire` | engines installed + session allows |

App manifests should prefer **capability IDs** ([APPLICATIONS.md](./APPLICATIONS.md));
the resolver maps modules → capabilities.

---

## 5. Probe sources

| Source | Use |
|--------|-----|
| DRM / wl outputs | displays |
| libinput / udev | input |
| PipeWire / ALSA | audio |
| V4L2 | cameras |
| IIO / vendor HAB / BLE GATT | body sensors |
| ModemManager / NetworkManager BlueZ | radios |
| UPower | battery |
| systemd / D-Bus | seats, host services |
| libvirt / podman | virt modules |
| Sticky config | class/posture override when probe lies |

### Wave A implementation (`shipped` sketch)

```bash
./services/proteus-hw-probe/proteus-hw-probe
./scripts/hw-probe-smoke.sh
```

| Path | Role |
|------|------|
| `services/proteus-hw-probe/proteus_hw_probe.py` | Probe logic |
| `services/proteus-hw-probe/proteus-hw-probe` | CLI wrapper |
| `scripts/hw-probe-smoke.sh` | JSON shape gate |
| `shell/shared/session/Hardware.qml` | Session-start probe + read cache; `Hardware.has("wifi")` |
| `ShellState` | Mirrors class / caps; `refreshHardware()` |
| Probe `--cache` | Writes `~/.config/proteus/hw-probe.json` (no QML hex encode) |

Shell and Settings call the probe at startup (`Hardware` singleton
`Component.onCompleted`). Settings → About shows class + capability chips and
Refresh.

Emits `schema: proteus.hw.probe/v0` with `device_class`, `modules` (present),
`capabilities` (true flags), plus `details` (DRM connectors, session env).

Class heuristic: `hostnamectl` chassis / DMI / battery+lid → `laptop` vs
`desktop`. Later waves extend the same JSON shape.

---

## 6. Priority

| Wave | Focus |
|------|--------|
| **A — now** | `desktop`/`laptop` class; display, input.pointer/keyboard, audio, net, battery; compositor caps — **probe sketch shipped** |
| **B** | `server`/`hub` + virt/container/home radios; headless + UI-on-demand seats |
| **C** | `tv`/`htpc` + remote/gamepad; media posture |
| **D** | `phone`/`tablet` touch + sensors.light/proximity/imu |
| **E** | `watch`/`band` vitals + ble; `xr_headset`; `vehicle_hu` |

Do not block the desktop spine on wearable IMUs.

---

## 7. Non-goals

- Certifying every sensor vendor in v1  
- Requiring exotic modules (`eda`, LiDAR) for architecture validity  
- Equating “module present” with “user granted permission” (privacy consent is separate)  
- One capability flag per sysfs node — keep app-facing IDs coarse  

---

## Related

- Posture / kits: [POSTURES.md](./POSTURES.md)  
- App contracts: [APPLICATIONS.md](./APPLICATIONS.md)  
- Compositor engines: [COMPOSITOR.md](./COMPOSITOR.md)  
