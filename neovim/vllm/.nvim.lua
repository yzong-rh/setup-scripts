local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local venv = vim.fs.joinpath(root, ".venv")
local venv_python = vim.fs.joinpath(venv, "bin", "python")

if vim.fn.executable(venv_python) == 1 then
  vim.env.VIRTUAL_ENV = venv
  vim.lsp.config("basedpyright", {
    settings = {
      python = {
        pythonPath = venv_python,
      },
    },
  })
else
  vim.notify("vllm: missing .venv/bin/python — run your usual venv setup", vim.log.levels.WARN)
end

vim.lsp.config("ruff", {
  cmd = { "ruff", "server" },
  filetypes = { "python" },
  root_markers = { "pyproject.toml", "ruff.toml", ".ruff.toml", ".git" },
})

vim.lsp.enable("ruff")
