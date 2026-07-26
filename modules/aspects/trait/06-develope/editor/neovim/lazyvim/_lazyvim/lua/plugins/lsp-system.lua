return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
        },
        pyright = {
          mason = false,
        },
        nil_ls = {
          mason = false,
        },
      },
    },
  },
}
