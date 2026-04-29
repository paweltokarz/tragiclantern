# EOS 750D / firmware 1.1.0 port status

This document tracks the practical state of the Canon EOS 750D / Rebel T6i
firmware 1.1.0 development branch in this repository.

## Scope

This is an experimental Magic Lantern-based port/development tree for:

- camera: Canon EOS 750D / Rebel T6i
- Canon firmware: 1.1.0
- platform directory: `platform/750D.110`

The goal is not to start a clean port from scratch. The current baseline already
boots on real hardware and is used as a practical development base.

## Baseline known to work

The local baseline has been tested on a real EOS 750D:

- Magic Lantern starts.
- Modules load.
- File Manager works.
- Benchmark works.
- The build produces a package.
- The module system works.

## Current development focus

The current work is centered on:

- Lua module packaging and runtime use.
- Lua scripts under `scripts/`.
- Lua API exposure for camera/lens/shooting controls.
- PTP-based file transfer and deploy workflow.
- Property/eventproc mapping.
- Firmware stubs and Canon-side functions.
- Exposure override experiments.
- Canon GUI/state stability while running Magic Lantern-side code.

## PTP workflow

The development workflow uses PTP to reduce SD-card removal.

Expected local helpers, when present:

- `tools/ml_ptp_750d.py`
- `tools/ml_deploy_750d.py`

Typical local workflow:

```sh
python3 tools/ml_deploy_750d.py deploy --build
```

This builds the 750D target, backs up selected files from the camera over PTP,
uploads new build artifacts, downloads them back and verifies hashes.

PTP requires:

- camera powered on;
- Magic Lantern running;
- USB connected;
- no desktop process blocking the USB/PTP interface.

KDE/Dolphin/gphoto may interfere with access to the camera.

Replacing root `autoexec.bin` is risky even when the deploy helper verifies the
upload. Treat deploy operations as hardware-facing operations, not as ordinary
desktop file copies.

## Lua status

Lua is part of the active development path for this port.

Relevant locations:

- `modules/lua/`
- `scripts/`
- `platform/750D.110/modules.included`
- `platform/750D.110/modules.hidden`

The current direction is to use Lua first for diagnostics and controlled
shooting/exposure experiments, then move stable low-level mechanisms into the
port code where appropriate.

## Safety notes

This is experimental code running alongside Canon firmware on real hardware.

Treat the following as risky:

- replacing root `autoexec.bin`;
- changing platform stubs;
- changing property/eventproc behavior;
- adding exposure overrides;
- writing to the camera card outside known Magic Lantern paths;
- deploying untested modules to the camera.

Do not publish or commit:

- Canon firmware files such as `CCF23110.FIR`;
- extracted firmware blocks;
- generated build directories;
- `autoexec.bin`;
- `*.sym`;
- local card backups;
- files copied from the camera card unless they are intentional source assets.

## Public repository policy

This repository should contain source code and documentation only.

It should not contain Canon firmware, local binary dumps, generated package
artifacts, card backups or private local logs.
