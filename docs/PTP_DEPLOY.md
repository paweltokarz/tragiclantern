# PTP deploy workflow for EOS 750D

This document describes the local PTP-based development workflow used by Tragic Lantern for the Canon EOS 750D / Rebel T6i firmware 1.1.0 port.

The goal is simple: reduce SD-card removal during development. Build locally, talk to the camera over USB/PTP, upload selected files, download them back, and verify hashes.

## Status

Experimental, but tested on real EOS 750D hardware in the local development workflow.

The current PTP path has been used for:

- detecting the camera over USB/PTP;
- CHDK-style PTP operation support;
- querying version/info;
- reading camera memory for diagnostics;
- uploading files to the card;
- downloading files from the card;
- byte-for-byte verification after upload;
- deploying `autoexec.bin` and selected Magic Lantern files;
- backing up selected files before deploy.

This is still hardware-facing code. Treat every deploy as potentially risky.

## Expected tools

The local workflow expects these helper scripts when present:

- `tools/ml_ptp_750d.py`
- `tools/ml_deploy_750d.py`

`ml_ptp_750d.py` is the lower-level PTP client/helper.

Typical operations:

```sh
python3 tools/ml_ptp_750d.py info
python3 tools/ml_ptp_750d.py put local_file.bin remote/path/file.bin
python3 tools/ml_ptp_750d.py get remote/path/file.bin local_file.bin
python3 tools/ml_ptp_750d.py getmem ADDRESS SIZE output.bin
```

`ml_deploy_750d.py` is the higher-level development deploy helper.

Typical operations:

```sh
python3 tools/ml_deploy_750d.py info
python3 tools/ml_deploy_750d.py build
python3 tools/ml_deploy_750d.py deploy --build
python3 tools/ml_deploy_750d.py put local_file.lua ML/scripts/local_file.lua
python3 tools/ml_deploy_750d.py get ML/scripts/local_file.lua local_file.lua
```

## Typical deploy

The usual development deploy command is:

```sh
python3 tools/ml_deploy_750d.py deploy --build
```

Expected behavior:

1. Build the EOS 750D target.
2. Prepare the deployable package.
3. Connect to the camera over PTP.
4. Back up selected files from the camera/card.
5. Upload new build artifacts.
6. Download uploaded files back from the camera/card.
7. Compare SHA256 hashes.
8. Report success or failure.

The important point is not only that files are uploaded, but that the uploaded files are downloaded back and verified byte-for-byte.

## Camera-side requirements

Before using PTP deploy:

- camera must be powered on;
- Magic Lantern must be running;
- USB must be connected;
- the camera must expose the expected PTP interface;
- no desktop process should be blocking the camera.

KDE/Dolphin, gphoto, GVFS or other desktop automount/photo tools may interfere with the camera interface.

If PTP access fails, check for processes holding the device before assuming the Magic Lantern side is broken.

## Files commonly deployed

Common deploy targets include:

- root `autoexec.bin`;
- `ML/modules/750D_110.sym`;
- selected modules under `ML/modules/`;
- Lua scripts under `ML/scripts/`.

Replacing root `autoexec.bin` is the riskiest common operation. The helper may verify hashes, but a verified bad build is still a bad build.

## Lua script deploy examples

Upload a Lua script:

```sh
python3 tools/ml_deploy_750d.py put scripts/example.lua ML/scripts/example.lua
```

Download it back for verification or inspection:

```sh
python3 tools/ml_deploy_750d.py get ML/scripts/example.lua /tmp/example.lua
```

## Troubleshooting

### Permission denied over SSH while pushing this repository

That is unrelated to PTP. It means GitHub SSH authentication is not configured.

### Camera visible to desktop but PTP helper fails

The desktop may have captured the device. Close file managers/photo importers and check whether gphoto/GVFS/KDE services are holding the camera.

### PTP worked before restart but not after

Check:

- USB cable and camera power;
- whether Magic Lantern is actually running;
- whether the camera is in a mode where the PTP handler is active;
- whether a desktop process grabbed the interface;
- whether the current build still includes the PTP configuration.

### Upload succeeds but camera behaves badly

Assume the uploaded build or script is bad. Restore the previous known-good files from backup, preferably using the deploy helper if PTP still works. Otherwise fall back to direct card access.

## Safety policy

Do not treat PTP deploy as a normal desktop copy operation.

Risky actions:

- replacing root `autoexec.bin`;
- replacing or adding modules;
- changing `750D_110.sym`;
- uploading scripts that alter shooting, exposure, properties or eventprocs;
- deploying after platform/stub changes;
- deploying untested build artifacts.

Safer workflow:

1. Keep the last known-good build.
2. Back up current camera/card files before overwriting them.
3. Upload only what is needed.
4. Download back and verify hashes.
5. Test one functional change at a time.
6. If the camera becomes unstable, revert before adding more changes.

## Repository policy

Do not commit or publish:

- Canon firmware files;
- extracted firmware blocks;
- generated `autoexec.bin`;
- generated `*.sym`;
- generated build directories;
- local PTP backup directories;
- private camera/card dumps.

Commit only source code, scripts and documentation required to reproduce the workflow.
