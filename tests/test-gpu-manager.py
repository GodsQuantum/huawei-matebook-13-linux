#!/usr/bin/env python3
import json
import os
import re
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "gpu-power" / "huawei-matebook-13-gpu-manager.sh"


def bash(code: str, env=None, check=False):
    e = os.environ.copy()
    if env:
        e.update(env)
    p = subprocess.run(["bash", "-c", code], text=True, capture_output=True, env=e)
    if check and p.returncode:
        raise AssertionError(f"bash failed rc={p.returncode}\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}")
    return p


def test_env(td: Path):
    home = td / "home"
    config = td / "config"
    state = td / "state"
    local_apps = td / "apps"
    sys_pci = td / "sys" / "bus" / "pci" / "devices"
    dmi = td / "sys" / "class" / "dmi" / "id"
    scripts = td / "scripts"
    for p in (home, config, state, local_apps, sys_pci, dmi, scripts):
        p.mkdir(parents=True, exist_ok=True)
    return {
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_STATE_HOME": str(state),
        "HUAWEI_GPU_TEST_MODE": "1",
        "HUAWEI_GPU_LIB_ONLY": "1",
        "HUAWEI_GPU_LOCAL_APPS": str(local_apps),
        "HUAWEI_GPU_SYSFS_PCI_DEVICES": str(sys_pci),
        "HUAWEI_GPU_DMI_ROOT": str(dmi),
        "HUAWEI_GPU_SCAN_DIRS": str(scripts),
        "HUAWEI_GPU_SYSTEM_CONFIG": str(td / "etc" / "huawei.conf"),
        "HUAWEI_GPU_LEGACY_V1_RUNNER": str(td / "usr" / "local" / "bin" / "legacy-dgpu-run"),
        "HUAWEI_GPU_LEGACY_V1_POWER": str(td / "usr" / "local" / "sbin" / "legacy-dgpu-power"),
        "HUAWEI_GPU_LEGACY_V1_SUDOERS": str(td / "etc" / "sudoers.d" / "legacy-dgpu"),
    }


class ManagerV3Tests(unittest.TestCase):
    def source_cmd(self, body=""):
        return f'source "{SCRIPT}"\n{body}'

    def test_00_library_mode_and_version_contract(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            p = bash(self.source_cmd('printf "%s|%s|%s\\n" "$VERSION" "$STATE_SCHEMA" "$INSTALL_SCHEMA"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(p.stdout.strip(), "3.0.2|3|3")

    def test_01_state_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            code = self.source_cmd(textwrap.dedent(r'''
                MANAGED_DESKTOP_APPS=("DaVinciResolve.desktop" "blender.desktop")
                MANAGED_STEAM_APPS=("730" "1234")
                STEAM_ALL=1
                save_user_state
                MANAGED_DESKTOP_APPS=(); MANAGED_STEAM_APPS=(); STEAM_ALL=0
                load_user_state
                printf 'D=%s\n' "${MANAGED_DESKTOP_APPS[*]}"
                printf 'S=%s\n' "${MANAGED_STEAM_APPS[*]}"
                printf 'A=%s\n' "$STEAM_ALL"
            '''))
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("D=DaVinciResolve.desktop blender.desktop", p.stdout)
            self.assertIn("S=730 1234", p.stdout)
            self.assertIn("A=1", p.stdout)
            state = Path(env["XDG_CONFIG_HOME"]) / "huawei-matebook-gpu-manager" / "state.json"
            obj = json.loads(state.read_text())
            self.assertEqual(obj["state_schema"], 3)

    def test_02_migrate_schema_1_and_2_to_3(self):
        for schema, payload in [
            (1, {"state_schema": 1, "desktop_apps": ["A.desktop"], "steam_apps": ["42"], "steam_all": True}),
            (2, {"state_schema": 2, "managed_desktop_apps": ["B.desktop"], "managed_steam_apps": ["84"], "steam_all": False}),
        ]:
            with self.subTest(schema=schema), tempfile.TemporaryDirectory() as d:
                env = test_env(Path(d))
                state = Path(env["XDG_CONFIG_HOME"]) / "huawei-matebook-gpu-manager" / "state.json"
                state.parent.mkdir(parents=True, exist_ok=True)
                state.write_text(json.dumps(payload))
                p = bash(self.source_cmd('migrate_state_file; load_user_state; printf "%s|%s|%s\\n" "${MANAGED_DESKTOP_APPS[*]}" "${MANAGED_STEAM_APPS[*]}" "$STEAM_ALL"'), env)
                self.assertEqual(p.returncode, 0, p.stderr)
                obj = json.loads(state.read_text())
                self.assertEqual(obj["state_schema"], 3)
                self.assertIn(".desktop", p.stdout)

    def test_03_import_v1_desktop_and_preserve_env_when_normalized(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            app = Path(env["HUAWEI_GPU_LOCAL_APPS"]) / "DaVinciResolve.desktop"
            legacy_runner = env["HUAWEI_GPU_LEGACY_V1_RUNNER"]
            app.write_text(textwrap.dedent(f'''\
                [Desktop Entry]
                Name=DaVinci Resolve
                Exec=env DBUS_SESSION_BUS_ADDRESS=abcdef QT_QPA_PLATFORM=xcb {legacy_runner} /opt/resolve/bin/resolve %u
            '''))
            # Use the real legacy path inside the launcher; discovery must recognize historical canonical names too.
            out = td / "normalized.desktop"
            code = self.source_cmd(f'''
                import_legacy_desktop_apps
                printf 'APPS=%s\\n' "${{MANAGED_DESKTOP_APPS[*]}}"
                strip_known_runners_from_desktop "{app}" "{out}"
            ''')
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("DaVinciResolve.desktop", p.stdout)
            text = out.read_text()
            self.assertNotIn(legacy_runner, text)
            self.assertIn("DBUS_SESSION_BUS_ADDRESS=abcdef QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve %u", text)

    def test_04_import_adjacent_script_manifest_is_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            old = Path(env["HUAWEI_GPU_SCAN_DIRS"]) / "Huawei-Gestion-GPUv2.sh"
            old.write_text(textwrap.dedent('''\
                #!/usr/bin/env bash
                # === HUAWEI_GPU_CONFIG_BEGIN ===
                MANAGED_DESKTOP_APPS=(
                  "DaVinciResolve.desktop"
                  "blender.desktop"
                )
                MANAGED_STEAM_APPS=(
                  "730"
                )
                STEAM_ALL=0
                # === HUAWEI_GPU_CONFIG_END ===
            '''))
            code = self.source_cmd(r'''
                import_adjacent_script_manifests
                import_adjacent_script_manifests
                printf 'D=%s\n' "${MANAGED_DESKTOP_APPS[*]}"
                printf 'S=%s\n' "${MANAGED_STEAM_APPS[*]}"
            ''')
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(p.stdout.count("DaVinciResolve.desktop"), 1)
            self.assertEqual(p.stdout.count("blender.desktop"), 1)
            self.assertEqual(p.stdout.count("730"), 1)

    def test_05_import_legacy_steam_runner(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            vdf = td / "localconfig.vdf"
            legacy_runner = env["HUAWEI_GPU_LEGACY_V1_RUNNER"]
            vdf.write_text(textwrap.dedent('''\
                "UserLocalConfigStore"
                {
                    "Software"
                    {
                        "Valve"
                        {
                            "Steam"
                            {
                                "apps"
                                {
                                    "730"
                                    {
                                        "LaunchOptions" "MANGOHUD=1 {RUNNER} %command% -novid"
                                    }
                                }
                            }
                        }
                    }
                }
            ''').replace('{RUNNER}', legacy_runner))
            env["HUAWEI_GPU_STEAM_LOCALCONFIG"] = str(vdf)
            p = bash(self.source_cmd('import_legacy_steam_apps; printf "%s\\n" "${MANAGED_STEAM_APPS[*]}"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(p.stdout.strip(), "730")

    def test_06_detect_v1_artifact(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            runner = Path(env["HUAWEI_GPU_LEGACY_V1_RUNNER"])
            runner.parent.mkdir(parents=True, exist_ok=True); runner.write_text("#!/bin/sh\n")
            p = bash(self.source_cmd('discover_legacy_generations; printf "%s\\n" "$LEGACY_GENERATIONS"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("v1", p.stdout.split())

    def test_07_cleanup_is_after_migration_commit(self):
        text = SCRIPT.read_text()
        m = re.search(r'install_core\(\) \{(?P<body>.*?)\n\}', text, re.S)
        self.assertIsNotNone(m)
        body = m.group("body")
        self.assertIn("migration_commit", body)
        self.assertIn("cleanup_legacy_v1", body)
        self.assertLess(body.index("migration_commit"), body.index("cleanup_legacy_v1"))

    def test_08_doctor_contract_and_list_rc(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            p = bash(self.source_cmd('list_managed; rc=$?; doctor; printf "LIST_RC=%s\\n" "$rc"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("LIST_RC=0", p.stdout)
            self.assertIn("STATE_SCHEMA=3", p.stdout)
            self.assertIn("INSTALL_SCHEMA=", p.stdout)
            self.assertIn("LEGACY_COMPONENTS=", p.stdout)

    def test_09_no_rtd3_claim_for_pascal(self):
        text = SCRIPT.read_text()
        self.assertNotIn('NVreg_DynamicPowerManagement=0x02', text)
        self.assertRegex(text, r'(?i)RTD3.*Turing|Turing.*RTD3')

    def test_10_import_is_read_only_until_transaction_snapshot(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            app = Path(env["HUAWEI_GPU_LOCAL_APPS"]) / "DaVinciResolve.desktop"
            legacy_runner = env["HUAWEI_GPU_LEGACY_V1_RUNNER"]
            app.write_text(f'[Desktop Entry]\nName=DaVinci\nExec={legacy_runner} /opt/resolve/bin/resolve\n')
            p = bash(self.source_cmd('import_legacy_state; printf "%s\\n" "${MANAGED_DESKTOP_APPS[*]}"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("DaVinciResolve.desktop", p.stdout)
            state = Path(env["XDG_CONFIG_HOME"]) / "huawei-matebook-gpu-manager" / "state.json"
            self.assertFalse(state.exists(), "legacy import must not persist before migration_begin snapshot")

    def test_11_install_transaction_success_order(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            code = self.source_cmd(r'''
                ensure_dirs(){ :; }
                manager_lock_acquire(){ echo lock; }
                bold(){ :; }; line(){ :; }; info(){ :; }; warn(){ :; }
                bootstrap_user_state(){ echo bootstrap; }
                import_legacy_state(){ echo import; LEGACY_COMPONENTS=1; LEGACY_GENERATIONS=v1; }
                normalize_idle_state(){ echo idle; }
                hardware_discover(){ echo hw; }
                migration_begin(){ echo begin; MIGRATION_ACTIVE=1; }
                sync_persistent_state(){ echo sync; }
                install_reconcile_steps(){ echo reconcile; }
                smoke_test(){ echo smoke; }
                migration_commit(){ echo commit; MIGRATION_COMMITTED=1; }
                cleanup_legacy_v1(){ echo cleanup; }
                install_core
            ''')
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            sequence = [x for x in p.stdout.splitlines() if x in {"lock","bootstrap","import","idle","hw","begin","sync","reconcile","smoke","commit","cleanup"}]
            self.assertLess(sequence.index("begin"), sequence.index("reconcile"))
            self.assertLess(sequence.index("smoke"), sequence.index("commit"))
            self.assertLess(sequence.index("commit"), sequence.index("cleanup"))

    def test_12_install_failure_rolls_back_and_preserves_rc(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            code = self.source_cmd(r'''
                ensure_dirs(){ :; }
                manager_lock_acquire(){ :; }
                bold(){ :; }; line(){ :; }; info(){ :; }; warn(){ :; }
                bootstrap_user_state(){ :; }
                import_legacy_state(){ LEGACY_COMPONENTS=1; LEGACY_GENERATIONS=v1; }
                normalize_idle_state(){ :; }
                hardware_discover(){ :; }
                migration_begin(){ MIGRATION_ACTIVE=1; }
                sync_persistent_state(){ :; }
                install_reconcile_steps(){ return 42; }
                migration_rollback(){ echo ROLLBACK; }
                migration_commit(){ echo COMMIT; }
                cleanup_legacy_v1(){ echo CLEANUP; }
                set +e
                install_core
                rc=$?
                set -e
                printf 'RC=%s\n' "$rc"
            ''')
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("ROLLBACK", p.stdout)
            self.assertIn("RC=42", p.stdout)
            self.assertNotIn("COMMIT", p.stdout)
            self.assertNotIn("CLEANUP", p.stdout)

    def test_13_refuse_install_schema_downgrade(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            cfg = Path(env["HUAWEI_GPU_SYSTEM_CONFIG"])
            cfg.parent.mkdir(parents=True, exist_ok=True)
            cfg.write_text('MANAGER_VERSION="7.0.0"\nINSTALL_SCHEMA=7\n')
            p = bash(self.source_cmd('set +e; assert_install_schema_compatible; rc=$?; printf "RC=%s\\n" "$rc"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("RC=2", p.stdout)
            self.assertIn("newer", p.stderr.lower())

    def test_14_runner_uses_standard_prime_without_global_vulkan_filter(self):
        text = SCRIPT.read_text()
        self.assertIn('export __NV_PRIME_RENDER_OFFLOAD=1', text)
        self.assertIn('export __VK_LAYER_NV_optimus=NVIDIA_only', text)
        self.assertIn('unset VK_LOADER_DRIVERS_SELECT', text)
        self.assertIn('HUAWEI_GPU_VK_DRIVER_FILTER', text)

    def test_15_power_helper_checks_all_common_nvidia_device_nodes(self):
        text = SCRIPT.read_text()
        self.assertIn('/dev/nvidia-uvm-tools', text)
        self.assertIn('/dev/nvidia-caps/*', text)

    def test_16_saved_desktop_apply_propagates_failure(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            p = bash(self.source_cmd(r'''
                MANAGED_DESKTOP_APPS=("missing.desktop")
                apply_desktop_app(){ return 37; }
                set +e
                apply_saved_desktop_apps
                rc=$?
                printf 'RC=%s\n' "$rc"
            '''), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("RC=37", p.stdout)

    def test_17_steam_existing_options_without_placeholder_put_runner_first(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            vdf = td / "localconfig.vdf"
            vdf.write_text(textwrap.dedent('''\
                "UserLocalConfigStore"
                {
                    "Software" { "Valve" { "Steam" { "apps"
                    {
                        "730"
                        {
                            "LaunchOptions"        "-novid   -high"
                        }
                    } } } }
                }
            '''))
            env["HUAWEI_GPU_STEAM_LOCALCONFIG"] = str(vdf)
            runner = td / "runner"; env["HUAWEI_GPU_RUNNER"] = str(runner)
            p = bash(self.source_cmd('steam_running(){ return 1; }; steam_edit_launchoption add 730'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            text = vdf.read_text()
            self.assertIn(f'{runner} %command% -novid   -high', text)
            self.assertNotIn(f'-novid   -high {runner}', text)

    def test_18_steam_remove_restores_exact_original_spacing(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            vdf = td / "localconfig.vdf"
            original = 'MANGOHUD=1   gamemoderun %command%   -novid'
            vdf.write_text(textwrap.dedent(f'''\
                "UserLocalConfigStore"
                {{
                    "Software" {{ "Valve" {{ "Steam" {{ "apps"
                    {{
                        "730"
                        {{
                            "LaunchOptions"        "{original}"
                        }}
                    }} }} }} }}
                }}
            '''))
            env["HUAWEI_GPU_STEAM_LOCALCONFIG"] = str(vdf)
            env["HUAWEI_GPU_RUNNER"] = str(td / "runner")
            p = bash(self.source_cmd('steam_running(){ return 1; }; steam_edit_launchoption add 730; steam_edit_launchoption remove 730'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn(original, vdf.read_text())

    def test_19_v1_desktop_backup_survives_upgrade_and_remove(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            env["HUAWEI_GPU_RUNNER"] = str(td / "usr/local/bin/huawei-matebook-dgpu-run")
            local_apps = Path(env["HUAWEI_GPU_LOCAL_APPS"])
            app = local_apps / "DaVinciResolve.desktop"
            original = '[Desktop Entry]\nName=DaVinci Resolve\nExec=env DBUS_SESSION_BUS_ADDRESS=abcdef QT_QPA_PLATFORM=xcb /opt/resolve/bin/resolve %u\n'
            app.write_text(original.replace('/opt/resolve/bin/resolve', env["HUAWEI_GPU_LEGACY_V1_RUNNER"] + ' /opt/resolve/bin/resolve'))
            legacy = Path(env["XDG_STATE_HOME"]) / "huawei-gpu-manager" / "desktop" / "DaVinciResolve.desktop"
            legacy.mkdir(parents=True)
            (legacy / "captured").touch()
            (legacy / "had_local").write_text('1\n')
            (legacy / "original.desktop").write_text(original)
            p = bash(self.source_cmd(r'''
                apply_desktop_app DaVinciResolve.desktop false
                remove_desktop_app DaVinciResolve.desktop false
            '''), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(app.read_text(), original)

    def test_20_interactive_menu_survives_install_failure(self):
        with tempfile.TemporaryDirectory() as d:
            env = test_env(Path(d))
            p = bash(self.source_cmd(r'''
                install_core(){ return 42; }
                clear(){ :; }
                pause(){ :; }
                warn(){ :; }
                main_menu <<< $'1\n0\n'
                echo SURVIVED
            '''), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn('SURVIVED', p.stdout)

    def test_21_old_adjacent_manifest_does_not_override_existing_v3_state(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            old = Path(env["HUAWEI_GPU_SCAN_DIRS"]) / "Huawei-Gestion-GPU-old.sh"
            old.write_text('# === HUAWEI_GPU_CONFIG_BEGIN ===\nMANAGED_DESKTOP_APPS=(\n  "DaVinciResolve.desktop"\n)\nMANAGED_STEAM_APPS=(\n)\nSTEAM_ALL=0\n# === HUAWEI_GPU_CONFIG_END ===\n')
            state = Path(env["XDG_CONFIG_HOME"]) / "huawei-matebook-gpu-manager" / "state.json"
            state.parent.mkdir(parents=True, exist_ok=True)
            state.write_text(json.dumps({"state_schema":3,"manager_version":"3.0.0","managed_desktop_apps":[],"managed_steam_apps":[],"steam_all":False,"legacy_generations":[]}))
            legacy_runner = Path(env["HUAWEI_GPU_LEGACY_V1_RUNNER"])
            legacy_runner.parent.mkdir(parents=True, exist_ok=True)
            legacy_runner.write_text("#!/bin/sh\n")
            p = bash(self.source_cmd('bootstrap_user_state; import_legacy_state; printf "D=%s\\n" "${MANAGED_DESKTOP_APPS[*]}"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertEqual(p.stdout.strip(), "D=")

    def test_22_adjacent_manifest_is_imported_on_fresh_reinstall(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            old = Path(env["HUAWEI_GPU_SCAN_DIRS"]) / "Huawei-Gestion-GPU-old.sh"
            old.write_text('# === HUAWEI_GPU_CONFIG_BEGIN ===\nMANAGED_DESKTOP_APPS=(\n  "DaVinciResolve.desktop"\n)\nMANAGED_STEAM_APPS=(\n)\nSTEAM_ALL=0\n# === HUAWEI_GPU_CONFIG_END ===\n')
            p = bash(self.source_cmd('bootstrap_user_state; import_legacy_state; printf "D=%s\\n" "${MANAGED_DESKTOP_APPS[*]}"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("DaVinciResolve.desktop", p.stdout)

    def test_23_import_backup_inventory_recovers_managed_apps_without_old_script(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            v2_desktop = Path(env["XDG_STATE_HOME"]) / "huawei-matebook-gpu-manager" / "desktop" / "DaVinciResolve.desktop"
            v2_desktop.mkdir(parents=True)
            (v2_desktop / "captured").touch()
            v1_desktop = Path(env["XDG_STATE_HOME"]) / "huawei-gpu-manager" / "desktop" / "blender.desktop"
            v1_desktop.mkdir(parents=True)
            (v1_desktop / "captured").touch()
            v2_steam = Path(env["XDG_STATE_HOME"]) / "huawei-matebook-gpu-manager" / "steam" / "original"
            v2_steam.mkdir(parents=True)
            (v2_steam / "730.json").write_text('{}')
            p = bash(self.source_cmd('import_legacy_backup_inventory; printf "D=%s\nS=%s\n" "${MANAGED_DESKTOP_APPS[*]}" "${MANAGED_STEAM_APPS[*]}"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("DaVinciResolve.desktop", p.stdout)
            self.assertIn("blender.desktop", p.stdout)
            self.assertIn("730", p.stdout)

    def test_24_public_script_contains_no_private_machine_codename(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("Pe" + "gasus", text)
        self.assertNotIn("pe" + "gasus", text)

    def test_25_dynamic_legacy_v1_path_discovery(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            # Clear explicit test overrides so discovery must inspect generic legacy artifacts.
            env["HUAWEI_GPU_LEGACY_V1_RUNNER"] = ""
            env["HUAWEI_GPU_LEGACY_V1_POWER"] = ""
            env["HUAWEI_GPU_LEGACY_V1_SUDOERS"] = ""
            bindir = td / "usr-local-bin"; sbindir = td / "usr-local-sbin"; sudoers = td / "sudoers.d"
            for x in (bindir, sbindir, sudoers): x.mkdir(parents=True, exist_ok=True)
            env["HUAWEI_GPU_USR_LOCAL_BIN"] = str(bindir)
            env["HUAWEI_GPU_USR_LOCAL_SBIN"] = str(sbindir)
            env["HUAWEI_GPU_SUDOERS_DIR"] = str(sudoers)
            power = sbindir / "legacy-dgpu-power"
            power.write_text('#!/bin/sh\n# NVIDIA MX250 10de:1d13\n')
            runner = bindir / "legacy-dgpu-run"
            runner.write_text(f'#!/bin/sh\nPOWER="{power}"\nexport __NV_PRIME_RENDER_OFFLOAD=1\n')
            sf = sudoers / "legacy-dgpu"
            sf.write_text(f'user ALL=(root) NOPASSWD: {power} on\n')
            p = bash(self.source_cmd('discover_legacy_v1_paths; printf "R=%s\nP=%s\nS=%s\n" "$LEGACY_V1_RUNNER" "$LEGACY_V1_POWER" "$LEGACY_V1_SUDOERS"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn(str(runner), p.stdout)
            self.assertIn(str(power), p.stdout)
            self.assertIn(str(sf), p.stdout)

    def test_26_legacy_kwin_cleanup_is_tied_to_legacy_udev_alias(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            env["HUAWEI_GPU_LEGACY_V1_UDEV"] = ""
            env["HUAWEI_GPU_LEGACY_V1_KWIN"] = ""
            udev = td / "udev"; kwin = td / "kwin"
            udev.mkdir(); kwin.mkdir()
            env["HUAWEI_GPU_UDEV_RULES_DIR"] = str(udev)
            env["HUAWEI_GPU_KWIN_DROPIN_DIR"] = str(kwin)
            rule = udev / "61-legacy-igpu.rules"
            rule.write_text('SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="0000:00:02.0", SYMLINK+="dri/legacy-intel"\n')
            unrelated = kwin / "60-unrelated.conf"
            unrelated.write_text('[Service]\nEnvironment=KWIN_DRM_DEVICES=/dev/dri/something-else\n')
            legacy = kwin / "61-legacy.conf"
            legacy.write_text('[Service]\nEnvironment=KWIN_DRM_DEVICES=/dev/dri/legacy-intel\nEnvironment=KWIN_RENDER_NODES=\n')
            p = bash(self.source_cmd('discover_legacy_v1_paths; printf "U=%s\nK=%s\n" "$LEGACY_V1_UDEV" "$LEGACY_V1_KWIN"'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn(str(rule), p.stdout)
            self.assertIn(str(legacy), p.stdout)
            self.assertNotIn(str(unrelated), p.stdout)

    def test_27_limine_active_prefers_limine_mkinitcpio(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            bindir = td / "bin"; bindir.mkdir()
            log = td / "calls.log"
            for name in ("limine-mkinitcpio", "mkinitcpio"):
                f = bindir / name
                f.write_text(f'#!/bin/sh\necho "{name} $*" >> "{log}"\n')
                f.chmod(0o755)
            limine_cfg = td / "etc-default-limine"; limine_cfg.write_text('KERNEL_CMDLINE[default]="quiet"\n')
            env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
            env["HUAWEI_GPU_LIMINE_CONFIG"] = str(limine_cfg)
            env["HUAWEI_GPU_LIMINE_BOOT_CONFIG"] = str(td / "missing-limine.conf")
            p = bash(self.source_cmd('sudo(){ "$@"; }; rebuild_initramfs'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(calls, ["limine-mkinitcpio "])

    def test_28_non_limine_arch_falls_back_to_mkinitcpio_p(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            bindir = td / "bin"; bindir.mkdir()
            log = td / "calls.log"
            for name in ("limine-mkinitcpio", "mkinitcpio"):
                f = bindir / name
                f.write_text(f'#!/bin/sh\necho "{name} $*" >> "{log}"\n')
                f.chmod(0o755)
            env["PATH"] = str(bindir) + os.pathsep + os.environ.get("PATH", "")
            env["HUAWEI_GPU_LIMINE_CONFIG"] = str(td / "missing-default-limine")
            env["HUAWEI_GPU_LIMINE_BOOT_CONFIG"] = str(td / "missing-limine.conf")
            p = bash(self.source_cmd('sudo(){ "$@"; }; rebuild_initramfs'), env)
            self.assertEqual(p.returncode, 0, p.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(calls, ["mkinitcpio -P"])


    def test_29_doctor_uses_functional_sudo_path_not_sudoers_readability(self):
        with tempfile.TemporaryDirectory() as d:
            td = Path(d); env = test_env(td)
            helper = td / "helper"
            runner = td / "runner"
            cfg = td / "system.conf"
            udev = td / "61-gpu.rules"
            missing_sudoers = td / "sudoers-not-readable-by-design"
            helper.write_text('#!/bin/sh\n[ "$1" = status ] && { echo GPU_PRESENT=NO; echo LEASES=0; exit 0; }\nexit 0\n')
            runner.write_text('#!/bin/sh\nexit 0\n')
            cfg.write_text('INSTALL_SCHEMA=3\n')
            udev.write_text('SUBSYSTEM=="drm"\n')
            helper.chmod(0o755); runner.chmod(0o755)
            env["HUAWEI_GPU_POWER_HELPER"] = str(helper)
            env["HUAWEI_GPU_RUNNER"] = str(runner)
            env["HUAWEI_GPU_SYSTEM_CONFIG"] = str(cfg)
            env["HUAWEI_GPU_UDEV_RULE"] = str(udev)
            env["HUAWEI_GPU_SUDOERS_FILE"] = str(missing_sudoers)
            code = self.source_cmd(r'''
                discover_legacy_generations(){ LEGACY_COMPONENTS=0; LEGACY_GENERATIONS=""; }
                plasma_wayland_detected(){ return 1; }
                find_dgpu_bdf(){ return 1; }
                modinfo(){ return 1; }
                lsmod(){ :; }
                sudo(){ [[ "${1:-}" == -n ]] && shift; "$@"; }
                doctor
            ''')
            p = bash(code, env)
            self.assertEqual(p.returncode, 0, p.stderr)
            self.assertIn("CONFIG_DRIFT=NO", p.stdout)



if __name__ == "__main__":
    unittest.main(verbosity=2)
