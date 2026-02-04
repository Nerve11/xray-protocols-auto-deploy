import argparse
import base64
import json
import os
import secrets
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


REPO_ROOT = Path(__file__).resolve().parents[1]
PROFILES_DIR = REPO_ROOT / "profiles"


class ProfileError(RuntimeError):
    pass


def _read_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _list_profiles() -> List[Dict[str, Any]]:
    if not PROFILES_DIR.exists():
        return []
    profiles = []
    for p in sorted(PROFILES_DIR.glob("*.json")):
        try:
            obj = _read_json(p)
        except Exception:
            continue
        obj["_path"] = str(p)
        profiles.append(obj)
    return profiles


def _get_profile(profile_id: str) -> dict:
    candidates = [p for p in _list_profiles() if p.get("id") == profile_id]
    if not candidates:
        raise ProfileError(f"Профиль не найден: {profile_id}")
    return candidates[0]


def _xray_cmd() -> Optional[str]:
    for name in ("xray", "xray.exe"):
        for dir_ in os.getenv("PATH", "").split(os.pathsep):
            if not dir_:
                continue
            if (Path(dir_) / name).exists():
                return name
    return None


def _run_xray(args: List[str]) -> str:
    cmd = _xray_cmd()
    if not cmd:
        raise ProfileError("Команда xray не найдена в PATH")
    p = subprocess.run([cmd, *args], capture_output=True, text=True, check=True)
    return p.stdout.strip()


def _gen_uuid() -> str:
    try:
        out = _run_xray(["uuid"])
        if out:
            return out.splitlines()[-1].strip()
    except Exception:
        pass
    return str(__import__("uuid").uuid4())


def _gen_reality_keypair() -> Tuple[str, str]:
    output = _run_xray(["x25519"])
    private_key = ""
    public_key = ""
    
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("Private key:"):
            private_key = line.split(":", 1)[1].strip()
        elif line.startswith("Public key:"):
            public_key = line.split(":", 1)[1].strip()
    
    if not private_key or not public_key:
        raise ProfileError("Не удалось извлечь ключи из вывода xray x25519")
    
    return private_key, public_key


def _gen_short_id() -> str:
    return secrets.token_hex(8)


def _require_str(params: Dict[str, Any], key: str) -> str:
    v = params.get(key)
    if v is None:
        raise ProfileError(f"Не задано обязательное поле: {key}")
    if not isinstance(v, str) or not v.strip():
        raise ProfileError(f"Поле {key} должно быть непустой строкой")
    return v.strip()


def _require_list(params: Dict[str, Any], key: str) -> List[Any]:
    v = params.get(key)
    if v is None:
        raise ProfileError(f"Не задано обязательное поле: {key}")
    if not isinstance(v, list) or len(v) == 0:
        raise ProfileError(f"Поле {key} должно быть непустым массивом")
    return v


def _maybe(params: dict, key: str, default=None):
    v = params.get(key)
    return default if v is None else v


def _base_server() -> Dict[str, Any]:
    return {
        "log": {"loglevel": "warning"},
        "inbounds": [],
        "outbounds": [
            {"protocol": "freedom", "tag": "direct"},
            {"protocol": "blackhole", "tag": "block"},
        ],
    }


def _base_client() -> Dict[str, Any]:
    return {
        "log": {"loglevel": "warning"},
        "inbounds": [
            {
                "listen": "127.0.0.1",
                "port": 1080,
                "protocol": "socks",
                "settings": {"auth": "noauth", "udp": True},
            }
        ],
        "outbounds": [
            {"protocol": "freedom", "tag": "direct"},
            {"protocol": "blackhole", "tag": "block"},
        ],
    }


def _stream_settings(profile: Dict[str, Any], params: Dict[str, Any], side: str) -> Dict[str, Any]:
    network = profile["transport"]
    security = profile.get("security", "none")

    stream = {
        "network": network,
        "security": security,
    }

    if network == "ws":
        ws_path = _maybe(params, "ws_path", profile.get("defaults", {}).get("ws_path", "/"))
        ws_host = _maybe(params, "ws_host", _maybe(params, "domain", ""))
        stream["wsSettings"] = {"path": ws_path, "host": ws_host}
    elif network == "grpc":
        defaults = profile.get("defaults", {})
        grpc = {
            "authority": _maybe(params, "grpc_authority", _maybe(params, "domain", "")),
            "serviceName": _maybe(params, "grpc_serviceName", defaults.get("grpc_serviceName", "grpc")),
            "multiMode": bool(_maybe(params, "grpc_multiMode", defaults.get("grpc_multiMode", False))),
        }
        stream["grpcSettings"] = grpc
    elif network == "kcp":
        defaults = profile.get("defaults", {})
        stream["kcpSettings"] = {
            "mtu": int(_maybe(params, "kcp_mtu", defaults.get("kcp_mtu", 1350))),
            "tti": int(_maybe(params, "kcp_tti", defaults.get("kcp_tti", 50))),
            "uplinkCapacity": int(_maybe(params, "kcp_uplinkCapacity", defaults.get("kcp_uplinkCapacity", 5))),
            "downlinkCapacity": int(_maybe(params, "kcp_downlinkCapacity", defaults.get("kcp_downlinkCapacity", 20))),
            "congestion": bool(_maybe(params, "kcp_congestion", defaults.get("kcp_congestion", False))),
            "readBufferSize": int(_maybe(params, "kcp_readBufferSize", defaults.get("kcp_readBufferSize", 2))),
            "writeBufferSize": int(_maybe(params, "kcp_writeBufferSize", defaults.get("kcp_writeBufferSize", 2))),
        }
    elif network == "xhttp":
        stream["xhttpSettings"] = {}
    elif network == "raw":
        stream["rawSettings"] = {}
    else:
        raise ProfileError(f"Неизвестный transport: {network}")

    if security == "tls":
        fingerprint = _maybe(params, "fingerprint", profile.get("defaults", {}).get("fingerprint", "chrome"))
        server_name = _maybe(params, "serverName", _maybe(params, "domain", ""))
        allow_insecure = bool(_maybe(params, "tls_allowInsecure", False)) if side == "client" else False
        tls = {"allowInsecure": allow_insecure, "serverName": server_name, "fingerprint": fingerprint}
        if side == "server":
            cert_file = _require_str(params, "tls_certificateFile")
            key_file = _require_str(params, "tls_keyFile")
            tls["certificates"] = [{"certificateFile": cert_file, "keyFile": key_file}]
        stream["tlsSettings"] = tls

    if security == "reality":
        if side == "server":
            reality = {
                "target": _require_str(params, "reality_target"),
                "serverNames": _require_list(params, "reality_serverNames"),
                "privateKey": _require_str(params, "reality_privateKey"),
                "shortIds": _require_list(params, "reality_shortIds"),
            }
        else:
            reality = {
                "serverName": _require_str(params, "reality_serverName"),
                "fingerprint": _require_str(params, "reality_fingerprint"),
                "password": _require_str(params, "reality_password"),
                "shortId": _require_str(params, "reality_shortId"),
            }
        stream["realitySettings"] = reality

    return stream


def _server_inbound(profile: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
    protocol = profile["protocol"]
    port = int(_maybe(params, "server_port", profile.get("defaults", {}).get("server_port", 443)))

    inbound = {"port": port, "protocol": protocol, "settings": {}, "streamSettings": _stream_settings(profile, params, "server")}

    if protocol == "vless":
        user_id = _maybe(params, "uuid", None) or _gen_uuid()
        flow = _maybe(params, "flow", profile.get("defaults", {}).get("flow", "xtls-rprx-vision"))
        inbound["settings"] = {"clients": [{"id": user_id, "level": 0, "email": "", "flow": flow}], "decryption": "none"}
    elif protocol == "vmess":
        user_id = _maybe(params, "uuid", None) or _gen_uuid()
        inbound["settings"] = {"clients": [{"id": user_id, "level": 0, "email": ""}]}
    elif protocol == "trojan":
        password = _maybe(params, "trojan_password", None) or secrets.token_urlsafe(24)
        inbound["settings"] = {"clients": [{"password": password, "email": "", "level": 0}]}
    else:
        raise ProfileError(f"Неизвестный protocol: {protocol}")

    return inbound


def _client_outbound(profile: Dict[str, Any], params: Dict[str, Any]) -> Dict[str, Any]:
    protocol = profile["protocol"]
    server_addr = _require_str(params, "server_addr")
    server_port = int(_maybe(params, "server_port", profile.get("defaults", {}).get("server_port", 443)))

    outbound = {"tag": "proxy", "protocol": protocol, "settings": {}, "streamSettings": _stream_settings(profile, params, "client")}

    if protocol == "vless":
        user_id = _maybe(params, "uuid", None) or _gen_uuid()
        flow = _maybe(params, "flow", profile.get("defaults", {}).get("flow", "xtls-rprx-vision"))
        outbound["settings"] = {
            "address": server_addr,
            "port": server_port,
            "id": user_id,
            "encryption": "none",
            "flow": flow,
            "level": 0,
        }
    elif protocol == "vmess":
        user_id = _maybe(params, "uuid", None) or _gen_uuid()
        outbound["settings"] = {"address": server_addr, "port": server_port, "id": user_id, "security": "auto", "level": 0}
    elif protocol == "trojan":
        password = _require_str(params, "trojan_password")
        outbound["settings"] = {"address": server_addr, "port": server_port, "password": password, "level": 0}
    else:
        raise ProfileError(f"Неизвестный protocol: {protocol}")

    return outbound


def render(profile_id: str, params_path: Path, out_dir: Path) -> None:
    profile = _get_profile(profile_id)
    params = _read_json(params_path)

    if profile.get("security") == "reality":
        if params.get("reality_privateKey") in (None, "") or params.get("reality_password") in (None, ""):
            private_key, public_key = _gen_reality_keypair()
            params.setdefault("reality_privateKey", private_key)
            params.setdefault("reality_password", public_key)
        params.setdefault("reality_fingerprint", _maybe(params, "fingerprint", "chrome"))
        params.setdefault("reality_shortIds", [_gen_short_id()])
        params.setdefault("reality_shortId", params["reality_shortIds"][0])

        if isinstance(params.get("reality_serverNames"), str):
            params["reality_serverNames"] = [params["reality_serverNames"]]

    if profile["protocol"] in ("vless", "vmess"):
        params.setdefault("uuid", _gen_uuid())
    if profile["protocol"] == "trojan":
        params.setdefault("trojan_password", secrets.token_urlsafe(24))

    server_cfg = _base_server()
    server_cfg["inbounds"].append(_server_inbound(profile, params))

    client_cfg = _base_client()
    client_cfg["outbounds"].insert(0, _client_outbound(profile, params))

    out_dir.mkdir(parents=True, exist_ok=True)
    _write_json(out_dir / "server.json", server_cfg)
    _write_json(out_dir / "client.json", client_cfg)
    _write_json(out_dir / "params.effective.json", params)


def _qs(params: Dict[str, Any]) -> str:
    parts = []
    for k, v in params.items():
        if v is None:
            continue
        if isinstance(v, bool):
            v = "1" if v else "0"
        else:
            v = str(v)
        parts.append((k, v))
    from urllib.parse import quote

    return "&".join([f"{quote(k, safe='')}={quote(v, safe='')}" for k, v in parts])


def share(profile_id: str, params_path: Path) -> Dict[str, Any]:
    profile = _get_profile(profile_id)
    params = _read_json(params_path)

    protocol = profile["protocol"]
    transport = profile["transport"]
    security = profile.get("security", "none")

    server_addr = params.get("server_addr") or params.get("serverName") or params.get("domain") or ""
    server_port = int(params.get("server_port") or profile.get("defaults", {}).get("server_port", 443))

    if protocol == "trojan":
        password = params.get("trojan_password") or ""
        if not (server_addr and password):
            return {"ok": False, "error": "Недостаточно данных для trojan:// ссылки"}

        q = {"type": transport}
        if security == "tls":
            q["security"] = "tls"
            q["sni"] = params.get("serverName") or params.get("domain") or ""
            q["fp"] = params.get("fingerprint") or "chrome"
            if params.get("tls_allowInsecure"):
                q["allowInsecure"] = True

        if transport == "grpc":
            q["serviceName"] = params.get("grpc_serviceName") or profile.get("defaults", {}).get("grpc_serviceName", "grpc")
            q["mode"] = "multi" if bool(params.get("grpc_multiMode") or profile.get("defaults", {}).get("grpc_multiMode", False)) else "gun"
        if transport == "ws":
            q["path"] = params.get("ws_path") or profile.get("defaults", {}).get("ws_path", "/")
            q["host"] = params.get("ws_host") or params.get("domain") or ""

        link = f"trojan://{password}@{server_addr}:{server_port}?{_qs(q)}#{profile_id}"
        return {"ok": True, "link": link, "profile": profile_id}

    if protocol == "vless":
        user_id = params.get("uuid") or ""
        if not (server_addr and user_id):
            return {"ok": False, "error": "Недостаточно данных для vless:// ссылки"}

        q = {"encryption": "none", "type": transport}
        flow = params.get("flow") or profile.get("defaults", {}).get("flow")
        if flow:
            q["flow"] = flow

        if security == "tls":
            q["security"] = "tls"
            q["sni"] = params.get("serverName") or params.get("domain") or ""
            q["fp"] = params.get("fingerprint") or "chrome"
            if params.get("tls_allowInsecure"):
                q["allowInsecure"] = True

        if security == "reality":
            q["security"] = "reality"
            q["sni"] = params.get("reality_serverName") or params.get("domain") or ""
            q["fp"] = params.get("reality_fingerprint") or params.get("fingerprint") or "chrome"
            q["pbk"] = params.get("reality_password") or ""
            q["sid"] = params.get("reality_shortId") or ""

        if transport == "grpc":
            q["serviceName"] = params.get("grpc_serviceName") or profile.get("defaults", {}).get("grpc_serviceName", "grpc")
            q["mode"] = "multi" if bool(params.get("grpc_multiMode") or profile.get("defaults", {}).get("grpc_multiMode", False)) else "gun"
        if transport == "ws":
            q["path"] = params.get("ws_path") or profile.get("defaults", {}).get("ws_path", "/")
            q["host"] = params.get("ws_host") or params.get("domain") or ""

        link = f"vless://{user_id}@{server_addr}:{server_port}?{_qs(q)}#{profile_id}"
        return {"ok": True, "link": link, "profile": profile_id}

    if protocol == "vmess":
        user_id = params.get("uuid") or ""
        if not (server_addr and user_id):
            return {"ok": False, "error": "Недостаточно данных для vmess:// ссылки"}
        if security != "none":
            return {"ok": False, "error": f"vmess:// ссылка не поддерживает security={security} в этом генераторе"}

        vmess_obj = {
            "v": "2",
            "ps": profile_id,
            "add": server_addr,
            "port": str(server_port),
            "id": user_id,
            "aid": "0",
            "scy": "auto",
            "net": transport,
            "type": "none",
            "host": params.get("ws_host") or "",
            "path": params.get("ws_path") or "",
            "tls": "",
            "sni": params.get("serverName") or "",
        }
        raw = json.dumps(vmess_obj, ensure_ascii=False).encode("utf-8")
        link = "vmess://" + base64.b64encode(raw).decode("ascii")
        return {"ok": True, "link": link, "profile": profile_id}

    return {"ok": False, "error": f"Ссылка не поддерживается для protocol={protocol}"}


def main() -> int:
    ap = argparse.ArgumentParser(prog="xpad")
    sub = ap.add_subparsers(dest="cmd", required=True)

    lp = sub.add_parser("list-profiles")

    rp = sub.add_parser("render")
    rp.add_argument("--profile", required=True)
    rp.add_argument("--params", required=True)
    rp.add_argument("--out", required=True)

    sp = sub.add_parser("share")
    sp.add_argument("--profile", required=True)
    sp.add_argument("--params", required=True)

    args = ap.parse_args()

    if args.cmd == "list-profiles":
        profiles = _list_profiles()
        print(json.dumps([{"id": p.get("id"), "protocol": p.get("protocol"), "transport": p.get("transport"), "security": p.get("security")} for p in profiles], ensure_ascii=False, indent=2))
        return 0

    if args.cmd == "render":
        try:
            render(args.profile, Path(args.params), Path(args.out))
            return 0
        except ProfileError as e:
            print(str(e))
            return 2

    if args.cmd == "share":
        out = share(args.profile, Path(args.params))
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
