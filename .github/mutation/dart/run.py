#!/usr/bin/env python3
"""Fixed-mutant runner for the mobile "Move to album" code.

Reads mutants.json, copies mobile/lib and mobile/test into a throwaway sandbox,
applies one source mutation at a time there, runs the listed tests and records
whether they noticed. The checkout itself is never written to.

Exit codes: 0 score at or above the break threshold, 1 score below it,
2 a mutant definition no longer matches the source or does not compile,
3 the tests fail before any mutation, 130 interrupted.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

COMPILE_FAILURE_MARKERS = ("Compilation failed", "Error: Compilation")
SANDBOX_COPIED_DIRECTORIES = ("lib", "test", ".dart_tool")
SANDBOX_SKIPPED_ENTRIES = ("build",)
CANARY_STATEMENT = "throw StateError('mutation sandbox canary');"
BODY_OPENING = re.compile(r"\s*(?:(?:async|sync)\*?\s*)?\{")

EXIT_OK = 0
EXIT_BELOW_THRESHOLD = 1
EXIT_STALE_DEFINITIONS = 2
EXIT_BASELINE_FAILED = 3
EXIT_INTERRUPTED = 130


class DefinitionError(Exception):
    pass


def parse_arguments():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    script_directory = Path(__file__).resolve().parent
    parser.add_argument("--mobile-dir", default="mobile", help="path to the Flutter package (default: mobile)")
    parser.add_argument("--config", default=str(script_directory / "mutants.json"), help="mutant definitions")
    parser.add_argument("--report-dir", help="where to write mutation.json and mutation.md (default: <mobile>/build/reports/mutation)")
    parser.add_argument("--flutter", default="flutter", help='command that starts Flutter, for example "mise exec -- flutter"')
    parser.add_argument("--break", dest="break_threshold", type=float, help="override thresholds.break from the config")
    parser.add_argument("--only", nargs="+", metavar="ID", help="run only these mutant ids")
    parser.add_argument("--list", action="store_true", help="resolve every mutant against the source, print them and exit")
    parser.add_argument("--timeout", type=int, help="seconds before a test run counts as a timeout (default: from the config)")
    parser.add_argument("--workdir", help="parent directory for the sandbox (default: the system temp directory)")
    return parser.parse_args()


def flexible_pattern(snippet):
    tokens = snippet.split()
    if not tokens:
        raise DefinitionError("an edit has an empty find text")
    return re.compile(r"\s+".join(re.escape(token) for token in tokens))


def matching_close(text, open_index, open_character, close_character):
    depth = 0
    for index in range(open_index, len(text)):
        character = text[index]
        if character == open_character:
            depth += 1
        elif character == close_character:
            depth -= 1
            if depth == 0:
                return index
    raise DefinitionError("unbalanced %s%s after offset %d" % (open_character, close_character, open_index))


def function_span(text, scope):
    if not scope.endswith("("):
        raise DefinitionError('scope "%s" must end with the opening parenthesis of the parameter list' % scope)
    occurrences = text.count(scope)
    if occurrences != 1:
        raise DefinitionError('scope "%s" occurs %d times, expected exactly once' % (scope, occurrences))
    start = text.index(scope)
    parameters_end = matching_close(text, start + len(scope) - 1, "(", ")")
    body = BODY_OPENING.match(text, parameters_end + 1)
    if body is None:
        return start, None, parameters_end + 1
    body_start = body.end() - 1
    body_end = matching_close(text, body_start, "{", "}")
    return start, body_start, body_end + 1


def apply_edits(text, scope, edits):
    start, _, end = function_span(text, scope)
    body = text[start:end]
    for edit in edits:
        pattern = flexible_pattern(edit["find"])
        matches = pattern.findall(body)
        if len(matches) != 1:
            raise DefinitionError('"%s" occurs %d times inside "%s", expected exactly once' % (edit["find"], len(matches), scope))
        body = pattern.sub(lambda _: edit["replace"], body, count=1)
    return text[:start] + body + text[end:]


def insert_canary(text, scope):
    _, body_start, _ = function_span(text, scope)
    if body_start is None:
        raise DefinitionError('scope "%s" has no function body for the canary' % scope)
    return text[: body_start + 1] + " " + CANARY_STATEMENT + text[body_start + 1 :]


def resolve_single_file(mobile_directory, pattern, scope):
    candidates = sorted(Path(path) for path in glob.glob(str(mobile_directory / pattern), recursive=True))
    holders = [path for path in candidates if scope in path.read_text(encoding="utf-8")]
    if len(holders) != 1:
        raise DefinitionError(
            '%d file(s) matching "%s" contain "%s", expected exactly one' % (len(holders), pattern, scope)
        )
    return holders[0].relative_to(mobile_directory)


def resolve_tests(mobile_directory, patterns):
    tests = []
    for pattern in patterns:
        matches = sorted(glob.glob(str(mobile_directory / pattern), recursive=True))
        if not matches:
            raise DefinitionError('no test file matches "%s"' % pattern)
        tests.extend(str(Path(match).relative_to(mobile_directory)) for match in matches)
    return sorted(set(tests))


def resolve_mutants(config, mobile_directory, only):
    resolved = []
    problems = []
    seen = set()
    for target in config["targets"]:
        try:
            relative_file = resolve_single_file(mobile_directory, target["file"], target["scope"])
            tests = resolve_tests(mobile_directory, target["tests"])
            original = (mobile_directory / relative_file).read_text(encoding="utf-8")
            function_span(original, target["scope"])
        except DefinitionError as error:
            problems.append("target %s: %s" % (target["name"], error))
            continue
        for mutant in target["mutants"]:
            mutant_id = "%s.%s" % (target["name"], mutant["id"])
            if mutant_id in seen:
                problems.append("duplicate mutant id %s" % mutant_id)
                continue
            seen.add(mutant_id)
            if only and mutant_id not in only:
                continue
            scope = mutant.get("scope", target["scope"])
            try:
                mutated = apply_edits(original, scope, mutant["edits"])
            except DefinitionError as error:
                problems.append("mutant %s: %s" % (mutant_id, error))
                continue
            if mutated == original:
                problems.append("mutant %s: the edit does not change the source" % mutant_id)
                continue
            resolved.append(
                {
                    "id": mutant_id,
                    "operator": mutant["operator"],
                    "description": mutant["description"],
                    "file": str(relative_file),
                    "canary_scope": target["scope"],
                    "tests": tests,
                    "original": original,
                    "mutated": mutated,
                }
            )
    if only:
        unknown = sorted(set(only) - seen)
        problems.extend("unknown mutant id %s" % mutant_id for mutant_id in unknown)
    return resolved, problems


def build_sandbox(repository_root, mobile_directory, parent):
    sandbox_root = Path(tempfile.mkdtemp(prefix="dart-mutation-", dir=parent))
    for entry in repository_root.iterdir():
        if entry.resolve() == mobile_directory.resolve() or entry.name == ".git":
            continue
        os.symlink(entry.resolve(), sandbox_root / entry.name)
    sandbox_mobile = sandbox_root / mobile_directory.name
    sandbox_mobile.mkdir()
    for entry in mobile_directory.iterdir():
        if entry.name in SANDBOX_SKIPPED_ENTRIES:
            continue
        destination = sandbox_mobile / entry.name
        if entry.name in SANDBOX_COPIED_DIRECTORIES and entry.is_dir():
            shutil.copytree(entry, destination, symlinks=True)
        elif entry.is_file() and not entry.is_symlink():
            shutil.copy2(entry, destination)
        else:
            os.symlink(entry.resolve(), destination)
    return sandbox_root, sandbox_mobile


def run_tests(flutter_command, sandbox_mobile, tests, timeout):
    command = flutter_command + ["test", "--no-pub", "--reporter", "expanded"] + tests
    started = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=str(sandbox_mobile),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        universal_newlines=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        output, _ = process.communicate()
        timed_out = True
    except BaseException:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        raise
    return {
        "exit_code": process.returncode,
        "timed_out": timed_out,
        "output": output,
        "seconds": round(time.monotonic() - started, 1),
    }


def classify(result):
    if result["timed_out"]:
        return "timeout"
    if result["exit_code"] == 0:
        return "survived"
    if any(marker in result["output"] for marker in COMPILE_FAILURE_MARKERS):
        return "invalid"
    return "killed"


def changed_lines(original, mutated):
    original_lines = original.splitlines()
    mutated_lines = mutated.splitlines()
    prefix = 0
    while prefix < min(len(original_lines), len(mutated_lines)) and original_lines[prefix] == mutated_lines[prefix]:
        prefix += 1
    suffix = 0
    while (
        suffix < min(len(original_lines), len(mutated_lines)) - prefix
        and original_lines[-1 - suffix] == mutated_lines[-1 - suffix]
    ):
        suffix += 1
    removed = original_lines[prefix : len(original_lines) - suffix]
    added = mutated_lines[prefix : len(mutated_lines) - suffix]
    return prefix + 1, removed, added


def source_fingerprint(mobile_directory, files):
    return {name: hashlib.sha256((mobile_directory / name).read_bytes()).hexdigest() for name in sorted(files)}


def tail(output, lines=25):
    return "\n".join(output.strip().splitlines()[-lines:])


def write_reports(report_directory, summary):
    report_directory.mkdir(parents=True, exist_ok=True)
    (report_directory / "mutation.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    lines = [
        "### Mutation test: mobile",
        "",
        "Fixed mutants from `%s`, applied in a sandbox copy of `mobile/lib`." % summary["config"],
        "",
        "| Mutation score | Killed | Timeout | Survived | Invalid | Threshold |",
        "| --- | --- | --- | --- | --- | --- |",
        "| %s | %d | %d | %d | %d | break %s |"
        % (
            "n/a" if summary["score"] is None else "%.2f %%" % summary["score"],
            summary["counts"]["killed"],
            summary["counts"]["timeout"],
            summary["counts"]["survived"],
            summary["counts"]["invalid"],
            summary["thresholds"]["break"],
        ),
        "",
    ]
    survivors = [mutant for mutant in summary["mutants"] if mutant["status"] == "survived"]
    invalid = [mutant for mutant in summary["mutants"] if mutant["status"] == "invalid"]
    lines.append("Surviving mutants:" if survivors else "No surviving mutants.")
    lines.append("")
    for mutant in survivors:
        lines.append("- `%s` (%s) `%s:%d`: %s" % (mutant["id"], mutant["operator"], mutant["file"], mutant["line"], mutant["description"]))
    if invalid:
        lines.extend(["", "Mutants that no longer compile and need a new definition:", ""])
        for mutant in invalid:
            lines.append("- `%s` `%s:%d`" % (mutant["id"], mutant["file"], mutant["line"]))
    (report_directory / "mutation.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def display_path(path, repository_root):
    try:
        return str(path.relative_to(repository_root))
    except ValueError:
        return str(path)


def raise_keyboard_interrupt(*_):
    raise KeyboardInterrupt()


def main():
    arguments = parse_arguments()
    mobile_directory = Path(arguments.mobile_dir).resolve()
    repository_root = mobile_directory.parent
    config_path = Path(arguments.config).resolve()
    config = json.loads(config_path.read_text(encoding="utf-8"))
    break_threshold = arguments.break_threshold if arguments.break_threshold is not None else config["thresholds"]["break"]
    timeout = arguments.timeout or config.get("timeoutSeconds", 600)
    report_directory = Path(arguments.report_dir).resolve() if arguments.report_dir else mobile_directory / "build" / "reports" / "mutation"
    flutter_command = shlex.split(arguments.flutter)

    mutants, problems = resolve_mutants(config, mobile_directory, set(arguments.only or []))
    if problems:
        print("The mutant definitions in %s do not match the source any more:" % config_path, file=sys.stderr)
        for problem in problems:
            print("  - %s" % problem, file=sys.stderr)
        print("Update the definitions so every scope and find text matches the move code again.", file=sys.stderr)
        return EXIT_STALE_DEFINITIONS

    if arguments.list:
        for mutant in mutants:
            line, removed, added = changed_lines(mutant["original"], mutant["mutated"])
            print("%s [%s] %s:%d" % (mutant["id"], mutant["operator"], mutant["file"], line))
            for text in removed:
                print("    - %s" % text.strip())
            for text in added:
                print("    + %s" % text.strip())
        print("%d mutants" % len(mutants))
        return EXIT_OK

    for interrupting_signal in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(interrupting_signal, raise_keyboard_interrupt)
    target_files = {mutant["file"] for mutant in mutants}
    fingerprint_before = source_fingerprint(mobile_directory, target_files)
    sandbox_root = None
    try:
        sandbox_root, sandbox_mobile = build_sandbox(repository_root, mobile_directory, arguments.workdir)
        print("Sandbox: %s" % sandbox_mobile, flush=True)

        all_tests = sorted({test for mutant in mutants for test in mutant["tests"]})
        baseline = run_tests(flutter_command, sandbox_mobile, all_tests, timeout)
        if baseline["exit_code"] != 0 or baseline["timed_out"]:
            print("The tests fail without any mutation, so no score can be computed:", file=sys.stderr)
            print(tail(baseline["output"], 60), file=sys.stderr)
            return EXIT_BASELINE_FAILED
        print("Baseline: %d test file(s) pass in %.1fs" % (len(all_tests), baseline["seconds"]), flush=True)

        canary_source = mutants[0]
        canary_path = sandbox_mobile / canary_source["file"]
        canary_path.write_text(insert_canary(canary_source["original"], canary_source["canary_scope"]), encoding="utf-8")
        try:
            canary = run_tests(flutter_command, sandbox_mobile, canary_source["tests"], timeout)
        finally:
            canary_path.write_text(canary_source["original"], encoding="utf-8")
        if classify(canary) != "killed":
            print(
                "A statement that always throws inside %s did not fail the tests (%s). "
                "The sandbox does not exercise the mutated sources, refusing to report a score."
                % (canary_source["canary_scope"], classify(canary)),
                file=sys.stderr,
            )
            print(tail(canary["output"]), file=sys.stderr)
            return EXIT_STALE_DEFINITIONS
        print("Canary: the tests run against the sandbox sources", flush=True)

        results = []
        for index, mutant in enumerate(mutants, start=1):
            mutant_path = sandbox_mobile / mutant["file"]
            mutant_path.write_text(mutant["mutated"], encoding="utf-8")
            try:
                result = run_tests(flutter_command, sandbox_mobile, mutant["tests"], timeout)
            finally:
                mutant_path.write_text(mutant["original"], encoding="utf-8")
            status = classify(result)
            line, removed, added = changed_lines(mutant["original"], mutant["mutated"])
            results.append(
                {
                    "id": mutant["id"],
                    "operator": mutant["operator"],
                    "description": mutant["description"],
                    "file": mutant["file"],
                    "line": line,
                    "removed": removed,
                    "added": added,
                    "tests": mutant["tests"],
                    "status": status,
                    "seconds": result["seconds"],
                    "output": tail(result["output"]) if status in ("survived", "invalid") else "",
                }
            )
            print("[%d/%d] %-8s %s (%.1fs)" % (index, len(mutants), status, mutant["id"], result["seconds"]), flush=True)
    except KeyboardInterrupt:
        print("Interrupted, the checkout was not modified.", file=sys.stderr)
        return EXIT_INTERRUPTED
    finally:
        if sandbox_root is not None:
            shutil.rmtree(sandbox_root, ignore_errors=True)
        if source_fingerprint(mobile_directory, target_files) != fingerprint_before:
            print("ERROR: a source file under %s changed while the runner was active." % mobile_directory, file=sys.stderr)
            sys.exit(EXIT_STALE_DEFINITIONS)

    counts = {status: sum(1 for result in results if result["status"] == status) for status in ("killed", "timeout", "survived", "invalid")}
    detected = counts["killed"] + counts["timeout"]
    valid = detected + counts["survived"]
    score = round(detected * 100.0 / valid, 2) if valid else None
    summary = {
        "config": display_path(config_path, repository_root),
        "thresholds": {"break": break_threshold},
        "score": score,
        "counts": counts,
        "mutants": results,
    }
    write_reports(report_directory, summary)

    print("")
    print("Mutation score: %s (%d detected of %d valid, %d invalid)" % ("n/a" if score is None else "%.2f %%" % score, detected, valid, counts["invalid"]))
    for result in results:
        if result["status"] == "survived":
            print("  survived: %s %s:%d %s" % (result["id"], result["file"], result["line"], result["description"]))
    print("Reports: %s" % report_directory)

    if counts["invalid"]:
        print("%d mutant(s) do not compile any more, update their definitions." % counts["invalid"], file=sys.stderr)
        return EXIT_STALE_DEFINITIONS
    if score is None or score < break_threshold:
        print("The mutation score is below the break threshold of %s." % break_threshold, file=sys.stderr)
        return EXIT_BELOW_THRESHOLD
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
