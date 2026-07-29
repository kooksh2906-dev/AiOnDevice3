#!/usr/bin/env python3
"""Create and build the Vitis 2024.2 CPU Polling reference application."""

from pathlib import Path
import shutil

import vitis


HERE = Path(__file__).resolve().parent
CPU_POLLING_ROOT = HERE.parent
SOURCE_XSA = CPU_POLLING_ROOT / "hw" / "cpu_polling_reference.xsa"
SOURCE_SW = CPU_POLLING_ROOT / "sw"
ARTIFACTS = CPU_POLLING_ROOT / "vitis_artifacts"

# Unified Vitis 2024.2 rejects component paths containing spaces. Stage the
# Vitis workspace and its inputs under a stable, no-space path.
RUNTIME_ROOT = Path("/tmp/cpu_polling_vitis_build_v2")
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


def main() -> None:
    if not SOURCE_XSA.is_file():
        raise FileNotFoundError(f"Missing XSA: {SOURCE_XSA}")

    RUNTIME_INPUT.mkdir(parents=True, exist_ok=True)
    SW.mkdir(parents=True, exist_ok=True)
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    ARTIFACTS.mkdir(parents=True, exist_ok=True)

    shutil.copy2(SOURCE_XSA, XSA)
    for source_name in APP_SOURCES:
        shutil.copy2(SOURCE_SW / source_name, SW / source_name)

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(WORKSPACE))

        if (WORKSPACE / PLATFORM_NAME).is_dir():
            print(f"Reusing platform {PLATFORM_NAME}")
            platform = client.get_component(PLATFORM_NAME)
        else:
            print(f"Creating platform from {XSA}")
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
        if (WORKSPACE / APP_NAME).is_dir():
            print(f"Reusing application {APP_NAME}")
            app = client.get_component(APP_NAME)
            app_src = WORKSPACE / APP_NAME / "src"
            for source_name in APP_SOURCES:
                shutil.copy2(SW / source_name, app_src / source_name)
        else:
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

        elf_files = list((WORKSPACE / APP_NAME).rglob("*.elf"))
        if not elf_files:
            raise FileNotFoundError(
                f"Application build produced no ELF under {WORKSPACE / APP_NAME}"
            )
        for elf in elf_files:
            output = ARTIFACTS / elf.name
            shutil.copy2(elf, output)
            print(f"VITIS_BUILD_PASS elf={output}")

        print(f"VITIS_BUILD_PASS workspace={WORKSPACE}")
        print(f"VITIS_BUILD_PASS platform={PLATFORM_NAME}")
        print(f"VITIS_BUILD_PASS application={APP_NAME}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
