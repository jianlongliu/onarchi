#!/usr/bin/env python3
"""Check tracked content for the things that must never enter this repo.

Usage:
    scripts/check-sanitized.py [--quiet]

Exits 1 when something is found. Run it before committing docs or configs:
`.gitignore` keeps known-sensitive *files* out, but nothing stops a secret being
pasted into a file that is legitimately tracked.

Scope is deliberately narrow. A scanner that reports 198 findings is a scanner
people learn to pipe to `cat`, which is worse than not having one — so the
placeholder rules only apply where a real identifier would actually live: this
machine's own configuration and documentation, never test fixtures, and never
anything under a `fixtures/` path.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

PATTERNS = [
    ("GitHub token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})")),
    ("API key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}")),
    ("AWS access key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY(?: BLOCK)?-----")),
    ("JWT", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
]

# A value assigned to a credential-shaped name, where the value looks like a
# literal rather than a variable, a placeholder, or a redaction.
CREDENTIAL = re.compile(
    r"""(?ix)
    \b(?:api[_-]?key|secret|token|password|passwd|access[_-]?key)
    \b\s*[=:]\s*
    ["']?(?!\$|"|<|>|\.\.\.|xxx|example|placeholder|your|redacted|dummy|fake|test)
    [A-Za-z0-9_./+=-]{24,}["']?
    """
)

# A subscription URL hands out proxy nodes. The node configs themselves stay
# out via .gitignore; a link pasted into a doc does not.
SUBSCRIPTION = re.compile(
    r"https?://[^\s)\"'`]+/(?:sub|subscribe|subscription|api/v1/client/subscribe)[^\s)\"'`]*", re.I
)

# Only this machine's own configuration can leak this machine's identifiers.
# Ported upstream source and tests are not candidates, and neither are fixtures,
# which invent users on purpose. `manual/` is excluded because a documentation
# example address is not a leak — the rule applies where a real value would be
# consulted, not where a placeholder is being explained.
SELF_OWNED = ("docs/", "local-config/", "niri-config/", "etc/", "agents/")
FIXTURE_MARKER = ("test/", "fixtures/")

ALLOWED_HOME = {"you", "me", "u", "user", "username", "example", "owner", "someone", "test-user"}
# 172.16/12 covers Docker's own defaults (172.17.0.1 bridge, 172.18.0.1 compose),
# which are the same on every machine and identify nothing.
LAN_IP = re.compile(
    r"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"
)
DOCKER_DEFAULT = re.compile(r"\b172\.(?:1[789]|2[0-9]|3[01])\.0\.1\b")

# Documents that describe the rule cannot be held to it. The remaining entries
# are upstream's own files, kept byte-identical to `bc220e70` on purpose: the
# Chromium device-flow client secret is hardcoded upstream (a public OAuth
# client, not a user's credential), and the other two are test data that spells
# out a token to prove sanitisation removes it. Exempting them by path keeps the
# scan meaningful — rewriting upstream files to satisfy a linter is how a port
# stops being replayable.
EXEMPT = {
    "scripts/check-sanitized.py",
    "agents/skills/sanitization.md",
    "AGENTS.md",
    "bin/omarchy-install-chromium-google-account",
    "test/shell.d/notifications/logic.cjs",
    "test/shell.d/update-stay-awake-security-test.sh",
}


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [f for f in out.decode().split("\0") if f]


def candidate_files():
    """Tracked files plus anything new that git does not ignore yet.

    A pre-commit scan that only reads `git ls-files` cannot see the file being
    added, which is precisely the one that has not been reviewed.
    """
    out = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        capture_output=True,
        check=True,
    ).stdout
    return sorted({f for f in out.decode().split("\0") if f and (ROOT / f).is_file()})


def is_binary(path):
    try:
        return b"\0" in (ROOT / path).open("rb").read(8000)
    except OSError:
        return True


def self_owned(path):
    if path.startswith(FIXTURE_MARKER):
        return False
    return path.startswith(SELF_OWNED)


def find(paths):
    hits = []
    for path in paths:
        if path in EXEMPT or is_binary(path):
            continue
        try:
            lines = (ROOT / path).read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        owned = self_owned(path)
        for number, line in enumerate(lines, 1):
            for label, pattern in PATTERNS:
                if pattern.search(line):
                    hits.append((path, number, label))
            if CREDENTIAL.search(line):
                hits.append((path, number, "credential assignment"))
            if SUBSCRIPTION.search(line):
                hits.append((path, number, "proxy subscription link"))
            if not owned:
                continue
            home = re.search(r"/home/([A-Za-z0-9_.-]+)", line)
            if home and home.group(1) not in ALLOWED_HOME:
                hits.append((path, number, f"real home directory ({home.group(1)})"))
            if LAN_IP.search(line) and not DOCKER_DEFAULT.search(line):
                hits.append((path, number, "LAN address"))
    return hits


def main():
    quiet = "--quiet" in sys.argv
    paths = candidate_files()
    hits = find(paths)

    if not hits:
        if not quiet:
            print(f"ok - {len(paths)} tracked files, no credentials or private identifiers")
        return 0

    for path, number, label in hits:
        print(f"{path}:{number}: {label}")
    print(f"\n{len(hits)} finding(s) in {len(paths)} tracked files", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
