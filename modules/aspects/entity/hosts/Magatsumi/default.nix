# macbook pro
# include 同时作用于系统侧与 home 侧，见 Enten/default.nix。
{ den, ... }:
{
  den.aspects.Magatsumi.includes = [
    den.aspects.desktop.session.compositor.aerospace
    den.aspects.app
    den.aspects.desktop.input.karabiner
    den.aspects.dev.editor.vscode
    den.aspects.dev.editor.cursor
    den.aspects.service.remote.rustdesk
  ];
}
