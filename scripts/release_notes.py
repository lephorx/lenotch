#!/usr/bin/env python3
"""Release notes for a tag: release-notes/<tag>.md if it exists, otherwise the commit
subjects since the previous tag (internal ones left out).

Writes build/release-notes.md (GitHub release) and build/Lenotch.html, which
generate_appcast --embed-release-notes puts into the Sparkle update dialog.

    scripts/release_notes.py v2.8
"""
import html
import pathlib
import re
import subprocess
import sys

INTERNAL = re.compile(r"agents\.md|claude\.md|gitignore|readme|workflow|\bci\b|^merge\b|bump version", re.I)


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def commit_notes(tag):
    try:
        previous = git("describe", "--tags", "--abbrev=0", f"{tag}^")
        span = f"{previous}..{tag}"
    except subprocess.CalledProcessError:
        span = tag
    subjects = git("log", "--no-merges", "--reverse", "--pretty=%s", span).splitlines()
    # A change and its revert cancel out.
    reverted = {m.group(1) for s in subjects if (m := re.match(r'Revert "(.+)"$', s))}
    return [s for s in subjects
            if s not in reverted and not s.startswith("Revert ") and not INTERNAL.search(s)]


def main():
    tag = sys.argv[1]
    out = pathlib.Path("build")
    out.mkdir(exist_ok=True)
    custom = pathlib.Path("release-notes") / f"{tag}.md"
    if custom.exists():
        markdown = custom.read_text().strip()
        items = [line[2:] for line in markdown.splitlines() if line.startswith(("- ", "* "))]
    else:
        items = commit_notes(tag) or ["Small fixes and improvements."]
        markdown = "\n".join(f"- {item}" for item in items)
    (out / "release-notes.md").write_text(markdown + "\n")
    # **bold** in the notes becomes <strong> in Sparkle's update dialog.
    bold = re.compile(r"[*][*](.+?)[*][*]")
    lis = "".join("<li>" + bold.sub(r"<strong>\1</strong>", html.escape(item)) + "</li>" for item in items)
    (out / "Lenotch.html").write_text(f"<h2>What's new in Lenotch {html.escape(tag.lstrip('v'))}</h2><ul>{lis}</ul>\n")
    print(markdown)


if __name__ == "__main__":
    main()
