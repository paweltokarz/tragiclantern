Magic Lantern EOS 750D / 1.1.0 Experimental Port
==================================================

This repository contains an experimental Magic Lantern-based development tree
for the Canon EOS 750D / Rebel T6i running Canon firmware 1.1.0.

It is based on the Magic Lantern codebase, but this repository is focused on
the EOS 750D / 1.1.0 port and the development workflow around this camera.

Current focus
-------------

- EOS 750D / firmware 1.1.0 platform work.
- Lua scripting support on real hardware.
- PTP-based development and deploy workflow.
- Runtime diagnostics without repeatedly removing the SD card.
- Exposure, property, eventproc and Canon GUI/state experiments.
- Controlled photographic parameter overrides from Magic Lantern, Lua or port code.

Status
------

Experimental.

The current development branch has been tested on a real Canon EOS 750D. Magic
Lantern boots, modules load, File Manager works, Benchmark works, Lua can be
packaged, and PTP-based file transfer/deploy has been tested in the local
development workflow.

This is not a polished user release. It is a development repository for people
who understand the risk of running experimental camera-side code.

Relationship to Magic Lantern
-----------------------------

This is not the official Magic Lantern repository.

It is a derived experimental tree based on Magic Lantern, with local changes for
the Canon EOS 750D / Rebel T6i firmware 1.1.0. The original Magic Lantern project
remains the upstream source and conceptual base.

Canon firmware files are not included in this repository. If Canon firmware is
needed for analysis, obtain it independently from Canon or from your own camera
workflow. Do not commit firmware dumps, extracted firmware blocks, generated
build artifacts or files copied from an SD card unless they are intentional
source assets.

Useful local paths in this tree
-------------------------------

- `platform/750D.110/` - EOS 750D / firmware 1.1.0 platform directory.
- `modules/lua/` - Lua module and Lua API bindings.
- `scripts/` - Lua scripts and examples.
- `src/ptp*.c`, `src/ptp*.h` - PTP-related code.
- `tools/ml_ptp_750d.py` - local PTP test/client helper, when present.
- `tools/ml_deploy_750d.py` - local PTP deploy helper, when present.
- `docs/750D_PORT_STATUS.md` - current practical port status.

Original Magic Lantern README
=============================

Magic Lantern
=============

Magic Lantern (ML) is a software enhancement that offers increased
functionality to the excellent Canon DSLR cameras.

It's an open framework, licensed under GPL, for developing extensions to the
official firmware.

Magic Lantern is not a *hack*, or a modified firmware, **it is an
independent program that runs alongside Canon's own software**. 
Each time you start your camera, Magic Lantern is loaded from your memory
card. Our only modification was to enable the ability to run software
from the memory card.

ML is being developed by photo and video enthusiasts, adding
functionality such as: HDR images and video, timelapse, motion
detection, focus assist tools, manual audio controls much more.

For more details on Magic Lantern please see [http://www.magiclantern.fm/](http://www.magiclantern.fm/)

There is a sibling repo for our patched version of Qemu that adds support
for emulating camera ROMs. This allows testing without access to a physical
camera, and automating tests across a suite of cameras.  
https://github.com/reticulatedpines/qemu-eos  
https://github.com/reticulatedpines/qemu-eos/tree/qemu-eos-v4.2.1 (current ML team supported branch)
