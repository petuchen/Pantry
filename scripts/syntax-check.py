#!/usr/bin/env python3
"""Syntax-only check of every Swift file using tree-sitter (no compiler needed).

This catches typos, unbalanced braces and malformed statements. It does NOT type-check:
a real `swift build` / `swift test` on macOS (see CI) remains the source of truth.

    pip install tree-sitter tree-sitter-swift
    python3 scripts/syntax-check.py
"""
import pathlib
import sys

import tree_sitter_swift
from tree_sitter import Language, Parser

parser = Parser(Language(tree_sitter_swift.language()))
root = pathlib.Path(__file__).resolve().parent.parent
failures = 0
files = sorted(list((root / "Sources").rglob("*.swift")) + list((root / "Tests").rglob("*.swift")) + [root / "Package.swift"])

def first_error(node):
    if node.type == "ERROR" or node.is_missing:
        return node
    for child in node.children:
        if child.has_error or child.is_missing:
            found = first_error(child)
            if found is not None:
                return found
    return None

for path in files:
    source = path.read_bytes()
    tree = parser.parse(source)
    if tree.root_node.has_error:
        failures += 1
        err = first_error(tree.root_node) or tree.root_node
        line = err.start_point[0] + 1
        text = source.decode("utf8", "replace").splitlines()[line - 1].strip()
        print(f"SYNTAX  {path.relative_to(root)}:{line}: {text[:100]}")

print(f"{len(files)} files checked, {failures} with syntax errors")
sys.exit(1 if failures else 0)
