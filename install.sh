#!/usr/bin/env bash
# Private-repository first entry; render with print-install-command.py.
# Explicit semicolons let the renderer join lines without changing shell syntax.
set +x;
set +a;
set -euo pipefail;
umask 077;
unset fleet_pat fleet_env_pat;
fleet_env_pat=${GH_TOKEN:-${GITHUB_TOKEN:-}};
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN;
fleet_root=${SUI_FLEET_ROOT:-/};
fleet_no_save=false;
fleet_input_fd='';
fleet_arguments=();
while (($#)); do
  case "$1" in
    --root|--github-token-fd)
      (($# >= 2)) && [[ -n $2 ]] || { printf '%s\n' '安装参数缺少值。' >&2; exit 1; };
      if [[ $1 == --root ]]; then fleet_root=$2; fleet_arguments+=("$1" "$2"); else fleet_input_fd=$2; fi;
      shift 2 ;;
    --root=*) fleet_root=${1#*=}; fleet_arguments+=("$1"); shift ;;
    --github-token-fd=*) fleet_input_fd=${1#*=}; shift ;;
    --no-save-token) fleet_no_save=true; fleet_arguments+=("$1"); shift ;;
    *) fleet_arguments+=("$1"); shift ;;
  esac;
done;
[[ -n $fleet_root ]] || { printf '%s\n' '安装根目录不能为空。' >&2; exit 1; };
[[ $fleet_root == /* ]] || fleet_root="$(pwd -P)/$fleet_root";
[[ $fleet_root != *$'\n'* && $fleet_root != *$'\r'* ]] || { printf '%s\n' '安装根目录格式无效。' >&2; exit 1; };
IFS=/ read -ra fleet_root_parts <<< "$fleet_root";
fleet_normalized_root='';
for fleet_component in "${fleet_root_parts[@]}"; do
  case "$fleet_component" in ''|.) continue ;; ..) printf '%s\n' '安装根目录不能包含 ..。' >&2; exit 1 ;; esac;
  fleet_normalized_root+="/$fleet_component";
  [[ ! -L $fleet_normalized_root ]] || { printf '%s\n' '安装根目录不能经过符号链接。' >&2; exit 1; };
done;
fleet_root=${fleet_normalized_root:-/};
[[ $EUID == 0 ]] || { printf '%s\n' '请在 root 终端运行此安装命令。' >&2; exit 1; };
[[ $(uname -s) == Linux ]] || { printf '%s\n' '中控安装仅支持 Linux。' >&2; exit 1; };
case $(uname -m) in x86_64|amd64|aarch64|arm64) ;; *) printf '%s\n' '中控安装仅支持 amd64 / arm64。' >&2; exit 1 ;; esac;
if ! command -v curl >/dev/null || ! command -v mktemp >/dev/null || ! command -v stat >/dev/null || [[ ! -s /etc/ssl/certs/ca-certificates.crt && ! -s /etc/pki/tls/certs/ca-bundle.crt ]]; then
  [[ $fleet_root == / ]] || { printf '%s\n' '预置安装不会修改宿主依赖；请先准备 curl、CA 根证书与 coreutils。' >&2; exit 1; };
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
fleet_validate_token() {
  [[ $fleet_pat =~ ^[A-Za-z0-9_]+$ && ${#fleet_pat} -le 4096 ]] || { printf '%s\n' '令牌为空或格式无效，安装已取消。' >&2; return 1; };
};
fleet_read_saved() {
  local file="${fleet_root%/}/etc/s-ui/github/ridd1e1337/s-ui-fleet.token" directory owner mode links size;
  [[ -e $file || -L $file ]] || return 1;
  [[ -f $file && ! -L $file ]] || return 2;
  read -r owner mode links size < <(stat -c '%u %a %h %s' -- "$file") || return 2;
  [[ $owner == 0 && $mode == 600 && $links == 1 && $size -gt 1 && $size -le 4097 ]] || return 2;
  directory=${file%/*};
  while :; do
    [[ -d $directory && ! -L $directory ]] || return 2;
    read -r owner mode < <(stat -c '%u %a' -- "$directory") || return 2;
    [[ $owner == 0 && $mode =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 )) || return 2;
    case "$directory" in
      "${fleet_root%/}/etc/s-ui"|"${fleet_root%/}/etc/s-ui/github"|"${fleet_root%/}/etc/s-ui/github/ridd1e1337") [[ $mode == 700 ]] || return 2 ;;
    esac;
    [[ $directory != "$fleet_root" ]] || break;
    directory=${directory%/*};
    [[ -n $directory ]] || directory=/;
  done;
  fleet_pat=$(<"$file");
  [[ $size == $((${#fleet_pat} + 1)) ]] || return 2;
  fleet_validate_token || return 2;
};
fleet_prompt_token() {
  local terminal;
  if ! { exec {terminal}<>/dev/tty; } 2>/dev/null; then
    printf '%s\n' '没有可用的已保存凭据，且当前没有交互终端；请通过 --github-token-fd 提供只读 Token。' >&2; return 1;
  fi;
  if ! IFS= read -rsp 'GitHub 只读 Token：' fleet_pat <&"$terminal" 2>&"$terminal"; then exec {terminal}>&-; printf '\n%s\n' '未读取到令牌，安装已取消。' >&2; return 1; fi;
  printf '\n' >&"$terminal";
  exec {terminal}>&-;
  fleet_validate_token;
};
fleet_pat='';
fleet_source='';
if [[ -n $fleet_input_fd ]]; then
  [[ $fleet_input_fd =~ ^[0-9]+$ && $fleet_input_fd -ge 3 ]] || { printf '%s\n' '令牌描述符必须大于或等于 3。' >&2; exit 1; };
  if ! { IFS= read -r -N 4098 fleet_pat <&"$fleet_input_fd"; } 2>/dev/null; then [[ -n $fleet_pat ]] || { printf '%s\n' '无法读取 GitHub 令牌描述符。' >&2; exit 1; }; fi;
  fleet_pat=${fleet_pat%$'\n'};
  fleet_source=fd;
elif [[ -n $fleet_env_pat ]]; then
  fleet_pat=$fleet_env_pat;
  fleet_source=environment;
elif [[ $fleet_no_save != true ]]; then
  if fleet_read_saved; then
    fleet_source=saved;
    printf '%s\n' '正在复用此仓库已保存的 root GitHub 凭据。';
  else
    fleet_saved_status=$?;
    [[ $fleet_saved_status == 1 ]] || { printf '%s\n' '已保存的 GitHub 凭据路径、权限或格式不安全，拒绝读取；凭据目录应由 root 独占（0700），文件为 root 0600 普通文件。' >&2; exit 1; };
  fi;
fi;
unset fleet_env_pat;
if [[ -z $fleet_source ]] && command -v gh >/dev/null; then
  if fleet_pat=$(gh auth token --hostname github.com 2>/dev/null) && [[ -n $fleet_pat ]]; then fleet_source=gh; else fleet_pat=''; fi;
fi;
if [[ $fleet_no_save == true ]]; then
  printf '%s\n' 'S-UI Fleet 中控一键安装：本次不读取或保存 GitHub 凭据。';
else
  printf '%s\n' 'S-UI Fleet 中控一键安装：仓库授权验证成功后，安装器将为 root 保存此仓库凭据，后续安装与更新自动复用。';
fi;
if [[ -z $fleet_source ]]; then fleet_prompt_token; fleet_source=prompt; else fleet_validate_token; fi;
fleet_script=$(mktemp);
trap 'rm -f -- "$fleet_script"; unset fleet_pat' EXIT;
fleet_download_entry() {
  if fleet_status=$(printf 'Authorization: Bearer %s\n' "$fleet_pat" | curl -q --proto '=https' --fail --silent --show-error --connect-timeout 15 --max-time 60 --header @- --header 'Accept: application/vnd.github.raw+json' --header 'X-GitHub-Api-Version: 2022-11-28' --output "$fleet_script" --write-out '%{http_code}' 'https://api.github.com/repos/ridd1e1337/s-ui-fleet/contents/install.sh?ref=main'); then fleet_curl_status=0; else fleet_curl_status=$?; fi;
};
fleet_download_entry;
if [[ $fleet_source == saved && ( $fleet_status == 401 || $fleet_status == 404 ) && ( $fleet_curl_status == 0 || $fleet_curl_status == 22 ) ]]; then
  printf '%s\n' '已保存的 GitHub 凭据已失效或无仓库权限，请重新输入一次；新凭据通过仓库授权验证后才会替换旧值。' >&2;
  fleet_prompt_token;
  fleet_download_entry;
fi;
[[ $fleet_curl_status == 0 ]] || { printf '%s\n' '下载安装入口失败，请核对网络及 Token 对此私有仓库的 Contents 读取权限；已保存凭据保持不变。' >&2; exit 1; };
[[ $fleet_status == 200 && -s $fleet_script ]] || { printf '%s\n' '下载未返回完整安装入口，未执行安装。' >&2; exit 1; };
bash -n "$fleet_script" && [[ $(tail -n 1 "$fleet_script") == PY_FLEET_BOOTSTRAP ]] || { printf '%s\n' '安装入口不完整或格式错误，未执行安装。' >&2; exit 1; };
bash "$fleet_script" --online --github-token-fd 3 "${fleet_arguments[@]}" 3< <(printf '%s\n' "$fleet_pat");
