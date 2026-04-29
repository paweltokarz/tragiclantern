# Experimental PTP file transfer for Canon EOS 750D / 1.1.0

This port includes experimental Magic Lantern / CHDK-style PTP support for the Canon EOS 750D running Canon firmware 1.1.0.

The current implementation is intended mainly as a development aid. It allows a Linux host to communicate with Magic Lantern over USB and transfer files to and from the camera card without removing the SD card. The most useful workflow is rebuilding Magic Lantern locally and deploying `autoexec.bin` plus `ML/modules/750D_110.sym` over USB.

This is not a general-purpose Canon remote-control implementation. It is a small, practical bridge for development on this specific camera/firmware combination.

## Current status

Verified on a real Canon EOS 750D / firmware 1.1.0:

- the camera exposes Canon PTP over USB;
- the CHDK-style operation code `0x9999` is visible in the camera PTP operation list;
- CHDK PTP `Version` works;
- CHDK PTP `GetMemory` works;
- CHDK PTP `UploadFile` works;
- CHDK PTP `DownloadFile` works;
- upload/download of small text files works;
- upload/download of 4 KiB and 64 KiB binary files works byte-for-byte;
- upload/download of an `autoexec.bin`-sized binary works byte-for-byte;
- practical deploy of `autoexec.bin` and `ML/modules/750D_110.sym` over USB works with backup and verification.

The helper script has successfully performed this workflow:

1. build `platform/750D.110`;
2. back up the current card-side `autoexec.bin`;
3. back up the current card-side `ML/modules/750D_110.sym`;
4. upload the newly built `autoexec.bin`;
5. upload the newly built `750D_110.sym`;
6. download both files back from the camera;
7. verify SHA256 checksums against the local build artifacts.

## Important warning

This is experimental 750D-specific development code.

Writing `autoexec.bin` over PTP changes the executable boot file on the camera card. A bad build, incomplete transfer, wrong file, wrong path, or unstable camera state may leave the card unable to boot Magic Lantern until restored manually.

Before relying on this workflow:

- keep a known-good backup of the card;
- keep a known-good `autoexec.bin`;
- keep a known-good `ML/modules/750D_110.sym`;
- test with harmless files first;
- only deploy root `autoexec.bin` when you are prepared to recover by removing the SD card.

## Requirements on the host

The Python tools require:

- Linux;
- Python 3;
- PyUSB;
- libusb access to the Canon USB device;
- a connected Canon EOS 750D running this Magic Lantern build.

On Debian/Ubuntu-like systems the required Python USB package is typically:

```sh
sudo apt install python3-usb
```

The camera must not be held by another program. Close file managers, camera import tools, and other PTP/GPhoto frontends if the tool cannot claim the USB interface.

Useful checks:

```sh
lsusb | grep -Ei 'canon|04a9'
gphoto2 --auto-detect
```

The camera usually appears as vendor/product:

```text
04a9:32a1 Canon, Inc. Canon Digital Camera
```

## Camera-side build configuration

The 750D platform build enables PTP in:

```text
platform/750D.110/Makefile
```

The relevant configuration is:

```make
CONFIG_PTP = y
CONFIG_PTP_CHDK = y
CONFIG_PTP_ML = y
CONFIG_PTP_NO_AUTO_INIT = y
CONFIG_PTP_MANUAL_MENU = y
```

The port uses a 750D-specific PTP operation-list registration path in `src/ptp.c`. The camera firmware wrapper symbol used for PTP registration is documented in:

```text
platform/750D.110/stubs.S
```

The implementation manually registers Magic Lantern PTP handlers into the Canon PTP operation list after the Canon PTP list is available. This avoids calling the Canon registration wrapper too early from normal ML init.

A Debug menu entry is also available:


```text
Debug -> PTP register
```

It can be used as a manual retry/diagnostic for handler registration.

## Host-side tools

Two tools are provided.

### Low-level client


```text
tools/ml_ptp_750d.py
```

This is a small PTP client for direct operations:

- `info`
- `put`
- `get`
- `getmem`

Examples:

```sh
python3 tools/ml_ptp_750d.py info
```

Upload a file to the camera card:

```sh
python3 tools/ml_ptp_750d.py put local_file.txt ML/LOGS/local_file.txt
```

Download a file from the camera card:

```sh
python3 tools/ml_ptp_750d.py get ML/LOGS/local_file.txt /tmp/local_file.from_camera.txt
```

Read memory through CHDK PTP `GetMemory`:


```sh
python3 tools/ml_ptp_750d.py getmem 0xFE0A0000 64 > /tmp/rom_start.bin
```

Use verbose mode for debugging the USB/PTP exchange:

```sh
python3 tools/ml_ptp_750d.py -v info
```

Increase timeout if needed:

```sh
python3 tools/ml_ptp_750d.py --timeout 8000 info
```

### Deploy helper

```text
tools/ml_deploy_750d.py
```

This is the practical development helper. It wraps build, backup, upload, download, and checksum verification.

Show help:

```sh
python3 tools/ml_deploy_750d.py --help
python3 tools/ml_deploy_750d.py deploy --help
```

Build the 750D platform:


```sh
python3 tools/ml_deploy_750d.py build
```

Build with clean first:


```sh
python3 tools/ml_deploy_750d.py build --clean
```

Check whether the camera PTP bridge is reachable:

```sh
python3 tools/ml_deploy_750d.py info
```

Upload one arbitrary file:

```sh
python3 tools/ml_deploy_750d.py put local_file.txt ML/LOGS/local_file.txt
```

Download one arbitrary file:


```sh
python3 tools/ml_deploy_750d.py get ML/LOGS/local_file.txt /tmp/local_file.txt
```

Deploy current build artifacts without rebuilding:

```sh
python3 tools/ml_deploy_750d.py deploy
```

Build and deploy in one command:

```sh
python3 tools/ml_deploy_750d.py deploy --build
```

Clean, build, deploy, back up old files, download new files back, and verify checksums:

```sh
python3 tools/ml_deploy_750d.py --timeout 8000 deploy --build --clean
```

The deploy command targets exactly:


```text
platform/750D.110/build/zip/autoexec.bin
platform/750D.110/build/zip/ML/modules/750D_110.sym
```

and uploads them to:


```text
autoexec.bin
ML/modules/750D_110.sym
```

## Recommended development workflow

For normal development:

1. boot the camera with a known-good PTP-enabled Magic Lantern build;
2. connect the camera by USB;
3. verify the bridge:

   ```sh
   python3 tools/ml_deploy_750d.py info
   ```

4. build and deploy:

   ```sh
   python3 tools/ml_deploy_750d.py --timeout 8000 deploy --build
   ```

5. power-cycle the camera manually to boot the newly deployed `autoexec.bin`.

At this stage, automatic camera reboot over PTP is not part of the confirmed workflow. Manual restart is still expected after replacing `autoexec.bin`.

## Safer file-transfer tests

Before deploying boot files, test transfer with harmless files:

```sh
printf "PTP test\n" > /tmp/ptp_test.txt
python3 tools/ml_ptp_750d.py put /tmp/ptp_test.txt ML/LOGS/PTP_TEST.TXT
python3 tools/ml_ptp_750d.py get ML/LOGS/PTP_TEST.TXT /tmp/ptp_test.readback.txt
cmp /tmp/ptp_test.txt /tmp/ptp_test.readback.txt
```

Binary test:

```sh
python3 - <<'PY'
from pathlib import Path
Path("/tmp/ml-ptp-64k.bin").write_bytes(bytes([(i * 7 + 3) % 256 for i in range(65536)]))
PY

python3 tools/ml_ptp_750d.py put /tmp/ml-ptp-64k.bin ML/LOGS/PTP64K.BIN
python3 tools/ml_ptp_750d.py get ML/LOGS/PTP64K.BIN /tmp/ml-ptp-64k.down.bin
cmp /tmp/ml-ptp-64k.bin /tmp/ml-ptp-64k.down.bin
```

## Troubleshooting

### The tool cannot find the camera

Check USB visibility:


```sh
lsusb | grep -Ei 'canon|04a9'
gphoto2 --auto-detect
```

The camera should appear as Canon EOS 750D.

### The tool cannot claim the USB interface

Close programs that may hold the camera:

- Dolphin / KDE amera view;
- GVFS / GPhoto importers;
- other PTP/MTP tools;
- file manager windows showing the camera.

Then reconnect the camera or power-cycle it.

### `info` works but upload/download fails

Try a small harmless file first. If small files work but larger transfers fail, increase timeout:


```sh
python3 tools/ml_ptp_750d.py --timeout 10000 put local.bin ML/LOGS/local.bin
```

### Deploy succeeds but camera does not boot after restart

Recover manually by mounting the SD card on the host and restoring the previous known-good files:

```text
autoexec.bin
ML/modules/750D_110.sym
```

The deploy helper stores backups when running `deploy`, unless explicitly configured otherwise. Keep independent backups anyway.

## Notes for contributors

This PTP support is currently tied to:


```text
Canon EOS 750D
Canon firmware 1.1.0
Magic Lantern platform directory: platform/750D.110
```

Do not assume the PTP operation-list root address, node layout, or registration path applies to other cameras.

The feature is useful enough for active development, but should still be treated as experimental when publishing builds for other users.
