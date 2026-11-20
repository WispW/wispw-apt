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
sudo apt install xxx
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

- `.deb` 放在本仓库 GitHub Releases；Pages 只放 APT 元数据和公钥
- Release 正文包含 `Package`、`Version`、`SHA256`
- Release tag：`<package>-v<version>`
- Release 附件：`<package>.deb`，不带版本号
- 支持 Debian 12/13、Ubuntu 22.04/24.04/26.04

## 维护

- 生成元数据：`scripts/build-repo.sh`
- 本地验证：`scripts/test-repo.sh`
- Pages 自动发布：`.github/workflows/publish.yml`
