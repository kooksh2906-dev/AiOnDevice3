#!/usr/bin/env python3
"""Create and build the EdgeScope-Lite Vitis 2024.2 application."""

from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET

import vitis


HERE = Path(__file__).resolve().parent
B_ROOT = HERE.parent
REPO_ROOT = B_ROOT.parents[1]
SOURCE_XSA = B_ROOT / "hw" / "edgescope_lite_reference.xsa"
SOURCE_SW = B_ROOT / "sw"
COMMON_HEADER = REPO_ROOT / "sw" / "include" / "logic_analyzer_regs.h"
ARTIFACTS = B_ROOT / "vitis_artifacts"
IMPL_DIR = (
    B_ROOT / "hw" / "build" / "edgescope_lite_reference.runs" / "impl_1"
)
SOURCE_MMI = IMPL_DIR / "base_soc_wrapper.mmi"
SOURCE_BIT = IMPL_DIR / "base_soc_wrapper.bit"

RUNTIME_ROOT = Path("/tmp/edgescope_lite_vitis_build_v1")
RUNTIME_INPUT = RUNTIME_ROOT / "input"
WORKSPACE = RUNTIME_ROOT / "workspace"
XSA = RUNTIME_INPUT / "edgescope_lite_reference.xsa"
SW = RUNTIME_INPUT / "sw"

PLATFORM_NAME = "edgescope_lite_platform"
DOMAIN_NAME = "standalone_microblaze_riscv_0"
APP_NAME = "edgescope_lite_app"
CPU_NAME = "microblaze_riscv_0"
APP_SOURCES = [
    "edgescope_lite_reference.c",
    "edgescope_lite_config.h",
    "logic_analyzer_regs.h",
]


def create_bootable_bit(updatemem: str, elf: Path) -> None:
    processor = ET.parse(SOURCE_MMI).find(".//Processor")
    if processor is None or not processor.get("InstPath"):
        raise RuntimeError("Processor InstPath was not found in the MMI")
    output = ARTIFACTS / "edgescope_lite_app.bit"
    subprocess.run(
        [
            updatemem,
            "-meminfo", str(SOURCE_MMI),
            "-data", str(elf),
            "-bit", str(SOURCE_BIT),
            "-proc", processor.get("InstPath"),
            "-out", str(output),
            "-force",
        ],
        check=True,
    )
    print(f"VITIS_BUILD_PASS bootable_bit={output}")


def require_inputs() -> str:
    required = [
        SOURCE_XSA,
        SOURCE_MMI,
        SOURCE_BIT,
        SOURCE_SW / "edgescope_lite_reference.c",
        SOURCE_SW / "edgescope_lite_config.h",
        COMMON_HEADER,
    ]
    missing = [path for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            "Required EdgeScope-Lite inputs are missing:\n  "
            + "\n  ".join(str(path) for path in missing)
        )
    updatemem = shutil.which("updatemem")
    if not updatemem:
        raise FileNotFoundError(
            "updatemem was not found on PATH. Source the Vitis 2024.2 "
            "settings64.sh before running this script."
        )
    return updatemem


def main() -> None:
    updatemem = require_inputs()
    if RUNTIME_ROOT.exists():
        shutil.rmtree(RUNTIME_ROOT)
    SW.mkdir(parents=True)
    WORKSPACE.mkdir(parents=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    shutil.copy2(SOURCE_XSA, XSA)
    shutil.copy2(SOURCE_SW / "edgescope_lite_reference.c", SW)
    shutil.copy2(SOURCE_SW / "edgescope_lite_config.h", SW)
    shutil.copy2(COMMON_HEADER, SW)

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
        preferred = [
            path for path in elf_files if path.name == f"{APP_NAME}.elf"
        ]
        if len(preferred) != 1:
            raise FileNotFoundError(
                f"Expected exactly one {APP_NAME}.elf under "
                f"{WORKSPACE / APP_NAME}, found: {elf_files}"
            )
        artifact_elf = ARTIFACTS / "edgescope_lite_app.elf"
        shutil.copy2(preferred[0], artifact_elf)
        print(f"VITIS_BUILD_PASS elf={artifact_elf}")
        create_bootable_bit(updatemem, artifact_elf)
        print(f"VITIS_BUILD_PASS workspace={WORKSPACE}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
