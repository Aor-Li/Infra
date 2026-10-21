# 关掉它你会失去：hf 命令行（Hugging Face Hub 的模型 / 数据集下载与上传）。
{
  den.aspects.dev.tool.hf.homeManager =
    { pkgs, ... }:
    {
      # nixpkgs 没有独立的 hf 包；CLI（hf / huggingface-cli）随 python 包 huggingface-hub 一起装，
      # 自带 hf-xet，大文件走 xet 协议下载。
      home.packages = [ pkgs.python3Packages.huggingface-hub ];
    };
}
