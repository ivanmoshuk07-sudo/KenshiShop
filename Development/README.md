# Development

Rebuild the data files from the supplied alpha.80 source (not from alpha.81):

```
python build_alpha81.py /path/to/alpha80/KenshiShop/KenshiShop.mod /path/to/release/KenshiShop/KenshiShop.mod
```

If the alpha.80 sibling `KenshiShop_LegendaryCompat` is present, its optional weapon override is rebuilt too.

Run the Lua behavioral tests with a Lua 5.3+ interpreter (or texlua):

```
texlua tests/runtime.lua ../KenshiShop/scripts
texlua tests/controller.lua ../KenshiShop/scripts
python tests/data.py /path/to/alpha80/KenshiShop/KenshiShop.mod ../KenshiShop/KenshiShop.mod
```

The tests use fake engine objects; they do not test the native game AI or ABI. Runtime Lua modules require the same KenshiLua setup as alpha.80. No development libraries need to be installed into Kenshi.

`kenshimod.py` is from https://github.com/LucasSKrewer/kenshi-modkit under the included MIT license. It is used only by the Python build/validation scripts.
