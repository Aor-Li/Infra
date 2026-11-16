-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- 剪贴板：yank 通过 OSC 52 写回终端（本地或 ssh 另一端）的系统剪贴板。
-- LazyVim 默认在 SSH_TTY 下把 clipboard 设为 ""，这里统一覆盖掉；
-- 不依赖 nvim 的自动探测，因为隔着 tmux / Rex 时能力查询常被吞掉。
vim.opt.clipboard = "unnamedplus"

local osc52 = require("vim.ui.clipboard.osc52")
-- 粘贴不走 OSC 52 读取（终端默认禁止程序读剪贴板），退回 nvim 的无名寄存器；
-- 从本机往 nvim 粘贴继续用终端自己的粘贴快捷键（bracketed paste）。
local function paste()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end

vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
}
