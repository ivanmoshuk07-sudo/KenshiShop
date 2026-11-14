-- Independent queue and NPC state for Engineering; one trader-led squad, plus patrol for Bar.
local queue=require('Core.NPC.Scheduler')
return queue.new('engineering',{

 {name='trader',driver=require('Core.Engineering.NPC.Trader')},
 {name='guard',driver=require('Core.Engineering.NPC.Guard')},
})
