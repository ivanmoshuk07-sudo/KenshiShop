-- Per-shop ownership/protection; does not alter construction, spawns or interiors.
return require('Core.Ownership.Manager').new({
 shop='bar',building='100-KenshiShop.mod',
 squads={
 {role='trader',template='300-KenshiShop.mod',faction='400-KenshiShop.mod',count=1,owner=true},
 {role='guard',template='7800-KenshiShop.mod',faction='400-KenshiShop.mod',count=2,owner=false},
 },
},function(line)
 local ok,registry=pcall(require,'Core.Ownership.Registry')
 if ok and registry.record then registry.record(line) end
end)
