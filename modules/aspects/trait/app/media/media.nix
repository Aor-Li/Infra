{ den, ... }:
{
  # 网易云音乐不在这里：官方 DMG 挂载时会弹「此磁盘映像可能有问题」的确认框，
  # brew 非交互的 hdiutil attach 直接被取消，cask 装不上也升级不了（会拖垮 switch），
  # 因此保持手动安装。上游修好后再加回 neteasemusic cask。
  den.aspects.app.media.includes = [
    den.aspects.app.media.bilibili
    den.aspects.app.media.shottr
  ];
}
