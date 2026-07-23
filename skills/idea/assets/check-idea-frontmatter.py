#!/usr/bin/env python3
"""Guard against the YAML-1.1 octal trap in IDEA frontmatter.

See skills/idea/SKILL.md § "ALWAYS QUOTE the id in frontmatter" for the full explanation. Short form:
a bare zero-padded id is OCTAL, so `id: 015` parses to the int 13 — silently. The same applies to
`related: [014, 003]`, `depends_on:`, `supersedes:` and `superseded_by:`.

Why a script and not just the inline snippet in SKILL.md: the trap is not a one-time migration. Some
`/idea` implementations still emit unquoted ids, so every new idea file can reintroduce it — this
needs to be re-runnable after each capture, not pasted once.

The failure is invisible without it. Nothing in the normal workflow parses this frontmatter, so it
surfaces only when a script or agent builds a status table — and then as *wrong data*, not an error.
It is also a sub-100 problem: ids 010-077 take a wrong value, 001-007 are right by value but wrong by
type, and anything containing an 8 or 9 stays a string by luck (8/9 are invalid octal). So a young
project is wrong on most of its ids and a mature one looks fine — it ages out before anyone notices.

The collision is the part that bites, and it is checked explicitly below. Raw, unquoted `012` -> 10
(int), while the real IDEA-010's *quoted* id is '010' (str) — different dict keys. But normalise to
3 digits — `str(v).zfill(3)`, the obvious move when building a status table — and 10 becomes '010',
colliding with the real IDEA-010.
One silently overwrites the other. This has been observed live in a consuming project, twice in one
tree.

Usage:  python3 <this-file> [project-root]     (default: cwd)
Exit 0 = clean, 1 = problems found. Suitable for a pre-commit hook or CI step.
"""
import pathlib
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: pip install pyyaml")

ID_FIELDS = ("related", "depends_on", "supersedes")


def main(argv: list[str]) -> int:
    root = pathlib.Path(argv[1]).resolve() if len(argv) > 1 else pathlib.Path.cwd()

    # Both idea locations per RULE_ideas-location-status: docs/ideas/ = backlog, docs/archive/ = rest.
    files = sorted(
        list((root / "docs/ideas").glob("IDEA-*.md"))
        + list((root / "docs/archive").glob("*/IDEA-*.md"))
    )
    if not files:
        print(f"no IDEA files under {root} — wrong project root?")
        return 1

    problems: list[str] = []
    seen: dict[str, str] = {}

    for path in files:
        name = path.name
        # Derive the expected id from the FILENAME: octal-immune, and correct even when the
        # frontmatter value has already mis-parsed.
        id_match = re.match(r"IDEA-(\d+)", name)
        if not id_match:
            problems.append(f"{name}: filename carries no numeric id — cannot derive the expected id")
            continue
        file_id = id_match.group(1)
        parts = path.read_text().split("---")
        if len(parts) < 3:
            problems.append(f"{name}: no `--- … ---` frontmatter block found")
            continue
        raw_front = parts[1]
        try:
            front = yaml.safe_load(raw_front) or {}
        except Exception as exc:  # noqa: BLE001 — report any parse failure, never crash the guard
            problems.append(
                f"{name}: frontmatter RAISES {exc.__class__.__name__} "
                "— an unquoted scalar containing ': ' (title, description, …) kills the whole block"
            )
            continue

        got = front.get("id")
        if not isinstance(got, str):
            problems.append(
                f'{name}: id is {type(got).__name__} {got!r}, not a string — write id: "{file_id}"'
            )
        elif got != file_id:
            problems.append(f"{name}: id {got!r} does not match the filename ({file_id!r})")

        # The collision only appears once ids are normalised — which is what any consumer does.
        key = str(got).zfill(3)
        if key in seen:
            problems.append(f"{name}: normalises to {key!r}, COLLIDING with {seen[key]}")
        seen[key] = name

        for field in ID_FIELDS:
            value = front.get(field)
            if value is None:
                continue
            for item in value if isinstance(value, list) else [value]:
                if not isinstance(item, str):
                    # NEVER suggest the parsed value back: for 010-077 it is ALREADY corrupted
                    # (raw `012` reached us as 10). The true digits survive only in the raw text.
                    raw_line = re.search(rf"^{field}:.*$", raw_front, flags=re.M)
                    raw = raw_line.group(0).split("#")[0].strip() if raw_line else "?"
                    problems.append(
                        f"{name}: {field} contains unquoted {item!r} — quote the ORIGINAL digits "
                        f"from the raw line ({raw}); "
                        "do NOT copy the parsed value, it is octal-corrupted"
                    )

        superseded_by = front.get("superseded_by")
        if superseded_by is not None and not isinstance(superseded_by, str):
            problems.append(f"{name}: superseded_by is unquoted {superseded_by!r}")

    if problems:
        print(f"{len(problems)} problem(s) in IDEA frontmatter:\n")
        for problem in problems:
            print(f"  {problem}")
        print('\nFix: quote the value — id: "015", related: ["014", "003"].')
        return 1

    print(
        f"OK — {len(files)} IDEA files: ids parse as strings matching their filenames, "
        "no collisions, all id fields quoted"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
