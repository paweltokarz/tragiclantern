#!/usr/bin/env python3
"""
Developer helper for Canon EOS 750D / Magic Lantern PTP workflow.

This wraps the minimal 750D CHDK/PTP client and provides repeatable build/deploy
steps for the current 750D.110 port. It is intentionally conservative:
- build output goes to logs,
- deploy verifies files by downloading them back and comparing SHA-256,
- risky remote paths are restricted unless --force is used.
"""

import argparse
import hashlib
import os
import subprocess
import sys
from pathlib import Path

THIS = Path(__file__).resolve()
TOOLS_DIR = THIS.parent
REPO = THIS.parents[1]
PLATFORM_DIR = REPO / "platform" / "750D.110"
BUILD_DIR = PLATFORM_DIR / "build"
ZIP_DIR = BUILD_DIR / "zip"

AUTOEXEC_LOCAL = ZIP_DIR / "autoexec.bin"
SYM_LOCAL = ZIP_DIR / "ML" / "modules" / "750D_110.sym"

AUTOEXEC_REMOTE = "autoexec.bin"
SYM_REMOTE = "ML/modules/750D_110.sym"

DEFAULT_BUILD_LOG = PLATFORM_DIR / "build-ptp-deploy.log"
DEFAULT_CLEAN_LOG = PLATFORM_DIR / "build-ptp-deploy.clean.log"

SAFE_REMOTE_PREFIXES = (
    "ML/scripts/",
    "ML/modules/",
    "ML/LOGS/",
    "ML/data/",
    "ML/doc/",
    "ML/fonts/",
    "ML/cropmks/",
)

SAFE_REMOTE_EXACT = {
    "autoexec.bin",
    "ML/modules/750D_110.sym",
}


sys.path.insert(0, str(TOOLS_DIR))
try:
    from ml_ptp_750d import PTP
except Exception as exc:
    raise SystemExit("ERROR: cannot import tools/ml_ptp_750d.py: %s" % exc)


def rel(path):
    try:
        return str(Path(path).resolve().relative_to(REPO))
    except Exception:
        return str(path)


def run(cmd, cwd=REPO, log_path=None, tail=80):
    print("$ " + " ".join(str(x) for x in cmd))
    if log_path:
        log_path = Path(log_path)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("wb") as log:
            proc = subprocess.run(cmd, cwd=str(cwd), stdout=log, stderr=subprocess.STDOUT)
        rc = proc.returncode
        print("rc=%d log=%s" % (rc, rel(log_path)))
        if rc != 0 or tail:
            print("--- log tail ---")
            data = log_path.read_text(errors="replace").splitlines()
            for line in data[-tail:]:
                print(line)
        if rc != 0:
            raise SystemExit(rc)
        return rc

    proc = subprocess.run(cmd, cwd=str(cwd))
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    return proc.returncode


def sha256_file(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def require_file(path):
    path = Path(path)
    if not path.is_file():
        raise SystemExit("ERROR: missing file: %s" % rel(path))
    return path


def remote_is_safe(remote):
    remote = remote.replace("\\", "/").lstrip("/")
    if remote in SAFE_REMOTE_EXACT:
        return True
    return any(remote.startswith(prefix) for prefix in SAFE_REMOTE_PREFIXES)


def check_remote_safe(remote, force=False):
    remote = remote.replace("\\", "/").lstrip("/")
    if ".." in Path(remote).parts:
        raise SystemExit("ERROR: refusing remote path with '..': %s" % remote)
    if remote.startswith("/"):
        raise SystemExit("ERROR: refusing absolute remote path: %s" % remote)
    if not force and not remote_is_safe(remote):
        raise SystemExit(
            "ERROR: remote path not in safe allowlist: %s\n"
            "Use --force only if you really know the Canon/ML path is safe." % remote
        )
    return remote


def build(args):
    if args.clean:
        run(["make", "-C", str(PLATFORM_DIR.relative_to(REPO)), "clean"], log_path=DEFAULT_CLEAN_LOG, tail=30)

    make_cmd = ["make", "-C", str(PLATFORM_DIR.relative_to(REPO))]
    if args.no_ptp:
        make_cmd += [
            "CONFIG_PTP=n",
            "CONFIG_PTP_CHDK=n",
            "CONFIG_PTP_ML=n",
            "CONFIG_PTP_TEST=n",
            "CONFIG_PTP_NO_AUTO_INIT=n",
            "CONFIG_PTP_MANUAL_MENU=n",
        ]
    run(make_cmd, log_path=DEFAULT_BUILD_LOG, tail=args.tail)

    require_file(AUTOEXEC_LOCAL)
    require_file(SYM_LOCAL)
    print("BUILD_OK")
    print("%s %s" % (sha256_file(AUTOEXEC_LOCAL), rel(AUTOEXEC_LOCAL)))
    print("%s %s" % (sha256_file(SYM_LOCAL), rel(SYM_LOCAL)))


def ptp_info(args):
    with PTP(timeout=args.timeout, verbose=args.verbose):
        print("PTP_OK: Canon EOS 750D CHDK/PTP bridge reachable")


def ptp_put(args):
    local = require_file(args.local)
    remote = check_remote_safe(args.remote, args.force)
    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        n, params = ptp.upload(local, remote)
    print("PUT_OK local=%s remote=%s bytes=%d params=%s" % (local, remote, n, [hex(p) for p in params]))


def ptp_get(args):
    remote = check_remote_safe(args.remote, args.force)
    local = Path(args.local)
    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        n, reported = ptp.download(remote, local)
    print("GET_OK remote=%s local=%s bytes=%d reported=%d" % (remote, local, n, reported))


def deploy(args):
    if args.build:
        build(args)

    autoexec = require_file(AUTOEXEC_LOCAL)
    sym = require_file(SYM_LOCAL)

    expected = {
        AUTOEXEC_REMOTE: (autoexec, sha256_file(autoexec)),
        SYM_REMOTE: (sym, sha256_file(sym)),
    }

    backup_dir = Path(args.backup_dir) if args.backup_dir else Path("/tmp/ml-ptp-deploy-backup")
    backup_dir.mkdir(parents=True, exist_ok=True)

    with PTP(timeout=args.timeout, verbose=args.verbose) as ptp:
        for remote, (local, _digest) in expected.items():
            backup_path = backup_dir / (remote.replace("/", "_") + ".before")
            try:
                n, reported = ptp.download(remote, backup_path)
                print("BACKUP_OK remote=%s local=%s bytes=%d reported=%d sha256=%s" % (
                    remote, backup_path, n, reported, sha256_file(backup_path)
                ))
            except Exception as exc:
                if args.require_backup:
                    raise
                print("BACKUP_WARN remote=%s: %s" % (remote, exc))

        for remote, (local, digest) in expected.items():
            n, params = ptp.upload(local, remote)
            print("PUT_OK local=%s remote=%s bytes=%d sha256=%s params=%s" % (
                rel(local), remote, n, digest, [hex(p) for p in params]
            ))

        verify_dir = Path(args.verify_dir) if args.verify_dir else Path("/tmp/ml-ptp-deploy-verify")
        verify_dir.mkdir(parents=True, exist_ok=True)

        ok = True
        for remote, (local, digest) in expected.items():
            downloaded = verify_dir / (remote.replace("/", "_") + ".downloaded")
            n, reported = ptp.download(remote, downloaded)
            got = sha256_file(downloaded)
            same = got == digest
            ok = ok and same
            print("VERIFY_%s remote=%s local=%s bytes=%d reported=%d sha256=%s expected=%s" % (
                "OK" if same else "FAIL", remote, downloaded, n, reported, got, digest
            ))

    if not ok:
        raise SystemExit("ERROR: deploy verification failed")

    print("DEPLOY_OK: autoexec.bin and 750D_110.sym uploaded and verified")


def main():
    ap = argparse.ArgumentParser(description="Build/deploy helper for ML Canon EOS 750D over experimental PTP.")
    ap.add_argument("--timeout", type=int, default=5000)
    ap.add_argument("-v", "--verbose", action="store_true")

    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("build", help="build platform/750D.110")
    p.add_argument("--clean", action="store_true", help="run make clean first")
    p.add_argument("--no-ptp", action="store_true", help="build with PTP disabled")
    p.add_argument("--tail", type=int, default=80)
    p.set_defaults(func=build)

    p = sub.add_parser("info", help="check whether camera PTP bridge responds")
    p.set_defaults(func=ptp_info)

    p = sub.add_parser("put", help="upload a file to the card over PTP")
    p.add_argument("local")
    p.add_argument("remote")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=ptp_put)

    p = sub.add_parser("get", help="download a file from the card over PTP")
    p.add_argument("remote")
    p.add_argument("local")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=ptp_get)

    p = sub.add_parser("deploy", help="upload current build autoexec.bin + 750D_110.sym and verify")
    p.add_argument("--build", action="store_true", help="build before deploying")
    p.add_argument("--clean", action="store_true", help="with --build, run make clean first")
    p.add_argument("--no-ptp", action="store_true", help="with --build, build with PTP disabled")
    p.add_argument("--tail", type=int, default=80)
    p.add_argument("--backup-dir")
    p.add_argument("--verify-dir")
    p.add_argument("--require-backup", action="store_true")
    p.set_defaults(func=deploy)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
