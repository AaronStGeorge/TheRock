import json
import logging
import os
import shlex
import subprocess
import tempfile
import tomllib
from pathlib import Path

THEROCK_BIN_DIR = Path(os.getenv("THEROCK_BIN_DIR")).resolve()
SCRIPT_DIR = Path(__file__).resolve().parent
THEROCK_DIR = SCRIPT_DIR.parent.parent.parent

logging.basicConfig(level=logging.INFO)

# Load test configuration from TOML (lists ALL plugins with paths/tolerances)
config_path = SCRIPT_DIR / "hipdnn_test_config.toml"
with open(config_path, "rb") as f:
    config = tomllib.load(f)
logging.info(f"Loaded test config from: {config_path}")

# Discover which plugins were built by looking for marker files installed by
# each provider's post-hook (via therock_register_hipdnn_engine_plugin).
# Marker filenames are the C API plugin names (returned from hipdnnGetEngineInfo_ext,
# or hipdnnPluginGetName on each plugin).
enabled_plugins_dir = (
    THEROCK_BIN_DIR / "hipdnn_integration_tests_test_infra" / "enabled_plugins"
)
if enabled_plugins_dir.is_dir():
    enabled_plugin_names = {
        f.name for f in enabled_plugins_dir.iterdir() if f.is_file()
    }
else:
    enabled_plugin_names = set()
    logging.warning(f"No enabled_plugins directory found at {enabled_plugins_dir}")
logging.info(f"Discovered enabled plugins: {enabled_plugin_names}")

# Filter TOML config to only include plugins this build produced.
# Match on the C API name (cfg["name"]) against discovered marker filenames.
if "plugins" in config:
    original_plugins = set(config["plugins"].keys())
    config["plugins"] = {
        key: cfg
        for key, cfg in config["plugins"].items()
        if cfg.get("name") in enabled_plugin_names
    }
    filtered_plugins = set(config["plugins"].keys())
    if filtered_plugins != original_plugins:
        logging.info(f"Filtered plugins: {original_plugins} -> {filtered_plugins}")

# Filter engines to only include those from enabled plugins
if "engines" in config and "plugins" in config:
    # Collect all engine names from enabled plugins
    enabled_engines = set()
    for plugin_cfg in config["plugins"].values():
        enabled_engines.update(plugin_cfg.get("engines", []))

    # Filter engines section
    original_engines = set(config["engines"].keys())
    config["engines"] = {
        name: cfg for name, cfg in config["engines"].items() if name in enabled_engines
    }
    filtered_engines = set(config["engines"].keys())
    if filtered_engines != original_engines:
        logging.info(f"Filtered engines: {original_engines} -> {filtered_engines}")

# Flatten expected failures from all engines into a single set
all_expected_failures = set()
for engine_name, engine_cfg in config.get("engines", {}).items():
    for failure in engine_cfg.get("expected_failures", []):
        all_expected_failures.add(failure)
config["expected_failures"] = sorted(all_expected_failures)
if all_expected_failures:
    logging.info(
        f"Total expected failures across all engines: {len(all_expected_failures)}"
    )

# Write JSON config to temp file for C++ harness
fd, json_config_path = tempfile.mkstemp(suffix=".json", prefix="hipdnn_test_config_")
with os.fdopen(fd, "w") as f:
    json.dump(config, f)
logging.info(f"Wrote JSON config to: {json_config_path}")

environ_vars = os.environ.copy()

# Set config path
environ_vars["HIPDNN_TEST_CONFIG_PATH"] = json_config_path

# Add THEROCK_BIN_DIR to PATH
environ_vars["PATH"] = f"{THEROCK_BIN_DIR}:{environ_vars['PATH']}"

cmd = [
    "ctest",
    "--test-dir",
    f"{THEROCK_BIN_DIR}/hipdnn_integration_tests_test_infra",
    "--output-on-failure",
    "--parallel",
    "8",
    "--timeout",
    "1200",
]

logging.info(f"++ Exec [{THEROCK_DIR}]$ {shlex.join(cmd)}")

subprocess.run(
    cmd,
    cwd=THEROCK_DIR,
    check=True,
    env=environ_vars,
)
