vim.lsp.config("basedpyright", {
  cmd = { "basedpyright-langserver", "--stdio" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "setup.py", "setup.cfg", ".git" },
})

vim.lsp.enable("basedpyright")

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("config.lsp", {}),
  callback = function(ev)
    local client = assert(vim.lsp.get_client_by_id(ev.data.client_id))
    local buf = ev.buf

    if client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end

    -- Navigation
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = buf, desc = "Go to definition" })
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { buffer = buf, desc = "Go to declaration" })
    vim.keymap.set("n", "gr", vim.lsp.buf.references, { buffer = buf, desc = "Go to references" })
    vim.keymap.set("n", "gI", vim.lsp.buf.implementation, { buffer = buf, desc = "Go to implementation" })
    vim.keymap.set("n", "gt", vim.lsp.buf.type_definition, { buffer = buf, desc = "Go to type definition" })
    vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = buf, desc = "Hover docs" })

    -- Edit
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { buffer = buf, desc = "Rename symbol" })
    vim.keymap.set({ "n", "x" }, "<leader>ca", vim.lsp.buf.code_action, { buffer = buf, desc = "Code action" })
    if client:supports_method("textDocument/formatting") then
      vim.keymap.set("n", "<leader>f", function()
        vim.lsp.buf.format({ bufnr = buf })
      end, { buffer = buf, desc = "Format buffer" })
    end

    -- Diagnostics
    vim.keymap.set("n", "]d", function()
      vim.diagnostic.jump({ count = 1, bufnr = buf })
    end, { buffer = buf, desc = "Next diagnostic" })
    vim.keymap.set("n", "[d", function()
      vim.diagnostic.jump({ count = -1, bufnr = buf })
    end, { buffer = buf, desc = "Previous diagnostic" })
    vim.keymap.set("n", "<leader>d", function()
      vim.diagnostic.open_float({ bufnr = buf })
    end, { buffer = buf, desc = "Show diagnostic" })

    -- Completion & signature help
    vim.keymap.set({ "n", "i" }, "<C-Space>", function()
      vim.lsp.completion.get()
    end, { buffer = buf, desc = "Trigger completion" })
    vim.keymap.set("i", "<C-h>", function()
      vim.lsp.buf.signature_help()
    end, { buffer = buf, desc = "Signature help" })
  end,
})
