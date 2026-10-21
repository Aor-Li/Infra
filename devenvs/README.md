# devenvs

不想把 devenv 配置提交进项目仓库时（公司仓库、上游开源仓库），配置放在这里，由
`devenv-deploy`（见 `modules/aspects/trait/dev/env/devenv.nix`）以 symlink 的形式投放到项目里。

每个子目录是一个项目，必须包含 `devenv.nix`、`devenv.yaml`、`.envrc` 三个文件：

```console
cp -r ~/Infra/devenvs/example ~/Infra/devenvs/<project>   # 新建
cd ~/code/<project> && devenv-deploy <project>             # 投放三个 symlink
direnv allow
```

`devenv.lock` 与 `.devenv/` 生成在项目目录里，记得加进项目的 `.git/info/exclude`。
