-- KenshiShop 0.3.0-alpha.11
-- Native floor number and open-air ROOF are distinct properties.
-- A roof stays linked to the parent building; its outside-furniture flag is
-- applied AFTER creation (do not use the flag to remove its parent link).
local FloorPlan=require('FloorPlan')
local M={}
local MAP={
    ['100-KenshiShop.mod']={[0]=0,[1]=1}, -- bar: upper interior, no roof props
    ['101-KenshiShop.mod']={[0]=0,[2]=1}, -- engineering: upper = roof
    ['102-KenshiShop.mod']={[0]=0,[1]=1}, -- L-House Armory: two physical interior storeys
    ['103-KenshiShop.mod']={[0]=0,[1]=1}, -- L-House Weapon Shop: two physical interior storeys
    ['104-KenshiShop.mod']={[0]=0}, -- robotics: ground only
    ['105-KenshiShop.mod']={[0]=0,[1]=1,[2]=2,[3]=3}, -- authentic Watchtower, four storeys including roof
}
local ROOF_SOURCE={
    ['101-KenshiShop.mod']={[2]=true},
    ['102-KenshiShop.mod']={[1]=true}, -- open L-House roof (not enclosed second floor)
    ['103-KenshiShop.mod']={[1]=true}, -- open L-House roof (not enclosed second floor)
    ['105-KenshiShop.mod']={[3]=true}, -- native Watchtower roof belongs to parent
}
function M.resolve(shop,classification,numFloors)
    assert(type(classification)=='table','Missing source classification')
    local source=assert(classification.floor,'Missing source floor')
    local mapping=assert(MAP[shop],'Unknown shop floor mapping '..tostring(shop))
    local roof=not classification.outside and ROOF_SOURCE[shop] and ROOF_SOURCE[shop][source]==true or false
    local target
    if classification.outside then
        target=source
    else
        target=mapping[source]
        assert(target~=nil,'Unknown source height band '..tostring(shop)..'/'..tostring(source))
        if roof and type(numFloors)=='number' then
            assert(numFloors>=2,'Open roof cannot share a single-floor building')
            target=numFloors-1
        end
    end
    local clamped=false
    if type(numFloors)=='number' and numFloors>=1 and target>=numFloors then
        target=numFloors-1
        clamped=true
    end
    return {source=source,native=target,remapped=(source~=target),
        clamped=clamped,outside=classification.outside,roof=roof}
end
function M.validate()
    local total,roofCount=0,0
    for shop in pairs(MAP) do
        local plan=assert(FloorPlan.forShop(shop),'Missing floor plan '..shop)
        for i,c in ipairs(plan) do
            local a=M.resolve(shop,c,nil)
            assert(a.native>=0 and a.native==math.floor(a.native),'Invalid native floor '..shop..'/'..i)
            total=total+1
            if a.roof then roofCount=roofCount+1 end
        end
    end
    for shop,expected in pairs({
        ['102-KenshiShop.mod']={ground=50,roof=10,exterior=1},
        ['103-KenshiShop.mod']={ground=54,roof=13,exterior=1},
    }) do
        local got={ground=0,roof=0,exterior=0}
        for _,c in ipairs(FloorPlan.forShop(shop)) do
            local a=M.resolve(shop,c,2)
            local zone=a.outside and 'exterior' or (a.roof and 'roof' or 'ground')
            got[zone]=got[zone]+1
        end
        assert(expected and got.ground==expected.ground and got.roof==expected.roof
            and got.exterior==expected.exterior,'L-House floor classification mismatch '..shop)
    end
    assert(total==352,'Expected 352 physical furniture items, got '..total)
    assert(roofCount==36,'Expected 36 rooftop furniture items including L-House shops, got '..roofCount)
    return total,roofCount
end
M.validate()
return M
