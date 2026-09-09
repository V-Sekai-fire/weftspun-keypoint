# SPDX-License-Identifier: Apache-2.0 OR MIT
"""Gate: the pinned pixi table, the two installers and the workspace's declared platforms
all say the same thing.

WHY THIS EXISTS. Bootstrapping is the one step that cannot be done by the tool it installs,
so the pins live in a text table rather than in a lockfile. A table is a second place, and a
second place drifts: an installer grows an architecture arm whose row was never added, a
release is re-pinned in the table and the checksum copied from the wrong line, or a project
declares `osx-arm64` in its `pixi.toml` while nothing here can install pixi on it. None of
those is visible until somebody is standing at a bare machine.

Four pairs are walked, each enumerated rather than sampled -- every population here is a
handful of lines in files this repository owns.

  1. every architecture arm in an installer resolves to a row in the table
  2. every row in the table is reachable from at least one installer arm
  3. every platform any workspace `pixi.toml` declares has a row
  4. every pinned checksum matches what the release publishes

The fourth needs the network. It is not skipped when the network is absent, because a silent
skip reads exactly like a pass; `--offline` drops it and still exits non-zero, naming it.

Run:  python check_bootstrap.py [--workspace DIR] [--offline] [--self-test]
"""

import argparse
import pathlib
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
WORKSPACE = HERE.parent.parent  # .repo/manifests -> .repo -> the repo client root


def read_table(text):
    version, source, checksums, rows = "", "", "", {}
    for line in text.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "version":
            version = parts[1]
        elif parts[0] == "source":
            source = parts[1]
        elif parts[0] == "checksums":
            checksums = parts[1]
        elif parts[0] == "platform" and len(parts) == 5:
            rows[parts[1]] = {"asset": parts[2], "sha256": parts[3], "member": parts[4]}
    return version, source, checksums, rows


def sh_arms(text):
    """Platform names the POSIX installer can select, from its `want=NAME` assignments."""
    out = set()
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("want=") or ") want=" in stripped:
            token = stripped.split("want=", 1)[1].split()[0]
            if token.isascii() and token[0].isalpha():
                out.add(token.rstrip(";"))
    return out


def ps_arms(text):
    """Platform names the PowerShell installer can select, from its `'ARCH' { 'NAME' }` arms."""
    out = set()
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("'") or "{ '" not in stripped:
            continue
        name = stripped.split("{ '", 1)[1].split("'", 1)[0]
        if name:
            out.add(name)
    return out


def declared_platforms(workspace):
    """Every platform named in a `platforms = [...]` line of a workspace pixi.toml."""
    out = {}
    for toml in sorted(pathlib.Path(workspace).glob("*/*/pixi.toml")):
        if ".pixi" in toml.parts:
            continue
        for line in toml.read_text(encoding="utf-8", errors="replace").splitlines():
            if not line.startswith("platforms"):
                continue
            inner = line.split("[", 1)[-1].split("]", 1)[0]
            for name in inner.split(","):
                name = name.strip().strip('"').strip("'")
                if name:
                    out.setdefault(name, []).append(str(toml.relative_to(workspace)))
    return out


def published(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        body = response.read().decode("utf-8")
    return {p[1]: p[0] for p in (l.split() for l in body.splitlines()) if len(p) == 2}


def check(table_text, sh_text, ps_text, workspace, offline):
    version, _source, checksums, rows = read_table(table_text)
    failures, counts = [], {}

    if not version or not rows:
        return ["FAIL pixi-release.txt names no version or no platform row"], counts

    arms = sh_arms(sh_text) | ps_arms(ps_text)
    counts["installer arms"] = len(arms)
    for arm in sorted(arms):
        if arm not in rows:
            failures.append(f"FAIL an installer selects {arm}, which has no row in pixi-release.txt")

    counts["pinned rows"] = len(rows)
    for name in sorted(rows):
        if name not in arms:
            failures.append(f"FAIL pixi-release.txt pins {name}, which no installer can select")

    declared = declared_platforms(workspace) if workspace else {}
    counts["platforms declared by workspace pixi.toml"] = len(declared)
    for name, users in sorted(declared.items()):
        if name not in rows:
            failures.append(f"FAIL {users[0]} declares {name}, which pixi cannot be bootstrapped on")

    if offline:
        counts["checksums verified against the release"] = 0
        failures.append("FAIL --offline: the published checksums were not read, which is not a pass")
    else:
        try:
            upstream = published(checksums)
        except Exception as exc:
            return failures + [f"FAIL could not read {checksums}: {exc}"], counts
        counts["checksums verified against the release"] = len(rows)
        for name, row in sorted(rows.items()):
            want = upstream.get(row["asset"])
            if want is None:
                failures.append(f"FAIL {row['asset']} is not in the release's sha256.sum")
            elif want != row["sha256"]:
                failures.append(f"FAIL {name}: pinned {row['sha256'][:12]}, published {want[:12]}")

    return failures, counts


def self_test():
    table = (HERE / "pixi-release.txt").read_text(encoding="utf-8")
    sh = (HERE / "install.sh").read_text(encoding="utf-8")
    ps = (HERE / "install.ps1").read_text(encoding="utf-8")
    controls = [
        (
            "a wrong checksum is rejected",
            table.replace("7700e558", "0000e558"),
            sh,
            ps,
            None,
            False,
        ),
        (
            "an installer arm with no row is rejected",
            "\n".join(l for l in table.splitlines() if not l.startswith("platform osx-64")),
            sh,
            ps,
            None,
            True,
        ),
        (
            "a row no installer selects is rejected",
            table + "platform aix-64 pixi-aix.tar.gz " + "0" * 64 + " pixi\n",
            sh,
            ps,
            None,
            True,
        ),
        ("--offline is not a pass", table, sh, ps, None, True),
    ]
    bad = 0
    for name, t, s, p, ws, off in controls:
        failures, _ = check(t, s, p, ws, off)
        status = "ok" if failures else "CONTROL DID NOT FIRE"
        bad += 0 if failures else 1
        print(f"  {status}: {name}")
    failures, _ = check(table, sh, ps, None, False)
    if failures:
        bad += 1
        print("  CONTROL DID NOT FIRE: the shipped table passes")
        for f in failures:
            print(f"    {f}")
    else:
        print("  ok: the shipped table passes")
    return 1 if bad else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", default=str(WORKSPACE))
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    workspace = args.workspace if pathlib.Path(args.workspace).is_dir() else None
    failures, counts = check(
        (HERE / "pixi-release.txt").read_text(encoding="utf-8"),
        (HERE / "install.sh").read_text(encoding="utf-8"),
        (HERE / "install.ps1").read_text(encoding="utf-8"),
        workspace,
        args.offline,
    )
    if workspace is None:
        print(f"  note: {args.workspace} is not a directory, so no pixi.toml was read")
    for label, n in counts.items():
        print(f"  {n:>3}  {label}")
    for f in failures:
        print(f"  {f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
