# WispW APT Repository

WispW 项目的第三方 APT 软件源：

```text
https://repo.wennie99s.top
```

当前提供：

- `hostnamefetch`

不是 Debian/Ubuntu 官方仓库。

## 安装

```sh
sudo install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://repo.wennie99s.top/wispw-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/wispw.gpg >/dev/null

echo "deb [signed-by=/etc/apt/keyrings/wispw.gpg] https://repo.wennie99s.top stable main" \
  | sudo tee /etc/apt/sources.list.d/wispw.list

sudo apt update
sudo apt install hostnamefetch
```

公钥指纹：

```text
EC40 94DD 2B7D A593 94CC  65F9 5FF3 4D62 F749 ABA6
```

升级：

```sh
sudo apt update && sudo apt upgrade
```

## 仓库说明

- `.deb` 归档在本仓库 GitHub Releases，并同步到 Pages 的 `pool/`
- Pages 只保留每个包的最新版本；历史版本请从对应 Release 下载
- 包均为 `Architecture: all`，索引在 `dists/stable/main/binary-all/`；
  同时为 amd64、arm64 等常见架构生成空索引，避免 `apt update` 报
  “doesn't support architecture” 提示
- Release 正文包含 `Package`、`Version`、`SHA256`
- Release tag：`<package>-v<version>`
- Release 附件：`<package>.deb`，不带版本号
- 支持 Debian 12/13、Ubuntu 22.04/24.04/26.04

## 维护

- 生成元数据：`scripts/build-repo.sh`
- 本地验证：`scripts/test-repo.sh`
- Pages 自动发布：`.github/workflows/publish.yml`
