#!/usr/bin/env python3
"""Create the Vitis 2024.2 CPU Polling app and its bootable bitstream."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

import vitis


HERE = Path(__file__).resolve().parent
CPU_POLLING_ROOT = HERE.parent
REPO_ROOT = CPU_POLLING_ROOT.parents[1]
SOURCE_XSA = CPU_POLLING_ROOT / "hw" / "cpu_polling_reference.xsa"
SOURCE_SW = CPU_POLLING_ROOT / "sw"
ARTIFACTS = CPU_POLLING_ROOT / "vitis_artifacts"
IMPL_DIR = (
    REPO_ROOT
    / "comparison"
    / "common"
    / "build"
    / "base_soc"
    / "edgescope_comparison_base.runs"
    / "impl_1"
)
IMPLEMENTED_MMI = IMPL_DIR / "base_soc_wrapper.mmi"
IMPLEMENTED_BIT = IMPL_DIR / "base_soc_wrapper.bit"
FROZEN_MMI = CPU_POLLING_ROOT / "hw" / "cpu_polling_reference.mmi"
FROZEN_BIT = CPU_POLLING_ROOT / "hw" / "cpu_polling_reference.bit"

# Unified Vitis 2024.2 rejects component paths containing spaces. Stage the
# workspace under TMPDIR.  A caller can select another writable, no-space base
# directory with EDGESCOPE_VITIS_RUNTIME_BASE.  UID and repository hash avoid
# collisions between users and independent checkouts on a shared Ubuntu host.
RUNTIME_BASE = Path(
    os.environ.get(
        "EDGESCOPE_VITIS_RUNTIME_BASE",
        tempfile.gettempdir(),
    )
).expanduser().resolve()
REPO_TAG = hashlib.sha256(str(REPO_ROOT).encode("utf-8")).hexdigest()[:8]
RUNTIME_ROOT = (
    RUNTIME_BASE
    / "cpu_polling_vitis_build_v3_{}_{}".format(os.getuid(), REPO_TAG)
)
RUNTIME_INPUT = RUNTIME_ROOT / "input"
WORKSPACE = RUNTIME_ROOT / "workspace"
XSA = RUNTIME_INPUT / "cpu_polling_reference.xsa"
SW = RUNTIME_INPUT / "sw"

PLATFORM_NAME = "cpu_polling_platform"
DOMAIN_NAME = "standalone_microblaze_riscv_0"
APP_NAME = "cpu_polling_app"
CPU_NAME = "microblaze_riscv_0"

APP_SOURCES = [
    "cpu_polling_reference.c",
    "cpu_polling_engine.c",
    "cpu_polling_engine.h",
    "cpu_polling_config.h",
]


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def xsa_member_hashes():
    """Return the one MMI and bit hash embedded in the current XSA."""
    try:
        with zipfile.ZipFile(SOURCE_XSA) as archive:
            mmi_names = [
                name for name in archive.namelist()
                if name.lower().endswith(".mmi")
            ]
            bit_names = [
                name for name in archive.namelist()
                if name.lower().endswith(".bit")
            ]
            if len(mmi_names) != 1 or len(bit_names) != 1:
                raise RuntimeError(
                    "Expected exactly one MMI and one bitstream in {}, "
                    "found MMI={} BIT={}".format(
                        SOURCE_XSA, mmi_names, bit_names
                    )
                )
            return (
                hashlib.sha256(archive.read(mmi_names[0])).hexdigest(),
                hashlib.sha256(archive.read(bit_names[0])).hexdigest(),
            )
    except zipfile.BadZipFile as exc:
        raise RuntimeError("Invalid XSA archive: {}".format(SOURCE_XSA)) from exc


def select_implementation_inputs():
    """Select MMI/raw-bit files proven to belong to the current XSA."""
    xsa_mmi_hash, xsa_bit_hash = xsa_member_hashes()
    candidates = (
        (IMPLEMENTED_MMI, IMPLEMENTED_BIT),
        (FROZEN_MMI, FROZEN_BIT),
    )
    found_pairs = []
    for mmi, bitstream in candidates:
        if not mmi.is_file() or not bitstream.is_file():
            continue
        found_pairs.append((mmi, bitstream))
        if (
            sha256_file(mmi) == xsa_mmi_hash
            and sha256_file(bitstream) == xsa_bit_hash
        ):
            return mmi, bitstream

    if not found_pairs:
        raise FileNotFoundError(
            "No CPU Polling implementation MMI/raw-bit pair was found. "
            "Run comparison/cpu_polling/hw/block_design.tcl and "
            "build_all.tcl before Vitis."
        )
    compared = "\n  ".join(
        "{} + {}".format(mmi, bitstream)
        for mmi, bitstream in found_pairs
    )
    raise RuntimeError(
        "The available MMI/raw-bit files do not match the current XSA:\n  "
        + compared
    )


def require_inputs():
    required = [SOURCE_XSA]
    required.extend(SOURCE_SW / source_name for source_name in APP_SOURCES)
    missing = [path for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            "Required CPU Polling inputs are missing:\n  "
            + "\n  ".join(str(path) for path in missing)
        )
    updatemem = shutil.which("updatemem")
    if not updatemem:
        raise FileNotFoundError(
            "updatemem was not found on PATH. Source the Vitis 2024.2 "
            "settings64.sh before running this script."
        )
    if any(character.isspace() for character in str(RUNTIME_ROOT)):
        raise RuntimeError(
            "Vitis staging path contains whitespace: {}. Set "
            "EDGESCOPE_VITIS_RUNTIME_BASE to a no-space directory.".format(
                RUNTIME_ROOT
            )
        )
    mmi, bitstream = select_implementation_inputs()
    return updatemem, mmi, bitstream


def stage_inputs():
    # A clean workspace makes the platform/BSP derive from this run's XSA.
    if RUNTIME_ROOT.exists():
        shutil.rmtree(RUNTIME_ROOT)
    SW.mkdir(parents=True)
    WORKSPACE.mkdir(parents=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    shutil.copy2(SOURCE_XSA, XSA)
    for source_name in APP_SOURCES:
        shutil.copy2(SOURCE_SW / source_name, SW / source_name)


def select_app_elf():
    elf_files = sorted((WORKSPACE / APP_NAME).rglob("*.elf"))
    preferred = [
        path for path in elf_files if path.name == "{}.elf".format(APP_NAME)
    ]
    if len(preferred) != 1:
        raise FileNotFoundError(
            "Expected exactly one {}.elf under {}, found: {}".format(
                APP_NAME, WORKSPACE / APP_NAME, elf_files
            )
        )
    return preferred[0]


def create_bootable_bit(updatemem, mmi, raw_bit, elf):
    processor = ET.parse(mmi).find(".//Processor")
    if processor is None or not processor.get("InstPath"):
        raise RuntimeError("Processor InstPath was not found in {}".format(mmi))

    output = ARTIFACTS / "cpu_polling_app.bit"
    subprocess.run(
        [
            updatemem,
            "-meminfo",
            str(mmi),
            "-data",
            str(elf),
            "-bit",
            str(raw_bit),
            "-proc",
            processor.get("InstPath"),
            "-out",
            str(output),
            "-force",
        ],
        check=True,
    )
    print("VITIS_BUILD_PASS bootable_bit={}".format(output))
    return output


def main() -> None:
    updatemem, mmi, raw_bit = require_inputs()
    stage_inputs()

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WORKSPACE))
        print("Creating clean platform from {}".format(XSA))
        platform = client.create_platform_component(
            name=PLATFORM_NAME,
            hw_design=str(XSA),
            os="standalone",
            cpu=CPU_NAME,
            domain_name=DOMAIN_NAME,
            generate_dtb=False,
        )
        domain = platform.get_domain(DOMAIN_NAME)
        domain.set_config("os", "standalone_stdin", "axi_uartlite_0")
        domain.set_config("os", "standalone_stdout", "axi_uartlite_0")
        platform.build()

        platform_xpfm = client.find_platform_in_repos(PLATFORM_NAME)
        app = client.create_app_component(
            name=APP_NAME,
            platform=platform_xpfm,
            domain=DOMAIN_NAME,
            template="empty_application",
        )
        app.import_files(
            from_loc=str(SW),
            files=APP_SOURCES,
            dest_dir_in_cmp="src",
        )
        app.set_app_config(
            key="USER_COMPILE_OPTIMIZATION_LEVEL",
            values="-O2",
        )
        print(
            "Optimization:",
            app.get_app_config(key="USER_COMPILE_OPTIMIZATION_LEVEL"),
        )
        app.build()

        source_elf = select_app_elf()
        artifact_elf = ARTIFACTS / "cpu_polling_app.elf"
        shutil.copy2(source_elf, artifact_elf)
        print("VITIS_BUILD_PASS elf={}".format(artifact_elf))
        create_bootable_bit(
            updatemem, mmi, raw_bit, artifact_elf
        )

        print("VITIS_BUILD_PASS workspace={}".format(WORKSPACE))
        print("VITIS_BUILD_PASS platform={}".format(PLATFORM_NAME))
        print("VITIS_BUILD_PASS application={}".format(APP_NAME))
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
