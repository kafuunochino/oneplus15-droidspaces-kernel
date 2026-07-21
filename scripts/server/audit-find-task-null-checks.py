#!/usr/bin/env python3
from __future__ import annotations

import glob
import pathlib
import re
import subprocess

ROOT = pathlib.Path('/root/oneplus15boot')
MODULES = ROOT / 'inputs/stock-modules'
OBJDUMP = (
    ROOT
    / 'build/source/kernel_platform/prebuilts/clang/host/linux-x86/'
      'clang-r536225/bin/llvm-objdump'
)

function_re = re.compile(r'^([0-9a-f]+) <([^>]+)>:$')
instruction_re = re.compile(r'^\s*[0-9a-f]+:\s+[0-9a-f ]+\s+(.+)$')
register_re = re.compile(r'\b(x(?:[12]?\d|30)|xzr)\b')


def instruction_text(line: str) -> str | None:
    match = instruction_re.match(line)
    return match.group(1).strip() if match else None


def analyze(module: pathlib.Path) -> list[tuple[str, str, str, list[str]]]:
    text = subprocess.check_output(
        [str(OBJDUMP), '-dr', str(module)],
        text=True,
        errors='replace',
    )
    lines = text.splitlines()
    current_function = '<unknown>'
    functions: dict[int, str] = {}
    for index, line in enumerate(lines):
        match = function_re.match(line)
        if match:
            current_function = match.group(2)
        functions[index] = current_function

    findings = []
    for index, line in enumerate(lines):
        if 'R_AARCH64_CALL26' not in line or 'find_task_by_vpid' not in line:
            continue

        aliases = {'x0'}
        checked = False
        dereferenced = False
        reason = 'no null check in next 14 instructions'
        window: list[str] = []
        for next_line in lines[index + 1:]:
            instruction = instruction_text(next_line)
            if instruction is None:
                continue
            window.append(instruction)
            if len(window) > 14:
                break

            move = re.match(r'mov\s+(x\d+),\s*(x\d+)', instruction)
            if move and move.group(2) in aliases:
                aliases.add(move.group(1))

            alias_pattern = '|'.join(re.escape(alias) for alias in sorted(aliases))
            if re.search(rf'\b(cbz|cbnz|cmp|cmn|tst)\s+({alias_pattern})\b', instruction):
                checked = True
                reason = 'null/range check observed'
                break

            for alias in aliases:
                if re.search(rf'\[[^\]]*\b{re.escape(alias)}\b[^\]]*\]', instruction):
                    dereferenced = True
                    reason = f'memory access through {alias} before null check'
                    break
                if re.search(rf'\badd\s+x\d+,\s*{re.escape(alias)},\s*#', instruction):
                    dereferenced = True
                    reason = f'pointer arithmetic on {alias} before null check'
                    break
            if dereferenced:
                break

        if dereferenced or not checked:
            findings.append((module.name, functions[index], reason, window))
    return findings


def main() -> None:
    all_findings = []
    module_count = 0
    call_count = 0
    for name in sorted(glob.glob(str(MODULES / '*' / '*.ko'))):
        module = pathlib.Path(name)
        undefined = subprocess.run(
            ['nm', '-u', str(module)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        ).stdout
        calls = undefined.count('find_task_by_vpid')
        if not calls:
            continue
        module_count += 1
        findings = analyze(module)
        call_count += subprocess.run(
            [str(OBJDUMP), '-dr', str(module)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        ).stdout.count('R_AARCH64_CALL26\tfind_task_by_vpid')
        all_findings.extend(findings)

    print(f'modules_importing_find_task_by_vpid={module_count}')
    print(f'relocation_callsites={call_count}')
    print(f'heuristic_findings={len(all_findings)}')
    for module, function, reason, window in all_findings:
        print(f'[{module}] {function}: {reason}')
        for instruction in window:
            print(f'  {instruction}')


if __name__ == '__main__':
    main()
