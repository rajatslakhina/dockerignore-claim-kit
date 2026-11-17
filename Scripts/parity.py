#!/usr/bin/env python3
"""Builds a throwaway Docker build context for every case, runs the classic `docker build` with
`FROM scratch` / `COPY . /ctx/`, reads which files reached the image, and writes the result as a Swift fixture.

Usage: python3 -I Scripts/parity.py Tests/DockerignoreClaimKitTests/ParityFixture.swift
Needs a running Docker daemon. Removes every image and container it makes.
"""
import io, json, os, subprocess, sys, tarfile, tempfile

DOCKERFILE = "FROM scratch\nCOPY . /ctx/\n"

# (name, .dockerignore text, files to create)
CASES = [
    ("root-only glob", "*.log\n", ["a.log", "logs/a.log", "app/b.log"]),
    ("root-only name", "node_modules\n", ["node_modules/x.js", "app/node_modules/y.js", "node_modules_backup/z"]),
    ("any-depth name", "**/node_modules\n", ["node_modules/x.js", "app/node_modules/y.js", "node_modules_backup/z"]),
    ("trailing slash", "logs/\n", ["logs/a.txt", "x/logs/b.txt"]),
    ("trailing slash file", "logs/\n", ["logs", "other"]),
    ("leading slash", "/build\n", ["build/a", "src/build/b"]),
    ("trailing comment", "node_modules # deps\n", ["node_modules/x", "node_modules # deps"]),
    ("indented comment", "  # note\na.txt\n", ["# note", "a.txt", "b.txt"]),
    ("comment", "# a.txt\nb.txt\n", ["a.txt", "b.txt"]),
    ("literal exception in skipped dir", "node_modules\n!node_modules/pkg/keep.txt\n",
     ["node_modules/pkg/keep.txt", "node_modules/pkg/other.txt", "node_modules/a.txt"]),
    ("wildcard exception in skipped dir", "node_modules\n!**/keep.txt\n",
     ["node_modules/pkg/keep.txt", "keep.txt", "src/keep.txt", "src/other.txt"]),
    ("mid wildcard exception", "node_modules\n!node_modules/*/keep.txt\n",
     ["node_modules/pkg/keep.txt", "node_modules/keep.txt", "node_modules/a/b/keep.txt"]),
    ("prefix glob with exception", "node_modules/**\n!node_modules/pkg/keep.txt\n",
     ["node_modules/pkg/keep.txt", "node_modules/pkg/other.txt", "node_modules/top.txt"]),
    ("prefix glob with wildcard exception", "node_modules/**\n!**/keep.txt\n",
     ["node_modules/keep.txt", "node_modules/pkg/keep.txt", "keep.txt"]),
    ("star contents with exception", "logs/*\n!logs/keep.log\n", ["logs/keep.log", "logs/a.log", "logs/sub/b.log"]),
    ("dir then literal exception", "logs\n!logs/keep.log\n", ["logs/keep.log", "logs/a.log"]),
    ("allow list", "*\n!src\n", ["src/a.go", "src/sub/b.go", "README.md", "go.mod"]),
    ("allow list glob", "*\n!src/**\n", ["src/a.go", "src/sub/b.go", "README.md"]),
    ("allow list nested", "*\n!src/main\n", ["src/main/a.go", "src/test/b.go", "README.md"]),
    ("exception after", "*.md\n!README.md\n", ["README.md", "docs.md", "docs/x.md"]),
    ("exception before", "!README.md\n*.md\n", ["README.md", "docs.md"]),
    ("anchored star", "doc/*.txt\n", ["doc/a.txt", "doc/server/b.txt", "x/doc/c.txt"]),
    ("double star middle", "doc/**/*.txt\n", ["doc/a.txt", "doc/server/b.txt", "doc/a/b/c.txt", "x/doc/d.txt"]),
    ("double star lead", "**/*.txt\n", ["a.txt", "d/b.txt", "d/e/c.txt", "a.md"]),
    ("double star zero", "a/**/b\n", ["a/b", "a/x/b", "a/x/y/b", "b"]),
    ("double star temp", "**/temp*\n", ["temp1", "x/temp2", "x/y/tempz", "x/atemp"]),
    ("one level", "*/temp*\n", ["temp1", "x/temp2", "x/y/temp3"]),
    ("question", "temp?\n", ["temp1", "temp12", "x/temp1"]),
    ("question alone", "?\n", ["a", "ab", "d/a"]),
    ("range", "[a-c].txt\n", ["a.txt", "b.txt", "d.txt"]),
    ("negated class", "[^a].txt\n", ["a.txt", "b.txt"]),
    ("bang class", "[!a].txt\n", ["!.txt", "a.txt", "b.txt"]),
    ("letter case", "README.md\n", ["readme.md", "other.md"]),
    ("dotfile star", "*.env\n", [".env", "a.env", "x/.env"]),
    ("dotfile prefix", ".env*\n", [".env", ".env.local", "x/.env"]),
    ("dockerfile excluded", "Dockerfile\n", ["a.txt"]),
    ("dockerignore excluded", ".dockerignore\n", ["a.txt"]),
    ("dot", ".\n", ["a.txt", "d/b.txt"]),
    ("dot slash", "./a.txt\n", ["a.txt", "x/a.txt"]),
    ("dot dot", "a/../b.txt\n", ["b.txt", "a/b.txt"]),
    ("leading slash file", "/a.txt\n", ["a.txt", "x/a.txt"]),
    ("trailing spaces", "a.txt   \n", ["a.txt", "b.txt"]),
    ("spaced exception", "*.txt\n  !a.txt\n", ["a.txt", "b.txt"]),
    ("space after bang", "*.txt\n! a.txt\n", ["a.txt", "b.txt"]),
    ("trailing double star", "foo/**\n", ["foo/a", "foo/b/c", "food"]),
    ("lead double star name", "**foo\n", ["foo", "xfoo", "d/xfoo", "foo2"]),
    ("escaped star", "a\\*b\n", ["a*b", "axb"]),
    ("escaped dot", "a\\.b\n", ["a.b", "axb"]),
    ("dot literal", "a.b\n", ["a.b", "axb"]),
    ("braces", "{a,b}.txt\n", ["{a,b}.txt", "a.txt"]),
    ("plus", "a+b\n", ["a+b", "aab"]),
    ("caret exact", "^a\n", ["^a", "a"]),
    ("caret in glob", "a^*\n", ["a^b", "ab"]),
    ("caret lead glob", "^a*\n", ["^ab", "ab"]),
    ("closing bracket", "a]*\n", ["a]b", "ab"]),
    ("crlf", "a.txt\r\nb.txt\r\n", ["a.txt", "b.txt", "c.txt"]),
    ("bom", "﻿a.txt\n", ["a.txt", "b.txt"]),
    ("git dir", ".git\n", [".git/config", "sub/.git/HEAD"]),
    ("git dir any depth", "**/.git\n", [".git/config", "sub/.git/HEAD"]),
    ("python", "*.pyc\n__pycache__\n", ["a.pyc", "pkg/b.pyc", "__pycache__/c", "pkg/__pycache__/d"]),
    ("nested dockerignore", "*.md\n", ["app/.dockerignore", "app/a.log", "app/b.md", "c.md"]),
    ("star slash", "*/\n", ["a.txt", "d/b.txt"]),
    ("exception dir then file", "dist\n!dist\n", ["dist/a.js"]),
    ("deep literal exception", "a\n!a/b/c.txt\n", ["a/b/c.txt", "a/b/d.txt", "a/e.txt"]),
    ("sub exclude", "app/node_modules\n", ["app/node_modules/x", "node_modules/y"]),
    ("secrets", "secrets/*.pem\n", ["secrets/a.pem", "secrets/x/b.pem", "a.pem"]),
    ("unclosed bracket", "[a\n", ["a"]),
    ("bang alone", "!\n", ["a"]),
    ("trailing backslash", "a\\\n", ["a"]),
]

NESTED = {"nested dockerignore": {"app/.dockerignore": "*.log\n"}}


def run(args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def build(number, name, ignore, files):
    with tempfile.TemporaryDirectory(prefix="dic-parity-") as root:
        for path in files:
            full = os.path.join(root, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(NESTED.get(name, {}).get(path, path + "\n"))
        with open(os.path.join(root, "Dockerfile"), "w") as handle:
            handle.write(DOCKERFILE)
        with open(os.path.join(root, ".dockerignore"), "w", newline="") as handle:
            handle.write(ignore)
        tag = f"dic-parity:{number}"
        built = run(["docker", "build", "-q", "-t", tag, root])
        if built.returncode != 0:
            return None
        container = run(["docker", "create", tag, "/none"]).stdout.strip()
        exported = subprocess.run(["docker", "export", container], capture_output=True).stdout
        run(["docker", "rm", container])
        run(["docker", "rmi", tag])
        names = tarfile.open(fileobj=io.BytesIO(exported)).getmembers()
        present = {m.name[len("ctx/"):] for m in names if m.isfile() and m.name.startswith("ctx/")}
        return {path: path in present for path in files + ["Dockerfile", ".dockerignore"]}


def swift(text):
    """A Swift string literal."""
    escapes = {'"': '\\"', "\\": "\\\\", "\n": "\\n", "\r": "\\r"}
    return '"' + "".join(escapes.get(c, c) if c in escapes or 32 <= ord(c) < 127 else "\\u{%x}" % ord(c)
                         for c in text) + '"'


def main(out):
    lines = ["// Written by Scripts/parity.py from the classic `docker build` (Docker CLI "
             + run(["docker", "version", "--format", "{{.Client.Version}}"]).stdout.strip() + "). Do not edit.",
             "", "enum ParityFixture {", "    static let cases: [ParityCase] = ["]
    for number, (name, ignore, files) in enumerate(CASES):
        result = build(number, name, ignore, files)
        if result is None:
            lines.append(f"        ParityCase(name: {swift(name)}, ignore: {swift(ignore)}, buildFails: true, paths: [:]),")
            continue
        pairs = ", ".join(f"{swift(p)}: {'true' if v else 'false'}" for p, v in sorted(result.items()))
        lines.append(f"        ParityCase(name: {swift(name)}, ignore: {swift(ignore)}, buildFails: false,")
        lines.append(f"                   paths: [{pairs}]),")
    lines += ["    ]", "}", ""]
    with open(out, "w") as handle:
        handle.write("\n".join(lines))
    print(f"{len(CASES)} contexts, {sum(len(c[2]) + 2 for c in CASES)} paths -> {out}")


if __name__ == "__main__":
    main(sys.argv[1])
