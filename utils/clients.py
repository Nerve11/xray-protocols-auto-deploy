import argparse
import json
import os
import secrets
import subprocess
import sys
import uuid
from pathlib import Path
from shutil import which
from typing import Any, Dict, List, Optional


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, data: Dict[str, Any], mode: Optional[int] = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if mode is not None:
        os.chmod(str(path), mode)


def _run(cmd: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def _which(name: str) -> Optional[str]:
    return which(name)


def _gen_uuid() -> str:
    xray = _which("xray")
    if xray:
        r = _run([xray, "uuid"])
        if r.returncode == 0:
            out = (r.stdout or "").strip().splitlines()
            if out:
                return out[-1].strip()
    return str(uuid.uuid4())


def _service_restart() -> None:
    systemctl = _which("systemctl")
    if not systemctl:
        return
    _run([systemctl, "restart", "xray.service"])


def _xray_test(config_path: str) -> None:
    xray = _which("xray")
    if not xray:
        raise RuntimeError("xray не найден в PATH")
    r = _run([xray, "-test", "-c", config_path])
    if r.returncode != 0:
        raise RuntimeError((r.stdout or "") + (r.stderr or ""))


def _get_inbound(cfg: Dict[str, Any]) -> Dict[str, Any]:
    inbounds = cfg.get("inbounds")
    if not isinstance(inbounds, list) or not inbounds:
        raise RuntimeError("В конфиге нет inbounds")
    ib = inbounds[0]
    if not isinstance(ib, dict):
        raise RuntimeError("Неверный inbound")
    return ib


def _clients_list(cfg: Dict[str, Any]) -> List[Dict[str, Any]]:
    ib = _get_inbound(cfg)
    protocol = ib.get("protocol")
    settings = ib.get("settings", {})
    if protocol in ("vless", "vmess", "trojan"):
        clients = settings.get("clients", [])
        if isinstance(clients, list):
            return [c for c in clients if isinstance(c, dict)]
    raise RuntimeError(f"Неподдерживаемый inbound protocol: {protocol}")


def _clients_write(cfg: Dict[str, Any], clients: List[Dict[str, Any]]) -> None:
    ib = _get_inbound(cfg)
    settings = ib.setdefault("settings", {})
    settings["clients"] = clients


def cmd_list(config_path: Path) -> int:
    cfg = _read_json(config_path)
    clients = _clients_list(cfg)
    print(json.dumps(clients, ensure_ascii=False, indent=2))
    return 0


def _derive_client_config(base_client_cfg: Dict[str, Any], protocol: str, cred: str) -> Dict[str, Any]:
    outbounds = base_client_cfg.get("outbounds")
    if not isinstance(outbounds, list) or not outbounds:
        raise RuntimeError("В client.json нет outbounds")
    ob0 = outbounds[0]
    if not isinstance(ob0, dict):
        raise RuntimeError("Неверный outbound[0]")
    settings = ob0.get("settings")
    if not isinstance(settings, dict):
        raise RuntimeError("В client.json outbound[0].settings не объект")

    if protocol == "vless":
        settings["id"] = cred
    elif protocol == "vmess":
        settings["id"] = cred
    elif protocol == "trojan":
        settings["password"] = cred
    else:
        raise RuntimeError(f"Неподдерживаемый protocol для client.json: {protocol}")
    return base_client_cfg


def cmd_add(config_path: Path, base_client_path: Path, email: str) -> int:
    cfg = _read_json(config_path)
    ib = _get_inbound(cfg)
    protocol = ib.get("protocol")

    clients = _clients_list(cfg)

    if protocol in ("vless", "vmess"):
        cred = _gen_uuid()
        new_client = {"id": cred, "level": 0, "email": email}
        if protocol == "vless":
            flow = ""
            if clients:
                flow = clients[0].get("flow", "")
            if isinstance(flow, str) and flow:
                new_client["flow"] = flow
        clients.append(new_client)
    elif protocol == "trojan":
        cred = secrets.token_urlsafe(24)
        clients.append({"password": cred, "level": 0, "email": email})
    else:
        raise RuntimeError(f"Неподдерживаемый inbound protocol: {protocol}")

    _clients_write(cfg, clients)
    _write_json(config_path, cfg, mode=0o644)
    _xray_test(str(config_path))
    _service_restart()

    base_client_cfg = _read_json(base_client_path)
    client_cfg = _derive_client_config(base_client_cfg, protocol, cred)
    out_path = base_client_path.parent / f"client.{email}.json"
    _write_json(out_path, client_cfg, mode=0o600)

    print(json.dumps({"email": email, "protocol": protocol, "credential": cred, "client_config": str(out_path)}, ensure_ascii=False, indent=2))
    return 0


def cmd_remove(config_path: Path, selector: str) -> int:
    cfg = _read_json(config_path)
    ib = _get_inbound(cfg)
    protocol = ib.get("protocol")
    clients = _clients_list(cfg)

    def keep(c: Dict[str, Any]) -> bool:
        if selector == c.get("email"):
            return False
        if protocol in ("vless", "vmess") and selector == c.get("id"):
            return False
        if protocol == "trojan" and selector == c.get("password"):
            return False
        return True

    new_clients = [c for c in clients if keep(c)]
    if len(new_clients) == len(clients):
        raise RuntimeError("Клиент не найден")

    _clients_write(cfg, new_clients)
    _write_json(config_path, cfg, mode=0o644)
    _xray_test(str(config_path))
    _service_restart()
    print(json.dumps({"removed": selector}, ensure_ascii=False, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/usr/local/etc/xray/config.json")
    ap.add_argument("--client", default="/usr/local/etc/xray/client.json")

    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("list")

    addp = sub.add_parser("add")
    addp.add_argument("--email", required=True)

    rmp = sub.add_parser("remove")
    rmp.add_argument("--selector", required=True)

    args = ap.parse_args()

    config_path = Path(args.config)
    client_path = Path(args.client)

    try:
        if args.cmd == "list":
            return cmd_list(config_path)
        if args.cmd == "add":
            return cmd_add(config_path, client_path, args.email)
        if args.cmd == "remove":
            return cmd_remove(config_path, args.selector)
    except Exception as e:
        print(str(e), file=sys.stderr)
        return 2

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
