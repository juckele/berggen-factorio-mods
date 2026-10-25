#!/usr/bin/env python3
"""Run Factorio headless test scenarios, or inspect a save's mod state over RCON.

  tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json
  tools/headless/headless.py test tests/vulcanus-demolisher-lifecycle/tests.json --scenario new-game -v
  tools/headless/headless.py inspect tests/vulcanus-demolisher-lifecycle/tests.json --save some.zip \
      --mods vulcanus-demolisher-lifecycle --context vulcanus-demolisher-lifecycle \
      --lua 'rcon.print(serpent.block(storage))'

Python 3.9+, standard library only. See tools/headless/README.md for the spec format.
"""

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rcon import Rcon  # noqa: E402

HERE = Path(__file__).resolve().parent
HARNESS_MOD = HERE / "headless-test-harness"
BUILTIN_MODS = ["base", "space-age", "quality", "elevated-rails", "recycler"]
TEST_LINE = re.compile(r"^TEST (PASS|FAIL|INFO|DONE) (\S+)(?: :: (.*))?$")
ERROR_LINE = re.compile(r"^\s*\d+\.\d+ (Error|Failed)|Error while running|Error in assignID|script error", re.I)


# --------------------------------------------------------------------------------------------------
# Locating Factorio


def find_factorio(version):
    """FACTORIO_BIN wins; otherwise <home>/<version>/factorio/bin/x64/factorio under FACTORIO_HOME,
    ~/factorio or /home/claude/factorio."""
    env = os.environ.get("FACTORIO_BIN")
    if env:
        return Path(env)
    homes = [os.environ.get("FACTORIO_HOME"), Path.home() / "factorio", "/home/claude/factorio"]
    for home in homes:
        if not home:
            continue
        home = Path(home)
        candidates = sorted(home.glob(f"{version}*/factorio/bin/x64/factorio"), reverse=True)
        if candidates:
            return candidates[0]
    sys.exit(f"Can't find Factorio {version}: set FACTORIO_BIN or FACTORIO_HOME")


def game_version(binary):
    out = subprocess.run([str(binary), "--version"], capture_output=True, text=True).stdout
    match = re.search(r"Version: (\d+)\.(\d+)\.(\d+)", out)
    if not match:
        sys.exit(f"Can't read the version of {binary}")
    return tuple(int(x) for x in match.groups())


# --------------------------------------------------------------------------------------------------
# Building a run directory


class RunDir:
    """An isolated write-data directory, mod directory and config for one Factorio invocation."""

    def __init__(self, root, binary, version, spec, mods, scenario, phase, params, settings):
        self.root = Path(root)
        self.binary = binary
        self.mods_dir = self.root / "mods"
        self.write_dir = self.root / "write"
        if self.root.exists():
            shutil.rmtree(self.root)
        self.mods_dir.mkdir(parents=True)
        self.write_dir.mkdir()
        self.config = self.root / "config.ini"
        read_data = Path(binary).resolve().parents[2] / "data"
        self.config.write_text(f"[path]\nread-data={read_data}\nwrite-data={self.write_dir}\n")
        factorio_version = f"{version[0]}.{version[1]}"

        enabled = set(spec.get("builtin_mods", BUILTIN_MODS)) | {"base"}
        mod_list = [{"name": m, "enabled": m in enabled} for m in BUILTIN_MODS]

        def add(name, source, retarget=False):
            dest = self.mods_dir / name
            shutil.copytree(source, dest, ignore=shutil.ignore_patterns(".git", "*.zip"))
            if retarget:
                info_path = dest / "info.json"
                info = json.loads(info_path.read_text())
                info["factorio_version"] = factorio_version
                info_path.write_text(json.dumps(info, indent=2))
            mod_list.append({"name": name, "enabled": True})

        for name in mods:
            add(name, spec["_mod_paths"][name])
        add("headless-test-harness", HARNESS_MOD, retarget=True)
        self._write_config_mod(factorio_version, scenario, phase, params, settings)
        mod_list.append({"name": "headless-test-config", "enabled": True})
        (self.mods_dir / "mod-list.json").write_text(json.dumps({"mods": mod_list}, indent=2))

    def _write_config_mod(self, factorio_version, scenario, phase, params, settings):
        d = self.mods_dir / "headless-test-config"
        d.mkdir()
        (d / "info.json").write_text(json.dumps({
            "name": "headless-test-config", "version": "1.0.0", "title": "Headless test config",
            "author": "tools/headless", "factorio_version": factorio_version,
            "dependencies": ["base"],
        }, indent=2))
        config = {"scenario": scenario, "phase": phase, "params": params or {}}
        (d / "config.lua").write_text("return " + lua_literal(config) + "\n")
        # Setting overrides change the setting's default (not forced_value, which would lock it).
        # Runtime-global values are stored in the save when the owning mod is first added, so the
        # override takes effect on the step that adds the mod; change it later over RCON.
        lines = []
        for name, value in (settings or {}).items():
            lines.append(
                "for _, kind in pairs({'bool-setting','int-setting','double-setting','string-setting'}) do\n"
                f"  local s = data.raw[kind] and data.raw[kind][{lua_literal(name)}]\n"
                f"  if s then s.default_value = {lua_literal(value)} end\n"
                "end")
        (d / "settings-final-fixes.lua").write_text("\n".join(lines) + "\n")

    def base_args(self):
        return [str(self.binary), "--config", str(self.config), "--mod-directory", str(self.mods_dir)]


def lua_literal(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{" + ", ".join(lua_literal(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{json.dumps(str(k))}] = {lua_literal(v)}" for k, v in value.items()) + "}"
    raise TypeError(f"Can't convert {value!r} to Lua")


# --------------------------------------------------------------------------------------------------
# Running Factorio


def run_process(args, log_path, timeout):
    with open(log_path, "w") as log:
        proc = subprocess.run(args, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    return proc.returncode, Path(log_path).read_text(errors="replace")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Server:
    """A headless server on a save, driven over RCON. Output is collected into a log file."""

    def __init__(self, run_dir, save, log_path):
        self.port = free_port()
        self.rcon_port = free_port()
        self.password = "headless"
        settings_path = run_dir.root / "server-settings.json"
        # Start from the game's example so every required key is present.
        example = Path(run_dir.binary).resolve().parents[2] / "data" / "server-settings.example.json"
        server_settings = json.loads(example.read_text())
        server_settings.update({
            "name": "headless test", "description": "", "visibility": {"public": False, "lan": False},
            "require_user_verification": False, "auto_pause": False, "autosave_interval": 0,
            "autosave_slots": 0,
        })
        settings_path.write_text(json.dumps(server_settings))
        args = run_dir.base_args() + [
            "--start-server", str(save), "--server-settings", str(settings_path),
            "--port", str(self.port), "--bind", "127.0.0.1",
            "--rcon-bind", f"127.0.0.1:{self.rcon_port}",
            "--rcon-password", self.password,
        ]
        self.log = open(log_path, "w")
        # Keep stdin open: the server treats EOF on stdin as an error and stops reading console input.
        self.proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=self.log, stderr=subprocess.STDOUT)
        self.rcon = None
        self.tick_ready = False
        deadline = time.time() + 180
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"Server exited early, see {log_path}")
            try:
                self.rcon = Rcon("127.0.0.1", self.rcon_port, self.password)
                break
            except OSError:
                time.sleep(0.5)
        if not self.rcon:
            self.stop()
            raise RuntimeError(f"Server never accepted RCON, see {log_path}")

    def lua(self, code, context=None):
        prefix = f"/sc __{context}__ " if context else "/sc "
        return self.rcon.command(prefix + code)

    def tick(self):
        # Right after RCON comes up the map may still be loading, and commands print nothing.
        deadline = time.time() + 120
        while True:
            out = self.lua("rcon.print(game.tick)").strip()
            if out.isdigit():
                return int(out)
            if time.time() > deadline:
                raise RuntimeError(f"Server never reported a tick (got {out!r})")
            time.sleep(0.5)

    def wait_ticks(self, ticks):
        target = self.tick() + ticks
        while self.tick() < target:
            time.sleep(0.05)

    def save(self):
        self.rcon.command("/server-save")
        time.sleep(1)  # the save is written asynchronously after the command returns

    def stop(self):
        try:
            if self.rcon:
                self.rcon.command("/quit")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.log.close()


# --------------------------------------------------------------------------------------------------
# Scenarios


class StepResult:
    def __init__(self, name):
        self.name = name
        self.passes, self.fails, self.infos, self.errors = [], [], [], []
        self.done = False

    def parse(self, output):
        for line in output.splitlines():
            m = TEST_LINE.match(line.strip())
            if m:
                kind, name, detail = m.groups()
                if kind == "PASS":
                    self.passes.append((name, detail))
                elif kind == "FAIL":
                    self.fails.append((name, detail))
                elif kind == "INFO":
                    self.infos.append((name, detail))
                elif kind == "DONE":
                    self.done = True
            elif ERROR_LINE.search(line):
                self.errors.append(line.strip())

    @property
    def ok(self):
        return not self.fails and not self.errors


def load_spec(path):
    path = Path(path).resolve()
    spec = json.loads(path.read_text())
    spec["_dir"] = path.parent
    spec["_mod_paths"] = {name: (path.parent / p).resolve() for name, p in spec["mod_paths"].items()}
    return spec


def run_scenario(spec, scenario, binary, version, work, verbose):
    name = scenario["name"]
    scenario_dir = Path(work) / name
    if scenario_dir.exists():
        shutil.rmtree(scenario_dir)
    scenario_dir.mkdir(parents=True)
    save = scenario_dir / "save.zip"
    if "save" in scenario:
        shutil.copy(spec["_dir"] / scenario["save"], save)
    settings = scenario.get("settings", {})
    timeout = spec.get("timeout", 900)
    results = []

    for index, step in enumerate(scenario["steps"]):
        phase = step.get("phase", f"step{index + 1}")
        result = StepResult(phase)
        results.append(result)
        run_dir = RunDir(scenario_dir / f"run-{index + 1}", binary, version, spec, step["mods"], name, phase,
                         {**scenario.get("params", {}), **step.get("params", {})},
                         {**settings, **step.get("settings", {})})
        log_path = scenario_dir / f"{index + 1}-{phase}.log"
        if "create" in step:
            args = run_dir.base_args() + ["--create", str(save)]
            create = step["create"] or {}
            if "seed" in create:
                args += ["--map-gen-seed", str(create["seed"])]
            for key, flag in (("map_gen_settings", "--map-gen-settings"), ("map_settings", "--map-settings")):
                if key in create:
                    args += [flag, str(spec["_dir"] / create[key])]
            code, output = run_process(args, log_path, timeout)
        elif "benchmark" in step:
            args = run_dir.base_args() + ["--benchmark", str(save), "--benchmark-ticks", str(step["benchmark"])]
            code, output = run_process(args, log_path, timeout)
        elif "server" in step:
            code, output = run_server_step(run_dir, save, step["server"], log_path, result)
        else:
            sys.exit(f"{name}: step {index + 1} has no create/benchmark/server action")

        result.parse(output)
        if code != 0:
            result.errors.append(f"Factorio exited with code {code}, see {log_path}")
        if step.get("expect_done") and not result.done:
            result.fails.append(("phase-finished", "the test mod never called H.done()"))
        print_step(name, result, log_path, verbose)
        if not result.ok:
            break
    return all(r.ok for r in results)


def run_server_step(run_dir, save, server_spec, log_path, result):
    server = Server(run_dir, save, log_path)
    try:
        start = server.tick()
        for action in server_spec.get("actions", []):
            if "wait" in action:
                server.wait_ticks(action["wait"])
            if "lua" in action:
                out = server.lua(action["lua"], action.get("context"))
                if "expect" in action:
                    ok = re.search(action["expect"], out) is not None
                    (result.passes if ok else result.fails).append(
                        (action.get("name", "rcon"), f"expected /{action['expect']}/, got {out.strip()!r}"))
        if server_spec.get("save", True):
            server.save()
        result.infos.append(("server-ticks", str(server.tick() - start)))
    finally:
        server.stop()
    return server.proc.returncode or 0, Path(log_path).read_text(errors="replace")


def print_step(scenario, result, log_path, verbose):
    status = "ok" if result.ok else "FAILED"
    print(f"  {scenario} / {result.name}: {status} ({len(result.passes)} passed, {len(result.fails)} failed)")
    if verbose:
        for name, detail in result.passes:
            print(f"      pass {name}" + (f" :: {detail}" if detail else ""))
        for name, detail in result.infos:
            print(f"      info {name} :: {detail}")
    for name, detail in result.fails:
        print(f"      FAIL {name} :: {detail}")
    for line in result.errors[:10]:
        print(f"      ERROR {line}")
    if not result.ok:
        print(f"      log: {log_path}")


def cmd_test(args):
    spec = load_spec(args.spec)
    binary = find_factorio(spec.get("factorio", ""))
    version = game_version(binary)
    work = Path(args.work or tempfile.mkdtemp(prefix="headless-"))
    print(f"Factorio {'.'.join(map(str, version))} ({binary}), work dir {work}")
    selected = [s for s in spec["scenarios"] if not args.scenario or s["name"] in args.scenario]
    if not selected:
        sys.exit("No matching scenarios")
    failures = []
    for scenario in selected:
        print(f"{scenario['name']}: {scenario.get('description', '')}")
        if not run_scenario(spec, scenario, binary, version, work, args.verbose):
            failures.append(scenario["name"])
    print()
    if failures:
        print(f"{len(failures)} of {len(selected)} scenarios failed: {', '.join(failures)}")
        return 1
    print(f"All {len(selected)} scenarios passed")
    return 0


def cmd_inspect(args):
    spec = load_spec(args.spec)
    binary = find_factorio(spec.get("factorio", ""))
    version = game_version(binary)
    work = Path(tempfile.mkdtemp(prefix="headless-inspect-"))
    save = work / "save.zip"
    shutil.copy(args.save, save)  # never touch the original
    mods = [m for m in (args.mods or "").split(",") if m]
    run_dir = RunDir(work / "run", binary, version, spec, mods, "inspect", "inspect", {}, {})
    server = Server(run_dir, save, work / "server.log")
    try:
        if args.ticks:
            server.wait_ticks(args.ticks)
        for code in args.lua:
            print(server.lua(code, args.context))
    finally:
        server.stop()
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    t = sub.add_parser("test", help="run the scenarios in a test spec")
    t.add_argument("spec")
    t.add_argument("--scenario", action="append", help="only run this scenario (repeatable)")
    t.add_argument("--work", help="work directory (default: a new temp dir)")
    t.add_argument("-v", "--verbose", action="store_true", help="list passing checks and info lines")
    i = sub.add_parser("inspect", help="load a save on a server and run Lua over RCON")
    i.add_argument("spec", help="test spec, for mod paths and Factorio version")
    i.add_argument("--save", required=True)
    i.add_argument("--mods", help="comma-separated mod names from the spec's mod_paths")
    i.add_argument("--context", help="run the Lua inside this mod's Lua state (/sc __mod__ ...)")
    i.add_argument("--ticks", type=int, default=0, help="let the game run this many ticks first")
    i.add_argument("--lua", action="append", required=True, help="Lua to run; use rcon.print for output")
    args = parser.parse_args()
    return cmd_test(args) if args.command == "test" else cmd_inspect(args)


if __name__ == "__main__":
    sys.exit(main())
