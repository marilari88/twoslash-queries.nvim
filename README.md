# twoslash-queries.nvim
Written in lua for nvim

Inspired by [vscode-twoslash-queries](https://github.com/orta/vscode-twoslash-queries), this plugin allows you to print typescript types as inline virtual text and dynamically update it instantly without having to move the cursor over the inspected variable

This is particularly useful when you are playing with complex typescript types:

["Added 
@typescript
 twoslash support to vscode with this little extension and I couldn't be happier with it"](https://twitter.com/tannerlinsley/status/1564254580715560960?s=20&t=E0Ap8W6vsFZhHyZFYlt_5w)

![twoslashqueries](https://user-images.githubusercontent.com/32909388/204164892-3c1444d3-8f2d-4c6d-8c1a-b812f1e4c657.gif)

## How to install it

### Packer
```lua
use("marilari88/twoslash-queries.nvim")
```

Make sure you have typescript language server properly installed and configured (personally I use Mason and Lspconfig plugins)

Then attach it on your tsserver in lspconfig setup
```lua
require("lspconfig")["tsserver"].setup({
    on_attach = function(client, bufnr)
       require("twoslash-queries").attach(client, bufnr)
    end,
})
```

Optionally you can define a custom keymap for InspectTwoslashQueries command
```lua
vim.api.nvim_set_keymap('n',"<C-k>","<cmd>InspectTwoslashQueries<CR>",{})
```
## Config
You can override default config use setup function:
```lua
use({
   "marilari88/twoslash-queries.nvim",			
    config = function()
        require("twoslash-queries").setup({
            multi_line = true, -- to print types in multi line mode
            is_enabled = false, -- to keep disabled at startup and enable it on request with the EnableTwoslashQueries 
	   })
    end,
})
```
Default config:
 - multi_line = false
 - is_enabled = true

## Usage
Write a `//    ^?` placing the sign `^` under the variable to inspected:
```typescript
const variableToInspect = ....
//      ^?
```

### Custom commands
`:EnableTwoslashQueries` Enable the plugin for the current session

`:DisableTwoslashQueries` Disable the plugin for the current session

`:InspectTwoslashQueries` Inspect variable under the cursor

`:RemoveTwoslashQueries` Remove all twoslash queries in the current buffer

![Commands](https://user-images.githubusercontent.com/32909388/204667598-5faa0b88-55af-4841-941d-6db79cfff013.gif)


## :gift: Contributing

Please raise a PR if you are interested in adding new functionality or fixing any bugs. When submitting a bug, please include an example spec that can be tested.
