# normal-cmdline.nvim

Lets you use normal mode in nvim cmdline.

https://github.com/user-attachments/assets/862298d9-9e9b-461e-9c86-ad5e7e90bc26

### example config (lazy.nvim)

```lua
{
    "jake-stewart/normal-cmdline.nvim",
    event = "CmdlineEnter",
    config = function()
        -- make the cmdline insert mode a beam
        vim.opt.guicursor:append("ci:ver1,c:ver1")

        local cmd = require("normal-cmdline")
        cmd.setup({
            -- key to hit within cmdline to enter normal mode:
            key = "<esc>",
            -- the cmdline text highlight when in normal mode:
            hl = "Normal",
            -- these mappings only apply to normal mode in cmdline:
            mappings = {
                ["k"] = cmd.history.prev,
                ["j"] = cmd.history.next,
                ["<cr>"] = cmd.accept,
                ["<esc>"] = cmd.cancel,
                ["<c-c>"] = cmd.cancel,
                [":"] = cmd.reset,
            }
        })
    end
}
```

### caveats
- Counts and dot register does not work for insert mode. This is
  because there is no insert mode. When you enter insert mode you
  really enter commandline mode so that completion works correctly.
- Search, input, and other cmdline modes other than `:` are not
  supported.
