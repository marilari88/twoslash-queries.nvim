# twoslash-queries.nvim

![twoslashqueries](https://user-images.githubusercontent.com/32909388/204164892-3c1444d3-8f2d-4c6d-8c1a-b812f1e4c657.gif)

## How to install it
### Packer
```lua
use("marilari88/twoslash-queries")
```

then attach it on your tsserver in lspconfig setup
```lua
require("lspconfig")["tsserver"].setup({
	on_attach = function(client, bufnr)
		require("twoslash-queries").attach(client, bufnr)
	end,
  ...
})

```
