-- Alpha.39: the 3-member patrol now spawns only with Police station.
-- Keep existing bar trader untouched. No automatic removal/teleport of legacy saved squads.
local queue=require('Core.NPC.Scheduler')
return queue.new('bar',{
 {name='trader',driver=require('Core.Bar.NPC.Trader')},
 {name='guard',driver=require('Core.Bar.NPC.Guard')},
})
