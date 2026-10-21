{ den, ... }:
{
  # 桌面外壳（顶栏 / 面板 / launcher / notifier 等）的汇总节点。
  den.aspects.desktop.shell.includes = [
    den.aspects.desktop.shell.quickshell
  ];
}
