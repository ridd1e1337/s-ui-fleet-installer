# S-UI Fleet 安装引导

这里只存放公开的安装引导脚本，不包含 Fleet 业务源码、安装包或凭据。业务仓库和正式安装包保持私有。

脚本自动准备下载工具，提示输入一次具有目标私有仓库 Contents 读取权限的 GitHub Token，再取得主安装器。主安装器自动识别系统和 amd64 / arm64 架构、准备依赖、下载校验稳定发行版并进入配置流程。Token 不预置、不写入配置、不下发节点。

支持 root 终端；中控推荐 Debian 12 / 13、Ubuntu 22.04+，需要 systemd。自动申请证书时域名须解析到服务器，公网 TCP 80 空闲且可达，TCP 443 放行。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ridd1e1337/s-ui-fleet-installer/main/install.sh)
```

尚未安装 curl 时，Debian / Ubuntu 可一次执行以下命令自动准备下载工具并启动：

```bash
( set -e; apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates; fleet_entry=$(mktemp); trap 'rm -f -- "$fleet_entry"' EXIT; curl -fsSL https://raw.githubusercontent.com/ridd1e1337/s-ui-fleet-installer/main/install.sh -o "$fleet_entry"; bash "$fleet_entry" )
```

首次安装需要具有目标私有仓库读取权限的 Token。可在 [GitHub 创建细粒度令牌](https://github.com/settings/personal-access-tokens/new)，选择目标仓库并授予 `Contents: Read`。普通 GitHub 账号或无仓库权限的令牌不能下载业务程序。

本仓库采用 GPL-3.0 许可证。
