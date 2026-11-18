# SSH 连接身份

`trait/network/ssh/` 只提供通用构造器、客户端参数选项及 Home Manager / SOPS 配置生成。
具体连接资料和密文跟随所属 entity：系统主机放 `entity/hosts/<Name>/`，
standalone home 放 `entity/homes/<user>@<name>/`。

## 注册与使用

在目标机器的 entity 中声明它提供的连接 aspect：

```nix
# entity/hosts/Example/ssh.nix
{ den, ... }:
{
  den.aspects.Example.provides.ssh = den.aspects.network.ssh.provides.target {
    name = "example"; # SSH 主别名，也是客户端 settings.targets 的键
    hostName = "example.org";
    user = "aor";
    port = 22;
  };
}
```

NixOS / nix-darwin 主机在自己的 host entity 中添加 `ssh.nix`。远程 Linux 服务器只管理
用户环境时，在 `den.homes` 注册 standalone home，并把连接身份放进相应的 home entity。
例如 `aor@ali-cloud/ssh.nix` 提供 `den.aspects."aor@ali-cloud".provides.ssh`。

客户端只 include 需要的连接 aspect：

```nix
den.aspects.Magatsumi.includes = [ den.aspects.Example.provides.ssh ];
# standalone home 同理：
den.aspects."aor@turbo-ai".includes = [ den.aspects."aor@ali-cloud".provides.ssh ];
```

定义目标、include 机器自身或填写客户端覆盖值，都不会自动启用它提供的 SSH 连接。
连接 aspect 只生成客户端配置，不携带被连接机器的系统配置，也不更改 sshd 或 authorized_keys。

## 目标事实与凭据

构造器支持 `name`（必填主别名）、`hostName`、`user`、`port`（默认 22）、`proxyJump`、
`identityFile`（运行时路径字符串）、`aliases`、`extraOptions`、`configSecret`、`identitySecret`。

- `aliases` 是附加别名到 OpenSSH 指令的映射，例如 `aliases.example-root.User = "root"`。
  各别名的专有指令先输出，共用连接参数后输出。
- `extraOptions` 是共用 OpenSSH 指令，例如 `ServerAliveInterval = 30`。
- `configSecret` / `identitySecret` 接受 SOPS secret 声明（`sopsFile`、`key` 等），
  框架统一使用 `0400` 权限。未提供凭据时，沿用 SSH 客户端自身的认证方式。

[AliCloud 的定义](../../../entity/homes/aor@ali-cloud/ssh.nix) 展示了附加 root 别名和加密凭据：
地址及 PEM 保存在同目录的 `ssh-secrets.yaml`。框架用 Host 块内的 `Include` 读取 `config`
字段的 HostName 片段，并用 `IdentityFile` 引用解密后的 `key`，运行时路径为
`config.sops.secrets."ssh/<name>/…".path`。地址片段不含 `Host` / `Match` 头。

私钥由 SOPS 在客户端解密，不通过 `readFile` 或 `home.file.source` 导入明文。公司内网
地址等内容同样使用密文或私有 input。客户端的 age 密钥默认放在
`~/.config/sops/age/keys.txt`；include 决定配置分发，age recipient 决定解密授权。

在仓库根目录编辑密文：

```console
sops --config modules/aspects/trait/security/secrets/.sops.yaml \
  modules/aspects/entity/homes/aor@ali-cloud/ssh-secrets.yaml
```

对于已有的多 Host 加密配置，可用 `provides.encryptedConfig { name; sopsFile; identityFiles; }`
封装，见 [TurboAI](../../../entity/homes/aor@turbo-ai/ssh.nix)。`config` 字段保留完整 Host 块，
`identityFiles` 将密文字段映射到 `~/.ssh/` 下的文件名；框架只 Include 该目标的确切文件，
不读取整个 `config.d`。这个构造器保留原始配置，下面的参数覆盖适用于 `provides.target`。

## 客户端差异

目标的默认值由 entity 注册；访问它的机器可以覆盖地址、主别名用户、端口、跳板和私钥路径：

```nix
den.hosts.aarch64-darwin.Magatsumi.settings.network.ssh.targets.AliCloud = {
  user = "aor";
  port = 22;
  # proxyJump = "gateway";  # 同时 include gateway 的连接 aspect
  # identityFile = "~/.ssh/my-existing-key";  # 运行时字符串，不是 Nix path
};
```

standalone 写到 `den.homes.<system>."<user>@<host>".settings`。
各项默认 `null`，表示沿用目标定义；`proxyJump = "none"` 可以覆盖目标预设的跳板。
指定 `hostName` 或 `identityFile` 后，对应的默认地址 secret 或私钥 secret 不再分发。
附加别名的固定用户（如 root）不受主别名的 `user` 覆盖影响。

## 迁移与生效

当前两台 Mac include TurboAI 和 AliCloud 的连接，并配置对应 Rex 隧道；
`aor@turbo-ai` include AliCloud 的连接。SSH 别名与 home 配置名独立。新增目标或客户端关系后执行对应的系统或 Home
Manager switch。Rex 的 SSH guard 由 Rex trait 注册。

不再默认读取 `config.local` 或 `config.d/*`；其他机器首次切换前先迁入需要的目标。
旧的 `~/.ssh/AliCloud.pem` 与 `config.d/AliCloud` 不再是新配置的入口。
