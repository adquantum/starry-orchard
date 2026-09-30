"""Supervise the private progression ledger and the Godot island server.

This owns process lifecycle only.  Economy and identity logic remain in
progression_service.py / progression_ledger.py.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request
from contextlib import closing
from pathlib import Path


class Child:
    def __init__(self, name, command, env, marker=""):
        self.name = name
        self.marker = marker
        self.ready = threading.Event()
        self.process = subprocess.Popen(
            command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
        )
        self.reader = threading.Thread(target=self._copy_output, daemon=True)
        self.reader.start()

    def _copy_output(self):
        for line in iter(self.process.stdout.readline, ""):
            print("[%s] %s" % (self.name, line), end="", flush=True)
            if self.marker and self.marker in line:
                self.ready.set()


def stop_children(children):
    for child in reversed(children):
        if child.process.poll() is None:
            child.process.terminate()
    # The existing updater gives the container 25 seconds after SIGTERM. Leave
    # most of that window for the consistent SQLite/outbox backup below.
    deadline = time.monotonic() + 8
    for child in children:
        remaining = max(0.0, deadline - time.monotonic())
        try:
            child.process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            child.process.kill()
            child.process.wait()
        if child.process.stdout is not None:
            child.process.stdout.close()
        child.reader.join(timeout=1)


def ledger_ready(url):
    try:
        with urllib.request.urlopen(url.rstrip("/") + "/health", timeout=0.25) as response:
            value = json.load(response)
        return value.get("service") == "game-progression" and value.get("version") == 1 and value.get("ready") is True
    except (OSError, ValueError):
        return False


def persistent_value(path, supplied, token_bytes, supplied_pattern=None):
    if supplied:
        if supplied_pattern is not None and not re.fullmatch(supplied_pattern, supplied):
            raise RuntimeError("Invalid supplied persistent identity: " + path.name)
        return supplied
    try:
        value = path.read_text(encoding="ascii").strip()
    except FileNotFoundError:
        value = secrets.token_hex(token_bytes)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        descriptor = os.open(str(path), flags, 0o600)
        with os.fdopen(descriptor, "w", encoding="ascii", newline="\n") as target:
            target.write(value + "\n")
    if not re.fullmatch(r"[0-9a-f]{%d}" % (token_bytes * 2), value):
        raise RuntimeError("Invalid persistent identity file: " + str(path))
    return value


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def backup_game_data(data):
    database = data / "progression.sqlite3"
    if not database.is_file():
        return None
    backup_root = data / "backups"
    backup_root.mkdir(exist_ok=True)
    identity = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(4)
    temporary = backup_root / ("." + identity + ".part")
    final = backup_root / identity
    temporary.mkdir()
    try:
        saved_database = temporary / "progression.sqlite3"
        with closing(sqlite3.connect("file:" + database.as_posix() + "?mode=ro", uri=True, timeout=10)) as source:
            with closing(sqlite3.connect(str(saved_database))) as target:
                source.backup(target)
                if target.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                    raise RuntimeError("Game ledger backup integrity check failed")
        outbox = data / "outbox"
        if outbox.exists():
            if outbox.is_symlink() or any(path.is_symlink() for path in outbox.rglob("*")):
                raise RuntimeError("Refusing to back up an outbox containing symlinks")
            shutil.copytree(outbox, temporary / "outbox")
        files = sorted(path for path in temporary.rglob("*") if path.is_file())
        manifest = {path.relative_to(temporary).as_posix(): file_sha256(path) for path in files}
        (temporary / "backup-manifest.json").write_text(json.dumps({
            "schema_version": 1,
            "created_utc": identity.split("-")[0],
            "files": manifest,
        }, indent=2) + "\n", encoding="utf-8")
        os.replace(str(temporary), str(final))
        print("GAME_DATA_BACKUP " + str(final), flush=True)
        return final
    except Exception:
        if temporary.exists():
            shutil.rmtree(temporary)
        raise


def wait_for_ledger(child, url, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if child.process.poll() is not None:
            raise RuntimeError("Progression ledger exited during startup: %s" % child.process.returncode)
        if ledger_ready(url):
            return
        time.sleep(0.1)
    raise RuntimeError("Progression ledger health timed out")


def wait_for_island(ledger, island, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if ledger.process.poll() is not None:
            raise RuntimeError("Progression ledger exited before island readiness")
        if island.process.poll() is not None:
            raise RuntimeError("Godot island server exited during startup: %s" % island.process.returncode)
        if island.ready.wait(0.1):
            return
    raise RuntimeError("Godot island readiness timed out")


def supervise(ledger_command, godot_command, env, health_url, startup_timeout=40, backup_data=None):
    children = []
    stopping = threading.Event()

    def request_stop(_signum=None, _frame=None):
        stopping.set()

    old_handlers = {}
    for name in ("SIGINT", "SIGTERM"):
        value = getattr(signal, name, None)
        if value is not None:
            old_handlers[value] = signal.signal(value, request_stop)
    try:
        ledger = Child("ledger", ledger_command, env)
        children.append(ledger)
        wait_for_ledger(ledger, health_url, startup_timeout)
        island = Child("island", godot_command, env, "ISLAND_SERVER_READY")
        children.append(island)
        wait_for_island(ledger, island, startup_timeout)
        print("GAME_SERVER_STACK_READY", flush=True)
        while not stopping.wait(0.25):
            for child in children:
                code = child.process.poll()
                if code is not None:
                    raise RuntimeError("Required %s process exited: %s" % (child.name, code))
        return 0
    finally:
        stop_children(children)
        if backup_data is not None:
            backup_game_data(backup_data)
        for value, handler in old_handlers.items():
            signal.signal(value, handler)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT_BIN", "godot"))
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--ledger-script", type=Path, required=True)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--ledger-port", type=int, default=18787)
    parser.add_argument("--game-port", type=int, default=29710)
    parser.add_argument("--startup-timeout", type=float, default=40)
    args = parser.parse_args()
    project = args.project.resolve()
    script = args.ledger_script.resolve()
    data = args.data.resolve()
    if not project.joinpath("project.godot").is_file():
        parser.error("Island project is missing project.godot")
    if not script.is_file():
        parser.error("Progression service script is missing")
    if not args.data.is_absolute():
        parser.error("--data must be an absolute persistent path")
    data.mkdir(parents=True, exist_ok=True)
    try:
        data.chmod(0o700)
    except OSError:
        pass
    env = os.environ.copy()
    missing = [name for name in ("LEGACY_ACCOUNT_SERVER_URL",) if not env.get(name)]
    if missing:
        parser.error("Missing required game setting(s): " + ", ".join(missing))
    env["ACADEMY_SERVICE_KEY"] = persistent_value(
        data / "service.key", env.get("ACADEMY_SERVICE_KEY", ""), 32, r"[^\x00\r\n]{16,256}",
    )
    env["ISLAND_SERVER_ID"] = persistent_value(
        data / "server.id", env.get("ISLAND_SERVER_ID", ""), 16, r"[A-Za-z0-9._:-]{1,128}",
    )
    outbox = data / "outbox"
    outbox.mkdir(exist_ok=True)
    health_url = "http://127.0.0.1:%d" % args.ledger_port
    env.update({
        "GAME_DATA_DIR": str(data),
        "GAME_PROGRESSION_URL": health_url,
        "ISLAND_PROGRESSION_DIR": str(outbox),
    })
    ledger_command = [sys.executable, str(script), "--host", "127.0.0.1", "--port", str(args.ledger_port)]
    godot_command = [args.godot, "--headless", "--path", str(project), "--", "--port=" + str(args.game_port)]
    return supervise(ledger_command, godot_command, env, health_url, args.startup_timeout, data)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print("GAME_SERVER_STACK_FAILED: " + str(error), file=sys.stderr, flush=True)
        raise SystemExit(1)
