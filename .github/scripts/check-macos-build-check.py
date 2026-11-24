#!/usr/bin/env python3
"""Fails when a step of macos-build-check.yml no longer equals the step of ci.yml it was copied from.

    check-macos-build-check.py              compares the two workflows of this checkout
    check-macos-build-check.py --self-test  checks the comparison against texts held here

macos-build-check.yml runs, by hand, the build steps of three of ci.yml's macOS jobs with no test run. A step there is
a copy, so a change to the step in ci.yml must be made there too, or the check builds something the gate does not.
Two steps are equal when their lines are, leaving out comments, the step's `id:` and `if:`, and the step's name where
the copy is named apart. A step of macos-build-check.yml that carries `# Only in this workflow.` on the line above its
name is not compared.
"""
import re
import sys

# Job of macos-build-check.yml -> the job of ci.yml its steps come from, unless a step is listed below.
JOBS = {"package": "spm-tests", "example-package": "example-integrations"}
# (job, step name) of macos-build-check.yml -> (job, step name) of ci.yml, where either differs from the above.
RENAMED = {
    ("package", "Restore Cloned Source Packages"): ("apple-platforms", "Cache Cloned Source Packages"),
    ("package", "Resolve Package Dependencies with xcodebuild"): ("apple-platforms", "Resolve Package Dependencies"),
}
ONLY_HERE = "# Only in this workflow."


def steps_of(text, job):
    """Returns {step name: (lines compared, whether marked as only here)} of one job."""
    lines = text.split("\n")
    try:
        start = lines.index(f"  {job}:")
    except ValueError:
        return None
    end = next((index for index in range(start + 1, len(lines)) if re.match(r"^  [A-Za-z0-9_-]+:\s*$", lines[index])), len(lines))
    steps, name, marked = {}, None, False
    for index in range(start, end):
        line = lines[index]
        if line.startswith("      - name: "):
            name = line[len("      - name: "):]
            marked = index > 0 and lines[index - 1].strip() == ONLY_HERE
            steps[name] = ([], marked)
        elif line.startswith("      - "):
            name = None
        elif name is not None and line.strip() and not line.strip().startswith("#") and not re.match(r"^        (id|if): ", line):
            steps[name][0].append(line)
    return steps


def differences(check_text, ci_text):
    found = []
    for job, ci_job in JOBS.items():
        copies = steps_of(check_text, job)
        if copies is None:
            found.append(f"macos-build-check.yml has no job `{job}`")
            continue
        for name, (lines, marked) in copies.items():
            if marked:
                continue
            source_job, source_name = RENAMED.get((job, name), (ci_job, name))
            originals = steps_of(ci_text, source_job)
            if originals is None or source_name not in originals:
                found.append(f"`{name}` in job `{job}`: ci.yml's job `{source_job}` has no step `{source_name}`")
            elif originals[source_name][0] != lines:
                found.append(f"`{name}` in job `{job}` differs from `{source_name}` in ci.yml's job `{source_job}`")
    return found


def self_test():
    ci = "jobs:\n  spm-tests:\n    steps:\n      # A comment.\n      - name: Build\n        id: build\n        if: ${{ needs.a.result == 'success' }}\n        run: |\n          swift build\n      - name: Test\n        run: swift test\n  apple-platforms:\n    steps:\n      - name: Resolve Package Dependencies\n        run: xcodebuild -resolvePackageDependencies\n  example-integrations:\n    steps:\n      - name: Example\n        run: swift build --package-path Example\n"
    check = "jobs:\n  package:\n    steps:\n      # Only in this workflow.\n      - name: Compare\n        run: compare\n      - name: Build\n        run: |\n          swift build\n      - name: Resolve Package Dependencies with xcodebuild\n        run: xcodebuild -resolvePackageDependencies\n  example-package:\n    steps:\n      - name: Example\n        run: swift build --package-path Example\n"
    cases = [
        ("copies that differ only in comments, id and if are equal", differences(check, ci), []),
        ("a changed command is reported", differences(check.replace("          swift build\n", "          swift build -v\n"), ci), ["`Build` in job `package` differs from `Build` in ci.yml's job `spm-tests`"]),
        ("a step ci.yml no longer has is reported", differences(check, ci.replace("- name: Example", "- name: Sample")), ["`Example` in job `example-package`: ci.yml's job `example-integrations` has no step `Example`"]),
        ("a renamed copy is compared with its source", differences(check, ci.replace("xcodebuild -resolvePackageDependencies", "xcodebuild -resolvePackageDependencies -scheme S", 1)), ["`Resolve Package Dependencies with xcodebuild` in job `package` differs from `Resolve Package Dependencies` in ci.yml's job `apple-platforms`"]),
        ("an unmarked step that is in neither is reported", differences(check.replace("      # Only in this workflow.\n", ""), ci), ["`Compare` in job `package`: ci.yml's job `spm-tests` has no step `Compare`"]),
        ("a missing job is reported", differences(check.replace("  example-package:", "  examples:"), ci), ["macos-build-check.yml has no job `example-package`"]),
    ]
    failures = [f"{description}: expected {expected}, was {actual}" for description, actual, expected in cases if actual != expected]
    for failure in failures:
        print(f"self-test failed: {failure}", file=sys.stderr)
    if not failures:
        print("check-macos-build-check: self-test passed")
    return 1 if failures else 0


def main():
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    with open(".github/workflows/macos-build-check.yml") as check, open(".github/workflows/ci.yml") as ci:
        found = differences(check.read(), ci.read())
    for difference in found:
        print(f"::error::{difference}. Copy the step again, or mark a step of this workflow's own with `{ONLY_HERE}` above its name.")
    if not found:
        print("Every copied step of macos-build-check.yml equals its step in ci.yml.")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
