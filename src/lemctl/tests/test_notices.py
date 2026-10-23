# Copyright 2026 Microsoft Corporation
# SPDX-License-Identifier: Apache-2.0

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "collect_notices", Path(__file__).parents[1] / "collect-notices.py"
)
NOTICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NOTICES)


class NoticesTest(unittest.TestCase):
    def test_install_keeps_notices_outside_pruned_documentation(self):
        package = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lemctl").write_text("binary fixture")
            notices = "Linked module\n\nCopyright holder\nLicense text\n"
            (root / "THIRD_PARTY_NOTICES").write_text(notices)
            subprocess.run(
                ["make", "-f", str(package / "Makefile"), "install", f"DESTDIR={root / 'package'}"],
                cwd=root, check=True, capture_output=True, text=True,
            )
            installed = root / "package/usr/share/lemctl/THIRD_PARTY_NOTICES"
            self.assertEqual(
                installed.read_text(), notices,
            )
            self.assertFalse(installed.is_relative_to(root / "package/usr/share/doc"))

    def test_linked_modules_nested_notices_and_toolchain(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = root / "module"
            package = module / "nested" / "pkg"
            package.mkdir(parents=True)
            (module / "LICENSE").write_text("MIT license and copyright")
            (package.parent / "NOTICE").write_text("Nested attribution")
            (module / "LICENSES").mkdir()
            goroot = root / "go"
            standard = goroot / "src" / "fmt"
            standard.mkdir(parents=True)
            (goroot / "LICENSE").write_text("Go BSD license and copyright")
            packages = [
                {"Dir": str(package), "Module": {
                    "Path": "example.com/module", "Version": "v1.2.3", "Dir": str(module)
                }},
                {"Dir": str(standard), "Standard": True},
            ]
            output = NOTICES.collect(packages, str(goroot), "go1.26.6")
            self.assertIn("example.com/module v1.2.3", output)
            self.assertIn("MIT license and copyright", output)
            self.assertIn("Nested attribution", output)
            self.assertIn("Go BSD license and copyright", output)
            self.assertEqual(output, NOTICES.collect(packages[::-1], str(goroot), "go1.26.6"))

    def test_missing_license_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            packages = [{"Dir": directory, "Module": {
                "Path": "example.com/unlicensed", "Dir": directory
            }}]
            with self.assertRaisesRegex(ValueError, "No license text"):
                NOTICES.collect(packages, directory, "go1.26.6")

    def test_symlinked_toolchain_sources_and_debian_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            goroot = root / "lib/go"
            goroot.mkdir(parents=True)
            sources = root / "share/go/src"
            (sources / "fmt").mkdir(parents=True)
            (goroot / "src").symlink_to(sources, target_is_directory=True)
            copyright = root / "doc/go/copyright"
            copyright.parent.mkdir(parents=True)
            copyright.write_text("Go upstream BSD license and copyright")
            packages = [{"Dir": str(goroot / "src/fmt"), "Standard": True}]
            output = NOTICES.collect(packages, str(goroot), "go1.26.7", {copyright})
            self.assertIn("Go toolchain go1.26.7", output)
            self.assertIn("Debian toolchain copyright", output)
            self.assertIn("Go upstream BSD license and copyright", output)
            with self.assertRaisesRegex(ValueError, "No license text"):
                NOTICES.collect(packages, str(goroot), "go1.26.7")

    def test_replacement_uses_replacement_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "COPYING").write_text("Replacement license")
            packages = [{"Dir": directory, "Module": {
                "Path": "example.com/original", "Replace": {
                    "Path": "example.com/replacement", "Version": "v2.0.0", "Dir": directory
                }
            }}]
            output = NOTICES.collect(packages, directory, "go1.26.6")
            self.assertIn("example.com/replacement v2.0.0", output)
            self.assertIn("Replacement license", output)

    def test_external_fips_standard_library_source_has_its_own_notice(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            goroot = root / "go"
            (goroot / "src/fmt").mkdir(parents=True)
            (goroot / "LICENSE").write_text("Go toolchain BSD license")
            cache = root / "modules"
            fips = cache / "golang.org/fips140@v1.0.0-c2097c7c"
            package = fips / "fips140/v1.0.0-c2097c7c"
            package.mkdir(parents=True)
            (fips / "LICENSE").write_text("FIPS module BSD license and copyright")
            packages = [
                {"Dir": str(goroot / "src/fmt"), "Standard": True},
                {"Dir": str(package), "Standard": True},
            ]
            output = NOTICES.collect(packages, str(goroot), "go1.26.7", modulecache=cache)
            self.assertIn("Go standard-library source golang.org/fips140@v1.0.0-c2097c7c", output)
            self.assertIn("FIPS module BSD license and copyright", output)
            self.assertIn("Go toolchain BSD license", output)
            (fips / "LICENSE").unlink()
            with self.assertRaisesRegex(ValueError, "No license text"):
                NOTICES.collect(packages, str(goroot), "go1.26.7", modulecache=cache)


if __name__ == "__main__":
    unittest.main()
