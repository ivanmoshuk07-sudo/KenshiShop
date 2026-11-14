-- Separate active platoon for chief and patrol; both owned by 400-KenshiShop.mod.
return require('Core.Ownership.Manager').new({
 shop='police',building='105-KenshiShop.mod',
 squads={
  {role='chief',template='310-KenshiShop.mod',faction='400-KenshiShop.mod',count=1,owner=true},
  {role='patrol',template='311-KenshiShop.mod',faction='400-KenshiShop.mod',count=3,owner=false},
 },
},function(line)
 local ok,registry=pcall(require,'Core.Ownership.Registry')
 if ok and registry.record then registry.record(line) end
end)
