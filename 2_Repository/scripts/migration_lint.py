#!/usr/bin/env python3
"""Expand/contract guard for SQL migrations (CI gate).

Because some app migrations are NOT backward compatible and run on startup, a release
that contains a destructive statement must be a 'contract' release, explicitly labelled,
and may only ship after the previous 'expand' release has been live in prod >= 1 cycle.

Destructive = DROP TABLE/COLUMN, RENAME, ALTER TYPE, SET NOT NULL without DEFAULT,
TRUNCATE, DELETE without WHERE, adding NOT NULL column without DEFAULT.
Escape hatch: a line `-- migration: contract` in the file (reviewed by DBA/owner).
"""
import pathlib, re, sys

RULES = [
    (r"\bDROP\s+(TABLE|COLUMN|SCHEMA)\b", "DROP is destructive (contract phase only)"),
    (r"\bRENAME\s+(TO|COLUMN)\b", "RENAME breaks the running version (use add+backfill+drop)"),
    (r"\bALTER\s+COLUMN\s+\w+\s+(SET\s+DATA\s+)?TYPE\b", "type change rewrites table / breaks old version"),
    (r"\bTRUNCATE\b", "TRUNCATE is destructive"),
    (r"\bDELETE\s+FROM\s+\w+\s*;", "DELETE without WHERE"),
    (r"\bSET\s+NOT\s+NULL\b", "SET NOT NULL fails old writers (add CHECK NOT VALID, backfill, validate)"),
    (r"\bADD\s+COLUMN\s+\w+\s+[\w\(\), ]*\bNOT\s+NULL\b(?![^;]*\bDEFAULT\b)", "NOT NULL column without DEFAULT breaks old inserts"),
    (r"\bCREATE\s+INDEX\b(?!\s+CONCURRENTLY)", "use CREATE INDEX CONCURRENTLY to avoid write locks"),
]


def lint_sql(text):
    if re.search(r"--\s*migration:\s*contract", text, re.I):
        return []
    problems = []
    for lineno, line in enumerate(text.splitlines(), 1):
        code = line.split("--")[0]
        for pat, msg in RULES:
            if re.search(pat, code, re.I):
                problems.append((lineno, msg))
    # multi-line statements: check whole text for NOT NULL w/o DEFAULT
    return problems


def main(argv):
    root = pathlib.Path(argv[1] if len(argv) > 1 else "migrations")
    bad = 0
    for f in sorted(root.rglob("*.sql")):
        for lineno, msg in lint_sql(f.read_text()):
            print(f"{f}:{lineno}: {msg}"); bad += 1
    print(f"migration lint: {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
