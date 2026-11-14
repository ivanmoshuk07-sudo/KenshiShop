-- Independent queue and NPC state for Armour; one trader-led squad, plus patrol for Bar.
local queue=require('Core.NPC.Scheduler')
return queue.new('armour',{

 {name='trader',driver=require('Core.Armour.NPC.Trader')},
 {name='guard',driver=require('Core.Armour.NPC.Guard')},
})
