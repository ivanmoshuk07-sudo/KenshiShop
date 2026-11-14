-- KenshiShop 0.3.0-alpha.11
-- Open-air roof diagnostics and opt-in migration for already furnished shops.
-- Roof is not a separate building; keep furnitureParentBuilding() linked.
-- Only change isOutsideFurniture on exact source-matched roof objects.
local FloorDiagnostics=require('FloorDiagnostics')
local M={}
function M.collect(parent)
    local a=FloorDiagnostics.collect(parent)
    local roof,wrongFlag,wrongFloor=0,0,0
    local matches={}
    for _,m in ipairs(a.matches) do
        if m.source.roof then
            roof=roof+1
            matches[#matches+1]=m
            if m.candidate.outside~=true then wrongFlag=wrongFlag+1 end
            if m.candidate.floor~=m.source.floor then wrongFloor=wrongFloor+1 end
        end
    end
    return {sid=a.sid,name=a.name,expected=a.expected,matched=a.matched,
        candidates=a.candidates,children=a.children,nodeCandidates=a.nodeCandidates,
        roofExpected=a.roofExpected,
        roofMatched=roof,wrongFlag=wrongFlag,wrongFloor=wrongFloor,matches=matches}
end
function M.audit(parent)
    local a=M.collect(parent)
    local sourceComplete=a.matched==a.expected and a.candidates==a.expected
    return string.format('ROOF_AUDIT READ-ONLY shop=%s expectedFurniture=%d matchedFurniture=%d roofExpected=%d roofMatched=%d wrongOutsideFlag=%d wrongFloor=%d ignoredLegacyMarkers=%d\n%s',
        a.name,a.expected,a.matched,a.roofExpected,a.roofMatched,a.wrongFlag,a.wrongFloor,a.nodeCandidates,
        sourceComplete and 'Read-only audit. No save modification is performed.'
        or 'BLOCKED: furniture matching incomplete. No changes allowed.')
end
return M
