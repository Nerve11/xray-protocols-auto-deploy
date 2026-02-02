#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдено в PATH: $1"
}

is_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ]
}

read_os_release() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${ID:-}|${VERSION_ID:-}"
    return 0
  fi
  echo "|"
}

assert_supported_os() {
  local id ver major
  IFS="|" read -r id ver < <(read_os_release)
  major="${ver%%.*}"

  case "$id" in
    ubuntu)
      [ "${major:-0}" -ge 22 ] || die "Требуется Ubuntu 22.04+"
      ;;
    debian)
      [ "${major:-0}" -ge 10 ] || die "Требуется Debian 10+"
      ;;
    centos|rhel)
      [ "${major:-0}" -ge 7 ] || die "Требуется CentOS/RHEL 7+"
      ;;
    *)
      die "Неподдерживаемая ОС: ${id:-unknown} ${ver:-}"
      ;;
  esac
}

install_packages() {
  local id
  IFS="|" read -r id _ < <(read_os_release)
  case "$id" in
    ubuntu|debian)
      need_cmd apt-get
      apt-get update -y
      apt-get install -y --no-install-recommends ca-certificates curl unzip python3
      ;;
    centos|rhel)
      need_cmd yum
      yum install -y ca-certificates curl unzip python3 || yum install -y ca-certificates curl unzip python
      ;;
    *)
      die "Неподдерживаемая ОС для установки пакетов: $id"
      ;;
  esac
}

install_xray_core() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  need_cmd curl
  curl -fsSL "https://github.com/XTLS/Xray-install/raw/main/install-release.sh" -o "$tmp/install-release.sh"
  chmod 700 "$tmp/install-release.sh"
  bash "$tmp/install-release.sh"

  if ! command -v xray >/dev/null 2>&1; then
    die "Xray установлен, но команда xray не найдена в PATH"
  fi
}

choose_profile_interactive() {
  python3 "$SCRIPT_DIR/generator/xpad.py" list-profiles || true
  echo
  read -r -p "Введите id профиля: " profile
  echo "$profile"
}

read_profile_meta() {
  local profile="$1"
  SCRIPT_DIR="$SCRIPT_DIR" PROFILE_ID="$profile" python3 - <<'PY'
import json
import os
from pathlib import Path

repo = Path(os.environ["SCRIPT_DIR"])
profiles_dir = repo / "profiles"
path = profiles_dir / (os.environ["PROFILE_ID"] + ".json")
if not path.exists():
  raise SystemExit(2)
obj = json.loads(path.read_text(encoding="utf-8"))
defaults = obj.get("defaults", {})
print(json.dumps({
  "id": obj.get("id"),
  "protocol": obj.get("protocol"),
  "transport": obj.get("transport"),
  "security": obj.get("security", "none"),
  "server_port": defaults.get("server_port", 443)
}, ensure_ascii=False))
PY
}

render_config() {
  local profile="$1"
  local out_dir="$2"
  local params_file="$3"

  python3 "$SCRIPT_DIR/generator/xpad.py" render --profile "$profile" --params "$params_file" --out "$out_dir"
}

write_systemd_service() {
  local xray_bin="$1"
  local config_path="$2"

  need_cmd systemctl

  cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
ExecStart=${xray_bin} run -c ${config_path}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xray.service
  systemctl restart xray.service
}

write_json() {
  local path="$1"
  local content="$2"
  install -d "$(dirname -- "$path")"
  printf '%s\n' "$content" > "$path"
}

main() {
  is_root || die "Запустите install.sh от root"

  assert_supported_os
  install_packages
  install_xray_core

  local profile domain server_addr server_port fingerprint
  profile="$(choose_profile_interactive)"
  [ -n "$profile" ] || die "Пустой profile id"

  local meta_json
  meta_json="$(read_profile_meta "$profile" || true)"
  [ -n "$meta_json" ] || die "Не удалось прочитать профиль: $profile"
  local security default_port
  security="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("security","none"))' <<<"$meta_json")"
  default_port="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("server_port",443))' <<<"$meta_json")"

  read -r -p "Домен для маскировки (SNI/host): " domain
  [ -n "$domain" ] || die "Пустой домен"

  read -r -p "Адрес сервера для client.json (домен или IP) [по умолчанию: $domain]: " server_addr
  server_addr="${server_addr:-$domain}"

  read -r -p "Порт сервера [по умолчанию: $default_port]: " server_port
  server_port="${server_port:-$default_port}"

  read -r -p "Fingerprint (chrome/firefox/safari/ios/android/edge/random/randomized) [по умолчанию: chrome]: " fingerprint
  fingerprint="${fingerprint:-chrome}"

  local params_dir out_dir xray_dir
  params_dir="/usr/local/etc/xpad"
  out_dir="/usr/local/etc/xpad/out/$profile"
  xray_dir="/usr/local/etc/xray"

  local params_file
  params_file="$params_dir/params.json"

  local params_json
  local tls_cert tls_key reality_target reality_server_names reality_server_name

  tls_cert=""
  tls_key=""
  reality_target=""
  reality_server_names=""
  reality_server_name=""

  if [ "$security" = "tls" ]; then
    read -r -p "Путь к certificateFile: " tls_cert
    [ -n "$tls_cert" ] || die "Пустой certificateFile"
    read -r -p "Путь к keyFile: " tls_key
    [ -n "$tls_key" ] || die "Пустой keyFile"
  fi

  if [ "$security" = "reality" ]; then
    read -r -p "Reality target (dest) [по умолчанию: ${domain}:443]: " reality_target
    reality_target="${reality_target:-${domain}:443}"
    read -r -p "Reality serverNames (через запятую) [по умолчанию: ${domain}]: " reality_server_names
    reality_server_names="${reality_server_names:-${domain}}"
    read -r -p "Reality serverName для клиента [по умолчанию: ${domain}]: " reality_server_name
    reality_server_name="${reality_server_name:-${domain}}"
  fi

  params_json="$(DOMAIN="$domain" SERVER_ADDR="$server_addr" SERVER_PORT="$server_port" FINGERPRINT="$fingerprint" TLS_CERT="$tls_cert" TLS_KEY="$tls_key" REALITY_TARGET="$reality_target" REALITY_SERVER_NAMES="$reality_server_names" REALITY_SERVER_NAME="$reality_server_name" SECURITY="$security" python3 - <<'PY'
import json
import os

params = {
  "domain": os.environ["DOMAIN"],
  "server_addr": os.environ["SERVER_ADDR"],
  "server_port": int(os.environ["SERVER_PORT"]),
  "fingerprint": os.environ["FINGERPRINT"],
  "serverName": os.environ["DOMAIN"],
}

if os.environ.get("SECURITY") == "tls":
  params["tls_certificateFile"] = os.environ["TLS_CERT"]
  params["tls_keyFile"] = os.environ["TLS_KEY"]

if os.environ.get("SECURITY") == "reality":
  params["reality_target"] = os.environ["REALITY_TARGET"]
  params["reality_serverNames"] = [x.strip() for x in os.environ["REALITY_SERVER_NAMES"].split(",") if x.strip()]
  params["reality_serverName"] = os.environ["REALITY_SERVER_NAME"]

print(json.dumps(params, ensure_ascii=False, indent=2))
PY
)"
  write_json "$params_file" "$params_json"

  render_config "$profile" "$out_dir" "$params_file"

  install -d "$xray_dir"
  install -m 644 "$out_dir/server.json" "$xray_dir/config.json"
  install -m 600 "$out_dir/client.json" "$xray_dir/client.json"
  install -m 600 "$out_dir/params.effective.json" "$xray_dir/params.effective.json"

  xray -test -c "$xray_dir/config.json"

  local xray_bin
  xray_bin="$(command -v xray)"
  write_systemd_service "$xray_bin" "$xray_dir/config.json"

  echo "Установка завершена"
  echo "Server config: $xray_dir/config.json"
  echo "Client config: $xray_dir/client.json"
}

main "$@"
