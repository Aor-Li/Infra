-- 关掉 Snacks bigfile 的「平均行长 > 1000」判定：单行 JSON 这类文件会被判成
-- bigfile，LSP / treesitter 全部禁用，<leader>cf 报 "No formatters available"。
-- 只按文件大小（默认 1.5MB）判定大文件。
return {
  {
    "folke/snacks.nvim",
    opts = {
      bigfile = {
        line_length = math.huge,
      },
    },
  },
}
