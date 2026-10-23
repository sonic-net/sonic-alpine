#!/usr/bin/env python3
# Copyright 2026 Microsoft Corporation
# SPDX-License-Identifier: Apache-2.0

import json
from pathlib import Path
import subprocess
import sys


def legal_files(directory):
    prefixes = ("LICENSE", "COPYING", "NOTICE", "COPYRIGHT", "AUTHORS", "PATENTS")
    return {
        path for path in directory.iterdir()
        if path.is_file() and path.name.upper().startswith(prefixes)
    }


def collect(packages, goroot, goversion, toolchain_notices=(), modulecache=None):
    components = {}
    for package in packages:
        if not package.get("Dir"):
            continue
        if package.get("Standard"):
            name, root = f"Go toolchain {goversion}", Path(goroot)
            directory = Path(package["Dir"]).absolute()
            if not directory.is_relative_to(root.absolute()):
                if not modulecache:
                    raise ValueError(f"Standard package outside GOROOT: {directory}")
                cache = Path(modulecache).absolute()
                parts = directory.relative_to(cache).parts
                boundary = next((i for i, part in enumerate(parts) if "@" in part), None)
                if boundary is None:
                    raise ValueError(f"No module identity for external standard package {directory}")
                root = cache.joinpath(*parts[:boundary + 1])
                name = "Go standard-library source " + "/".join(parts[:boundary + 1])
        else:
            module = package["Module"]
            module = module.get("Replace", module)
            name = module["Path"] + " " + module.get("Version", "(local source)")
            root = Path(module["Dir"])
        root = root.absolute()
        paths = components.setdefault((name, root), set())
        if root == Path(goroot).absolute():
            paths.update(toolchain_notices)
        directory = Path(package["Dir"]).absolute()
        directory.relative_to(root)
        while True:
            paths.update(legal_files(directory))
            if directory == root:
                break
            directory = directory.parent

    sections = ["Notices for the source packages linked into lemctl.\n"]
    for (name, root), paths in sorted(components.items()):
        if not any(
            path.name.upper().startswith(("LICENSE", "COPYING")) or path in toolchain_notices
            for path in paths
        ):
            raise ValueError(f"No license text found for linked component {name} in {root}")
        sections.append(f"\n{'=' * 72}\n{name}\n")
        for path in sorted(paths):
            label = path.relative_to(root) if path.is_relative_to(root) else "Debian toolchain copyright"
            sections.append(f"\n--- {label} ---\n")
            sections.append(path.read_text(encoding="utf-8").rstrip() + "\n")
    return "".join(sections)


def main():
    output = subprocess.check_output(
        ["go", "list", "-buildvcs=false", "-deps", "-json", "./cmd/lemctl"], text=True
    )
    decoder = json.JSONDecoder()
    packages = []
    while output.strip():
        output = output.lstrip()
        package, end = decoder.raw_decode(output)
        packages.append(package)
        output = output[end:]
    environment = json.loads(subprocess.check_output(
        ["go", "env", "-json", "GOROOT", "GOVERSION", "GOMODCACHE"], text=True
    ))
    goroot, goversion = environment["GOROOT"], environment["GOVERSION"]
    toolchain_notices = set()
    if not any(path.name.upper().startswith(("LICENSE", "COPYING")) for path in legal_files(Path(goroot))):
        owners = subprocess.check_output(
            ["dpkg-query", "--search", str(Path(goroot) / "bin/go")], text=True
        )
        for line in owners.splitlines():
            package = line.rsplit(": ", 1)[0].split(":", 1)[0]
            toolchain_notices.add(Path("/usr/share/doc") / package / "copyright")
    Path(sys.argv[1]).write_text(
        collect(packages, goroot, goversion, toolchain_notices, environment["GOMODCACHE"]),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
