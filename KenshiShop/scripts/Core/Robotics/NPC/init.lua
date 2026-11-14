-- Independent queue and NPC state for Robotics; one trader-led squad, plus patrol for Bar.
local queue=require('Core.NPC.Scheduler')
return queue.new('robotics',{

 {name='trader',driver=require('Core.Robotics.NPC.Skeleton')},
})
