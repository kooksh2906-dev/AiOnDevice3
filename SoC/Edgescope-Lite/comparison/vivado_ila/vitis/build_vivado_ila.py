#!/usr/bin/env python3
"""Create and build the Vivado-ILA comparison Vitis 2024.2 application."""

import argparse
from pathlib import Path
import shutil
import subprocess
import time
import xml.etree.ElementTree as ET

import vitis


HERE = Path(__file__).resolve().parent
C_ROOT = HERE.parent
SOURCE_XSA = C_ROOT / "hw" / "vivado_ila_reference.xsa"
SOURCE_SW = C_ROOT / "sw"
ARTIFACTS = C_ROOT / "vitis_artifacts"
IMPL_DIR = (
    C_ROOT / "hw" / "build" / "vivado_ila_reference.runs" / "impl_1"
)
SOURCE_MMI = IMPL_DIR / "base_soc_wrapper.mmi"
SOURCE_BIT = IMPL_DIR / "base_soc_wrapper.bit"

# Unified Vitis rejects some component paths containing spaces. Keep all
# generated workspace state under a stable, no-space staging directory.
RUNTIME_ROOT = Path("/tmp/vivado_ila_vitis_build_v1")
RUNTIME_INPUT = RUNTIME_ROOT / "input"
WORKSPACE = RUNTIME_ROOT / "workspace"
XSA = RUNTIME_INPUT / "vivado_ila_reference.xsa"
SW = RUNTIME_INPUT / "sw"

PLATFORM_NAME = "vivado_ila_platform"
DOMAIN_NAME = "standalone_microblaze_riscv_0"
APP_NAME = "vivado_ila_app"
CPU_NAME = "microblaze_riscv_0"
APP_SOURCES = [
    "vivado_ila_reference.c",
    "vivado_ila_config.h",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build the C generator-control application after Vivado exports "
            "vivado_ila_reference.xsa"
        )
    )
    parser.add_argument(
        "--wait-xsa",
        type=int,
        default=0,
        metavar="SECONDS",
        help="wait up to SECONDS for the XSA/bit/MMI inputs",
    )
    return parser.parse_args()


def wait_for_hardware_inputs(timeout_seconds: int) -> None:
    required = (SOURCE_XSA, SOURCE_MMI, SOURCE_BIT)
    deadline = time.monotonic() + timeout_seconds
    while True:
        missing = [path for path in required if not path.is_file()]
        if not missing:
            return
        if time.monotonic() >= deadline:
            joined = "\n  ".join(str(path) for path in missing)
            raise FileNotFoundError(
                "Vivado hardware inputs are missing:\n  " + joined
            )
        time.sleep(1.0)


def create_bootable_bit(elf: Path) -> Path:
    processor = ET.parse(SOURCE_MMI).find(".//Processor")
    if processor is None or not processor.get("InstPath"):
        raise RuntimeError("Processor InstPath was not found in the MMI")

    output = ARTIFACTS / "vivado_ila_app.bit"
    subprocess.run(
        [
            "updatemem",
            "-meminfo",
            str(SOURCE_MMI),
            "-data",
            str(elf),
            "-bit",
            str(SOURCE_BIT),
            "-proc",
            processor.get("InstPath"),
            "-out",
            str(output),
            "-force",
        ],
        check=True,
    )
    print(f"VITIS_BUILD_PASS bootable_bit={output}")
    return output


def stage_inputs() -> None:
    if RUNTIME_ROOT.exists():
        shutil.rmtree(RUNTIME_ROOT)
    SW.mkdir(parents=True)
    WORKSPACE.mkdir(parents=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    shutil.copy2(SOURCE_XSA, XSA)
    for source_name in APP_SOURCES:
        shutil.copy2(SOURCE_SW / source_name, SW / source_name)


def main() -> None:
    args = parse_args()
    wait_for_hardware_inputs(args.wait_xsa)
    stage_inputs()

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WORKSPACE))
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
        app.build()

        elf_files = sorted((WORKSPACE / APP_NAME).rglob("*.elf"))
        if not elf_files:
            raise FileNotFoundError(
                f"Vitis produced no ELF under {WORKSPACE / APP_NAME}"
            )
        preferred = [
            path for path in elf_files if path.name == f"{APP_NAME}.elf"
        ]
        source_elf = preferred[0] if preferred else elf_files[0]
        artifact_elf = ARTIFACTS / "vivado_ila_app.elf"
        shutil.copy2(source_elf, artifact_elf)
        print(f"VITIS_BUILD_PASS elf={artifact_elf}")

        create_bootable_bit(artifact_elf)
        print(f"VITIS_BUILD_PASS workspace={WORKSPACE}")
        print(f"VITIS_BUILD_PASS platform={PLATFORM_NAME}")
        print(f"VITIS_BUILD_PASS application={APP_NAME}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
