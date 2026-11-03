"""Verify recovered assets; optionally stage original source names for old builds.

The repository stores lowercase paths. This restores original Makefile/.S/header
case in an ignored, new directory without editing archived source contents.
It does not run compilers, Vivado, Makefiles, shell scripts or formal tools.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data/recovery/original_cpu/manifest.json"


def contained(root, relative):
    rel = PurePosixPath(relative)
    if rel.is_absolute() or ".." in rel.parts or "\\" in relative or ":" in relative:
        raise ValueError(f"Unsafe relative path: {relative}")
    result = root.joinpath(*rel.parts).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError(f"Path outside root: {relative}")
    return result


def verify():
    records = json.loads(MANIFEST.read_text(encoding="utf-8"))["records"]
    seen = set()
    for record in records:
        dest = record["destination"]
        if dest in seen:
            raise ValueError(f"Duplicate destination: {dest}")
        seen.add(dest)
        content = contained(ROOT, dest).read_bytes()
        if hashlib.sha256(content).hexdigest() != record["sha256"]:
            raise ValueError(f"Recovered file hash mismatch: {dest}")
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--stage", metavar="NAME",
        help="Create build/local/NAME with original source filenames; must not exist",
    )
    args = parser.parse_args()
    records = verify()
    print(f"Verified {len(records)} recovered file hashes.")
    if args.stage is None:
        return
    if not args.stage or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in args.stage):
        parser.error("Stage name must use lowercase ASCII letters, digits, _ or -")
    local_root = ROOT / "build/local"
    target = contained(local_root, args.stage)
    if target.exists():
        parser.error(f"Refusing to overwrite existing stage: {target}")

    plan = {}

    def add(relative, source):
        dest = contained(target, relative)
        # Case-fold to detect collisions on Windows as well as Linux.
        key = str(dest).casefold()
        if key in plan:
            raise ValueError(f"Duplicate stage destination: {relative}")
        plan[key] = (dest, source)

    for record in records:
        source = contained(ROOT, record["destination"])
        if record["package"]:
            add(record["package"] + "/" + record["original_relative"], source)
        elif "/sources_1/imports/rtl/" in record["destination"]:
            # Archived JasperGold scripts refer to ../rtl from formal/.
            add("rtl/" + source.name, source)
        elif source.name in ("rv32ui-p-add.hex", "rv64ui-p-add.hex"):
            arch = "RV32" if source.name.startswith("rv32") else "RV64"
            add(f"test/riscv-test/{arch}/hex/{source.name}", source)

    target.mkdir(parents=True, exist_ok=False)
    for dest, source in plan.values():
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("xb") as stream:
            stream.write(source.read_bytes())
    print(f"Staged {len(plan)} source/input files in {target}")
    print("No builds executed. Review documented dependency and testbench gaps first.")


if __name__ == "__main__":
    main()
