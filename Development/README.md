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

## alpha.82

Apply the alpha.82 data recipe to an alpha.81 binary:

```
python build_alpha82.py /path/to/alpha81/KenshiShop.mod ../KenshiShop/KenshiShop.mod
texlua tests/duty.lua ../KenshiShop/scripts
```

`tests/data.py` now additionally validates alpha.82 native packages and compares physical building/furniture modules with the repository's `v0.3.0-alpha.81` tag. Run it from the repository root as CI does.
