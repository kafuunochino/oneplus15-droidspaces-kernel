#!/usr/bin/env python3
import pathlib
import re
import subprocess
import sys


def pahole(vmlinux: pathlib.Path) -> str:
    return subprocess.check_output(
        ["pahole", "-C", "task_struct", str(vmlinux)], text=True
    )


def top_level_fields(text: str) -> dict[str, tuple[int, int]]:
    fields: dict[str, tuple[int, int]] = {}
    pattern = re.compile(
        r"\b([A-Za-z_][A-Za-z0-9_]*)(?:\[[^]]+\])?;"
        r"\s*/\*\s*(\d+)\s+(\d+)\s*\*/"
    )
    for line in text.splitlines():
        if not line.startswith("\t") or line.startswith("\t\t"):
            continue
        match = pattern.search(line)
        if match:
            fields[match.group(1)] = (int(match.group(2)), int(match.group(3)))
    return fields


def struct_size(text: str) -> int:
    match = re.search(r"/\* size: (\d+),", text)
    if not match:
        raise SystemExit("task_struct size was not found in pahole output")
    return int(match.group(1))


def symvers(path: pathlib.Path) -> dict[tuple[str, str], str]:
    result: dict[tuple[str, str], str] = {}
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 3:
            result[(parts[1], parts[2])] = parts[0]
    return result


def is_rust_symbol(name: str) -> bool:
    return name.startswith("_R") or name.startswith("rust_")


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: validate.py BASE_VMLINUX NEW_VMLINUX "
            "BASE_MODULE_SYMVERS NEW_MODULE_SYMVERS",
            file=sys.stderr,
        )
        return 2

    base_vmlinux, new_vmlinux, base_symvers, new_symvers = map(
        pathlib.Path, sys.argv[1:]
    )
    base_pahole = pahole(base_vmlinux)
    new_pahole = pahole(new_vmlinux)
    base_fields = top_level_fields(base_pahole)
    new_fields = top_level_fields(new_pahole)

    layout_changes = []
    for name in sorted(base_fields.keys() & new_fields.keys()):
        if base_fields[name] != new_fields[name]:
            layout_changes.append((name, base_fields[name], new_fields[name]))

    base_symbols = symvers(base_symvers)
    new_symbols = symvers(new_symvers)
    crc_changes = []
    for key in sorted(base_symbols.keys() & new_symbols.keys()):
        if base_symbols[key] != new_symbols[key]:
            crc_changes.append((key[0], key[1], base_symbols[key], new_symbols[key]))
    rust_changes = [item for item in crc_changes if is_rust_symbol(item[0])]
    non_rust_changes = [item for item in crc_changes if not is_rust_symbol(item[0])]

    print(f"base_task_struct_size={struct_size(base_pahole)}")
    print(f"new_task_struct_size={struct_size(new_pahole)}")
    print(f"common_top_level_fields={len(base_fields.keys() & new_fields.keys())}")
    print(f"top_level_layout_changes={len(layout_changes)}")
    for item in layout_changes[:50]:
        print(f"LAYOUT_CHANGE {item[0]} {item[1]} -> {item[2]}")
    print(f"common_symbols={len(base_symbols.keys() & new_symbols.keys())}")
    print(f"crc_changes_total={len(crc_changes)}")
    print(f"crc_changes_rust={len(rust_changes)}")
    print(f"crc_changes_non_rust={len(non_rust_changes)}")
    for item in non_rust_changes[:50]:
        print(f"NON_RUST_CRC_CHANGE {item[0]} {item[1]} {item[2]} -> {item[3]}")

    if struct_size(base_pahole) != 5184 or struct_size(new_pahole) != 5184:
        return 1
    if layout_changes or non_rust_changes:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
