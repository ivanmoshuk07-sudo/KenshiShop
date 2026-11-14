local M = {}
function M.quat(a,b)
    return {w=a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z,
      x=a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
      y=a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
      z=a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w}
end
function M.world(origin,q,scale,item)
    local norm=math.sqrt(q.w*q.w+q.x*q.x+q.y*q.y+q.z*q.z)
    assert(norm>0,'Invalid building rotation')
    q={w=q.w/norm,x=q.x/norm,y=q.y/norm,z=q.z/norm}
    local v={w=0,x=item.p[1]*scale,y=item.p[2]*scale,z=item.p[3]*scale}
    local p=M.quat(M.quat(q,v),{w=q.w,x=-q.x,y=-q.y,z=-q.z})
    local r=item.q
    return {x=origin.x+p.x,y=origin.y+p.y,z=origin.z+p.z},M.quat(q,{w=r[1],x=r[2],y=r[3],z=r[4]})
end
function M.error(a,b)
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
return M
