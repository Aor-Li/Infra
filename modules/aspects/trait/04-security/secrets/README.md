# secrets

基于 [sops-nix](https://github.com/Mic92/sops-nix) 的密钥管理。密文经 age 加密后**可安全入库**，
明文私钥与解密结果都不入库。

## 存储位置约定

| | 密文（入库） | age 私钥（不入库，手动放置） | 解密后明文 |
| --- | --- | --- | --- |
| **系统级** | [`hosts/<hostName>.yaml`](hosts) | `/var/lib/sops-nix/key.txt` | `/run/secrets/<name>`（tmpfs） |
| **用户级** | [`users/<userName>.yaml`](users) | `~/.config/sops/age/keys.txt` | `%r/secrets/<name>`（`%r` = `XDG_RUNTIME_DIR`） |

密文文件按主机名 / 用户名自动匹配（见 [`secrets.nix`](secrets.nix)）：主机 `Enten` 找
`hosts/Enten.yaml`，用户 `aor` 找 `users/aor.yaml`。**文件不存在时自动跳过**（`pathExists` 兜底），
因此可以先只建需要的那个。

> 系统级刻意不使用 ssh host key 解密（`sops.age.sshKeyPaths = []`）——多数主机已按角色关闭 sshd
> （见 [`feature/network/ssh.nix`](../../network/ssh.nix)），没有可用的 host key。

## 新增一个 secret

```console
# 1) 首次：生成 age 私钥（用户级）
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt          # 公钥填进 .sops.yaml

# 2) 编辑密文（sops 会按 .sops.yaml 的 creation_rules 自动选 recipient）
cd modules/aspects/feature/security/secrets
sops users/aor.yaml                                # 系统级则用 hosts/<hostName>.yaml
```

然后在需要它的**特性就近**声明，而不是集中写在这里，例如：

```nix
sops.secrets.clauddy_auth_token = { };
# 引用：config.sops.placeholder.clauddy_auth_token（模板）
#      config.sops.secrets.clauddy_auth_token.path（文件路径）
```

## 待办

- [`feature/ai/claude.nix`](../../ai/claude.nix) 中 provider 认证（`ANTHROPIC_AUTH_TOKEN` 与
  `~/.claude/settings.json`）的 sops 配置目前是注释状态，待此处放好 `users/aor.yaml` 后接回。
- [`feature/network/tailscale.nix`](../../network/tailscale.nix) 待用 `authKeyFile` 免交互入网。
- [`.sops.yaml`](.sops.yaml) 中系统级规则暂用 aor 个人 key，待各主机生成 age key 后按主机拆分。
- 原 `feature/nix/settings.nix` 曾用 sops 模板注入 `github_access_token` 到 `nix.conf`（迁移时移除），
  需要时可接回。
