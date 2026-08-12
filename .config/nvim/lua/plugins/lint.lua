return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      python = { "ruff" },
      sh = { "shellcheck" },
      go = { "golangcilint" },
      yaml = { "yamllint" },
      markdown = { "markdownlint" },
      javascript = { "eslint_d" },
      javascriptreact = { "eslint_d" },
      typescript = { "eslint_d" },
      typescriptreact = { "eslint_d" },
    }

    -- nvim-lint 同梱の golangcilint は、nvim 起動時の cwd で引いた `go env GOMOD` が
    -- 空 (= モジュール外) だと単一ファイルを golangci-lint に渡す。マルチモジュールな
    -- リポジトリのルートで nvim を起動するとこれに該当し、同一パッケージの他ファイルが
    -- 見えないので `typecheck: undefined: Xxx` が大量に出る。常にパッケージ（ファイルの
    -- 親ディレクトリ）を渡すようにして防ぐ。
    local golangcilint = lint.linters.golangcilint
    if golangcilint and type(golangcilint.args) == "table" and #golangcilint.args > 0 then
      golangcilint.args[#golangcilint.args] = function()
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p:h")
      end
    end

    local lint_augroup = vim.api.nvim_create_augroup("UserNvimLint", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function(args)
        if vim.bo[args.buf].filetype == "go" then
          -- golangci-lint はパッケージ単位で数秒かかるので、Go は保存/読み込み時のみ。
          -- InsertLeave ごとに走らせると編集が引っかかる。
          if args.event == "InsertLeave" then
            return
          end
          -- モジュール外（マルチモジュールなリポジトリのルート等）で実行すると
          -- `no go files to analyze` で失敗するので、go.mod のあるディレクトリで動かす
          local go_mod_dir = vim.fs.root(args.buf, "go.mod")
          lint.try_lint(nil, go_mod_dir and { cwd = go_mod_dir } or nil)
          return
        end
        lint.try_lint()
      end,
    })
  end,
}
