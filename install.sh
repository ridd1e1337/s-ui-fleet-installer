#!/usr/bin/env bash
# Private-repository first entry; render with print-install-command.py.
# Explicit semicolons let the renderer join lines without changing shell syntax.
set +x;
set +a;
set -euo pipefail;
umask 077;
[[ $EUID == 0 ]] || { printf '%s\n' '请在 root 终端运行此安装命令。' >&2; exit 1; };
[[ $(uname -s) == Linux ]] || { printf '%s\n' '中控安装仅支持 Linux。' >&2; exit 1; };
case $(uname -m) in x86_64|amd64|aarch64|arm64) ;; *) printf '%s\n' '中控安装仅支持 amd64 / arm64。' >&2; exit 1 ;; esac;
if ! command -v curl >/dev/null || ! command -v mktemp >/dev/null || [[ ! -s /etc/ssl/certs/ca-certificates.crt && ! -s /etc/pki/tls/certs/ca-bundle.crt ]]; then
  printf '%s\n' '正在自动准备下载工具……';
  if command -v apt-get >/dev/null; then
    apt-get update;
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates coreutils;
  elif command -v dnf >/dev/null; then
    dnf install -y curl ca-certificates coreutils;
  else
    printf '%s\n' '中控需要支持 apt 或 dnf 的系统，推荐 Debian 12 / 13。' >&2; exit 1;
  fi;
fi;
unset fleet_pat;
fleet_script=$(mktemp);
trap 'rm -f -- "$fleet_script"; unset fleet_pat' EXIT;
printf '%s\n' 'S-UI Fleet 中控一键安装：私仓令牌仅用于本次下载，不会保存。' >/dev/tty;
IFS= read -rsp 'GitHub 只读 Token：' fleet_pat </dev/tty;
printf '\n' >/dev/tty;
[[ $fleet_pat =~ ^[A-Za-z0-9_]+$ && ${#fleet_pat} -le 4096 ]] || { printf '%s\n' '令牌为空或格式无效，安装已取消。' >&2; exit 1; };
fleet_status=$(printf 'Authorization: Bearer %s\n' "$fleet_pat" | curl -q --proto '=https' --fail --silent --show-error --connect-timeout 15 --max-time 60 --header @- --header 'Accept: application/vnd.github.raw+json' --header 'X-GitHub-Api-Version: 2022-11-28' --output "$fleet_script" --write-out '%{http_code}' 'https://api.github.com/repos/ridd1e1337/s-ui-fleet/contents/install.sh?ref=main') || { printf '%s\n' '下载安装入口失败，请核对网络及 Token 对此私有仓库的 Contents 读取权限。' >&2; exit 1; };
[[ $fleet_status == 200 && -s $fleet_script ]] || { printf '%s\n' '下载未返回完整安装入口，未执行安装。' >&2; exit 1; };
bash -n "$fleet_script" && [[ $(tail -n 1 "$fleet_script") == PY_FLEET_BOOTSTRAP ]] || { printf '%s\n' '安装入口不完整或格式错误，未执行安装。' >&2; exit 1; };
bash "$fleet_script" --online --github-token-fd 3 "$@" 3< <(printf '%s\n' "$fleet_pat");
