#!/usr/bin/env python3
import collections
import pathlib
import subprocess
import sys


def read_symvers(path: pathlib.Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 3:
            result[parts[1]] = parts[0].lower()
    return result


def module_versions(path: pathlib.Path) -> dict[str, str]:
    proc = subprocess.run(
        ["modprobe", "--dump-modversions", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode:
        raise RuntimeError(f"{path}: {proc.stderr.strip()}")
    result: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2:
            result[parts[1]] = parts[0].lower()
    return result


def main() -> int:
    if len(sys.argv) < 4:
        print(
            "usage: validate-stock-module-crcs.py MODULE_ROOT "
            "NAME=MODULE_SYMVERS [NAME=MODULE_SYMVERS ...]",
            file=sys.stderr,
        )
        return 2

    module_root = pathlib.Path(sys.argv[1])
    candidates: dict[str, dict[str, str]] = {}
    for spec in sys.argv[2:]:
        name, value = spec.split("=", 1)
        candidates[name] = read_symvers(pathlib.Path(value))

    modules = sorted(module_root.rglob("*.ko"))
    stats = {
        name: collections.Counter() for name in candidates
    }
    mismatches: dict[str, list[tuple[str, str, str, str]]] = {
        name: [] for name in candidates
    }
    mismatch_modules: dict[str, set[str]] = {
        name: set() for name in candidates
    }
    parse_errors: list[str] = []
    modules_with_versions = 0
    total_requirements = 0

    for module in modules:
        rel = str(module.relative_to(module_root))
        try:
            required = module_versions(module)
        except RuntimeError as exc:
            parse_errors.append(str(exc))
            continue
        if required:
            modules_with_versions += 1
        total_requirements += len(required)

        for name, exported in candidates.items():
            counter = stats[name]
            counter["requirements"] += len(required)
            for symbol, expected_crc in required.items():
                actual_crc = exported.get(symbol)
                if actual_crc is None:
                    counter["missing_from_gki"] += 1
                elif actual_crc == expected_crc:
                    counter["matched"] += 1
                else:
                    counter["mismatched"] += 1
                    mismatch_modules[name].add(rel)
                    mismatches[name].append(
                        (rel, symbol, expected_crc, actual_crc)
                    )

    print(f"module_files={len(modules)}")
    print(f"modules_with_versions={modules_with_versions}")
    print(f"total_requirements={total_requirements}")
    print(f"parse_errors={len(parse_errors)}")
    for error in parse_errors[:20]:
        print(f"PARSE_ERROR {error}")

    failed = bool(parse_errors)
    for name in candidates:
        counter = stats[name]
        print(f"[{name}]")
        print(f"matched={counter['matched']}")
        print(f"mismatched={counter['mismatched']}")
        print(f"missing_from_gki={counter['missing_from_gki']}")
        print(f"modules_with_mismatch={len(mismatch_modules[name])}")
        for module, symbol, expected, actual in mismatches[name][:100]:
            print(
                f"MISMATCH {name} {module} {symbol} "
                f"module={expected} kernel={actual}"
            )
        if counter["mismatched"]:
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
