local Config=require('Core.Police.Services.Config')
local caretaker=Config.copy(Config.undertaker)
caretaker.owner=true

return require('Core.Ownership.Manager').new({
 shop='crematorium',building=Config.crematorium,squads={caretaker},hasInterior=false,
},function(line)
 local ok,registry=pcall(require,'Core.Ownership.Registry')
 if ok and registry.record then registry.record(line) end
end)
