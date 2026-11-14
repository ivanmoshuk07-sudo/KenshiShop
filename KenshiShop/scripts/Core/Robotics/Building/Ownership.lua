-- Per-shop ownership/protection; does not alter construction, spawns or interiors.
return require('Core.Ownership.Manager').new({
 shop='robotics',building='104-KenshiShop.mod',
 squads={
 {role='trader',template='309-KenshiShop.mod',faction='400-KenshiShop.mod',count=1,owner=true},
 },
},function(line)
 local ok,registry=pcall(require,'Core.Ownership.Registry')
 if ok and registry.record then registry.record(line) end
end)
