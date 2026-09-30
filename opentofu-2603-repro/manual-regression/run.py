#!/usr/bin/env python3
"""Run the local issue-2603 CLI regression fixtures."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPRO = HERE.parent

# Stage and diagnostic expected for intentionally invalid configurations.
EXPECTED_ERRORS = {
    "11_invalid_mapping": ("test", "Missing provider definition for docker.missing"),
    "17_constraint_conflict": ("init", "constraint > 0.4.1"),
    "18_no_root_requirement": ("init", "hashicorp/docker"),
}

# 12, 14, and 15 were exploratory controls. Case 14 has an unrelated duplicate
# provider warning; case 19 is the clean regression comparison.
DEFAULT_CASES = tuple(
    name for name in (
        "01_implicit",
        "02_explicit_same",
        "03_alias",
        "04_renamed",
        "05_helper_requirement",
        "06_unselected_alias",
        "07_two_runs",
        "08_two_runs_reversed",
        "09_root_plan_apply",
        "10_mock",
        "11_invalid_mapping",
        "13_multiple_aliases",
        "16_helper_source_conflict",
        "17_constraint_conflict",
        "18_no_root_requirement",
        "19_preexisting_no_test_provider",
    )
)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("cases", nargs="*", help="case directory names; defaults to the curated suite")
parser.add_argument("--binary", type=Path, default=REPRO / "bin/tofu")
parser.add_argument("--plugin-dir", type=Path, default=REPRO / ".terraform/providers")
args = parser.parse_args()

binary = args.binary.resolve()
plugin_dir = args.plugin_dir.resolve()
if not binary.is_file() or not plugin_dir.is_dir():
    parser.error("build --binary and initialize the original reproduction's provider cache first")

failures = []
env = dict(os.environ, TF_IN_AUTOMATION="1", CHECKPOINT_DISABLE="1")
for name in args.cases or DEFAULT_CASES:
    case = HERE / name
    if not case.is_dir():
        parser.error(f"unknown case: {name}")
    expected = EXPECTED_ERRORS.get(name)
    for stage, cmd in (
        ("init", ["init", "-backend=false", "-input=false", "-lockfile=readonly", f"-plugin-dir={plugin_dir}", "-no-color"]),
        ("test", ["test", "-no-color"]),
    ):
        result = subprocess.run(
            [str(binary), f"-chdir={case}", *cmd],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )
        output = result.stdout + result.stderr
        (case / f"{stage}.log").write_text(output)
        if expected is not None and expected[0] == stage:
            ok = result.returncode != 0 and expected[1] in output
        else:
            ok = result.returncode == 0
        print(f"{name}: {stage} {'PASS' if ok else 'FAIL'} (exit {result.returncode})", flush=True)
        if not ok:
            failures.append(f"{name} {stage}: see {case / (stage + '.log')}")
        if result.returncode != 0:
            break

if failures:
    print("\nUnexpected results:", *failures, sep="\n", file=sys.stderr)
    sys.exit(1)
print("\nAll selected cases matched their expectations.")
