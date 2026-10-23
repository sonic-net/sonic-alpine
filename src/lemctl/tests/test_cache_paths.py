# Copyright 2026 Microsoft Corporation
# SPDX-License-Identifier: Apache-2.0

from pathlib import Path
import subprocess
import unittest


class CachePathsTest(unittest.TestCase):
    def test_sonic_submodule_hash_inputs_resolve_from_package_directory(self):
        platform = Path(__file__).resolve().parents[3]
        package = platform / "src/lemctl"
        makefile = (
            f"PLATFORM_PATH := {platform}\n"
            "CONFIGURED_ARCH := amd64\n"
            f"include {platform}/lemctl.mk\n"
            f"include {platform}/lemctl.dep\n"
            "print:\n"
            "\t@printf '%s\\n' $(patsubst $($(LEMCTL)_SRC_PATH)/%,%,$($(LEMCTL)_SMDEP_FILES))\n"
        )
        paths = subprocess.check_output(
            ["make", "--no-print-directory", "-f", "-", "print"], input=makefile, text=True
        ).splitlines()
        self.assertIn("../libsai-grpc/lemming/go.mod", paths)
        result = subprocess.run(
            ["xargs", "git", "hash-object"], cwd=package,
            input="\n".join(paths) + "\n", text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(result.stdout.splitlines()), len(paths))

    def test_patch_and_notice_generator_are_cache_inputs(self):
        platform = Path(__file__).resolve().parents[3]
        makefile = (
            f"PLATFORM_PATH := {platform}\n"
            "CONFIGURED_ARCH := amd64\n"
            f"include {platform}/lemctl.mk\n"
            f"include {platform}/lemctl.dep\n"
            "print:\n"
            "\t@printf '%s\\n' $($(LEMCTL)_DEP_FILES)\n"
        )
        paths = subprocess.check_output(
            ["make", "--no-print-directory", "-f", "-", "print"], input=makefile, text=True
        ).splitlines()
        for name in (
            "patches/0001-luciusctl-transport-policy.patch",
            "collect-notices.py",
            "debian/copyright",
        ):
            self.assertIn(str(platform / "src/lemctl" / name), paths)


if __name__ == "__main__":
    unittest.main()
