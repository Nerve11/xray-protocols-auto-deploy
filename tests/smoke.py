import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parents[1]
GEN = REPO_ROOT / "generator" / "xpad.py"
PROFILES_DIR = REPO_ROOT / "profiles"
EXAMPLES_DIR = REPO_ROOT / "examples"


def read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def run(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def xray_path() -> str:
    return shutil.which("xray") or ""


def render(profile_id: str, params: Path, out_dir: Path) -> None:
    r = run([sys.executable, str(GEN), "render", "--profile", profile_id, "--params", str(params), "--out", str(out_dir)])
    if r.returncode != 0:
        raise RuntimeError((r.stdout or "") + (r.stderr or ""))


def xray_test(server_cfg: Path) -> None:
    xray = xray_path()
    if not xray:
        return
    r = run([xray, "-test", "-c", str(server_cfg)])
    if r.returncode != 0:
        raise RuntimeError((r.stdout or "") + (r.stderr or ""))


def main() -> int:
    profiles = [p for p in sorted(PROFILES_DIR.glob("*.json"))]
    if not profiles:
        raise RuntimeError("profiles/*.json не найдены")

    params_reality = EXAMPLES_DIR / "params.reality.sample.json"
    params_tls = EXAMPLES_DIR / "params.tls.sample.json"

    ok = 0
    skipped_test = 0

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        for p in profiles:
            meta = read_json(p)
            profile_id = meta["id"]
            security = meta.get("security", "none")

            params = params_reality if security != "tls" else params_tls
            out_dir = td_path / profile_id

            if security == "reality" and not xray_path():
                base = read_json(params_reality)
                base.setdefault("reality_privateKey", "PRIVATE_KEY")
                base.setdefault("reality_password", "PUBLIC_KEY")
                tmp_params = td_path / f"{profile_id}.params.json"
                tmp_params.write_text(json.dumps(base, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                params = tmp_params

            render(profile_id, params, out_dir)

            server_cfg = read_json(out_dir / "server.json")
            client_cfg = read_json(out_dir / "client.json")
            eff = read_json(out_dir / "params.effective.json")

            if "inbounds" not in server_cfg or "outbounds" not in server_cfg:
                raise RuntimeError(f"{profile_id}: отсутствуют inbounds/outbounds в server.json")
            if "outbounds" not in client_cfg:
                raise RuntimeError(f"{profile_id}: отсутствует outbounds в client.json")
            if not isinstance(eff, dict):
                raise RuntimeError(f"{profile_id}: params.effective.json не объект")

            if xray_path():
                if security == "tls":
                    cert = eff.get("tls_certificateFile")
                    key = eff.get("tls_keyFile")
                    if cert and key and Path(cert).exists() and Path(key).exists():
                        xray_test(out_dir / "server.json")
                    else:
                        skipped_test += 1
                else:
                    xray_test(out_dir / "server.json")
            else:
                skipped_test += 1

            ok += 1

    print(json.dumps({"profiles_ok": ok, "xray_test_skipped": skipped_test}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
