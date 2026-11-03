#!/usr/bin/env python3
"""Run the actual platform-independent sources/tests using Swift on Linux/macOS.

This does not build the iOS app or substitute for its Simulator tests.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--swift", default="swift")
parser.add_argument("--repeat", type=int, default=1)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
sources = ["Concurrency/AsyncOperation.swift", "Concurrency/TransferPipeline.swift", "Concurrency/SecretMigration.swift",
           "Onboarding/QuickConnectParser.swift", "Models/ServerProfile.swift",
           "Models/AppSettings.swift", "Models/SettingsCodec.swift",
           "Storage/JSONStore.swift", "Vault/SSHWire.swift"]
tests = ["AsyncOperationTests.swift", "TransferPipelineTests.swift",
         "QuickConnectParserTests.swift", "StoresTests.swift", "SettingsCodecTests.swift", "SecretMigrationTests.swift"]
with tempfile.TemporaryDirectory(prefix="terminal-checks-") as folder:
    package = Path(folder)
    for directory in ["Sources/Terminal", "Tests/TerminalTests"]:
        (package / directory).mkdir(parents=True)
    for source in sources:
        shutil.copyfile(root / "Terminal" / source, package / "Sources/Terminal" / Path(source).name)
    for test in tests:
        shutil.copyfile(root / "TerminalTests" / test, package / "Tests/TerminalTests" / test)
    (package / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TerminalChecks", targets: [
    .target(name: "Terminal"),
    .testTarget(name: "TerminalTests", dependencies: ["Terminal"])
], swiftLanguageModes: [.v5])
''')
    environment = dict(os.environ,
        CLANG_MODULE_CACHE_PATH=str(package / "clang-cache"),
        SWIFTPM_MODULECACHE_OVERRIDE=str(package / "module-cache"))
    for iteration in range(args.repeat):
        print(f"Portable test iteration {iteration + 1}/{args.repeat}", flush=True)
        subprocess.run([args.swift, "test", "--package-path", str(package),
            "--cache-path", str(package / "cache"), "--config-path", str(package / "config"),
            "--security-path", str(package / "security"), "--jobs", "2"],
            env=environment, check=True)
