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

## alpha.83

`python Development/build_alpha83.py /path/to/alpha82/KenshiShop.mod KenshiShop/KenshiShop.mod`

Adds only five versioned packages so saved squads can migrate and restock once.
The shop IDs were cross-checked against the user's `Kenshi_Shops_Offline(1).zip`,
whose HTML shop index identifies Scraphouse 56154-rebirth.mod, Mechanical Shop
44855-rebirth.mod, and vendor lists 1502-gamedata.base, 49375-rebirth.mod and
56149-rebirth.mod. The uploaded reference's furniture editing instructions are
not part of this change. The reference and embedded third-party pictures are
not redistributed in the mod.

The old addGoal binding requires a non-null RootObjectBase. Location-only goals
use the character as a temporary carrier and then clear the copied Tasker.subject
hand before setting the location. KenshiLua's Tasker getter uses HandBinding::push
(pushValue<hand>), and the setter copies it back; the character handle is never
nullified. Tests deliberately reject nil subjects and check that location-only
tasks retain no self-target. Native API source: Genpretz/KenshiLua,
src/Bindings/Kenshi/TaskerBinding.cpp and Util/HandBinding.cpp.

The native engine cannot be run here. Mock tests do not establish actual navmesh
movement, dialogue availability, generated stock quality or rare artifact restock.

## alpha.84

`python Development/build_alpha84.py /path/to/alpha83/KenshiShop.mod KenshiShop/KenshiShop.mod`

Removes the scripted duty movement/combat controller. Native FCS routines use
positive weights; urgent finite care tasks keep zero weights. WANDER_TOWN=37,
FOLLOW_SQUADLEADER=141 and PROTECT_ALLIES_STAY_IN_TOWN=288 are checked against
KenshiLua EnumsReference. A native autonomous patrol is not an exact copy of a
mercenary contract. No route confinement guarantee is made without a game test.

NativeNodes uses RootObjectFactory.createLocationNode, not createBuilding.
It registers stable per-building node IDs with Building.addUsageNode. Nodes use
the original post coordinates; physical furniture and layout modules are intact.
LocationNode is only lightuserdata in KenshiLua, so in-engine node selection and
zone unload/reload lifecycle still need validation. No unsupported dereference
or raw memory access is used.

Stock grades are faction-scoped. The custom merchant faction now has persistent
Skeletons/Armour King weights, also synchronized to its runtime Faction.getData.
Original faction 42088-rebirth.mod is read-only. This replaces temporary borrowed
weights that did not cover independent engine refreshes. Default grade weights
0,0,2,80,110,50: https://kenshi.fandom.com/wiki/Armour_King%27s_Shop
Native routine weight semantics: https://kenshi.wiki/ai-goals
Bar vendor IDs and contents come from the supplied offline reference.

Release CI now passes --full-only to tools/package_release.py.
