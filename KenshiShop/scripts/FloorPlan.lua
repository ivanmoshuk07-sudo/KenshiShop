-- KenshiShop 0.3.0-alpha.18-buildings-only
-- Floor numbers from the CITY BUILDER rule, NOT from height clustering.
-- Each source layout has its own minimum Y. Interior and exterior are separate.
-- This classifies exported furniture; actual in-game floor/roof visibility still needs testing.
local Layouts = require('Layouts')
local M = {}
local HEIGHT_PER_FLOOR = 30.0
local SOURCE_MINIMA = {
    ['100-KenshiShop.mod'] = { inside=139.2688, outside=173.438 },
    ['101-KenshiShop.mod'] = { inside=3.7708, outside=66.2822 },
    ['102-KenshiShop.mod'] = { inside=4.57014036, outside=67.7968826 },
    ['103-KenshiShop.mod'] = { inside=4.60335636, outside=4.64027643 },
    ['104-KenshiShop.mod'] = { inside=4.7134, outside=54.518 },
    ['105-KenshiShop.mod'] = { inside=3.9144, outside=33.9626 },
}
local EXPECTED = {
    ['100-KenshiShop.mod'] = 101,
    ['101-KenshiShop.mod'] = 44,
    ['102-KenshiShop.mod'] = 61,
    ['103-KenshiShop.mod'] = 68,
    ['104-KenshiShop.mod'] = 17,
    ['105-KenshiShop.mod'] = 61,
}
local cached = {}
local summaries = {}

for shop, expected in pairs(EXPECTED) do
    local layout = assert(Layouts[shop], 'Missing shop layout '..shop)
    assert(#layout.objects == expected, 'Unexpected object count '..shop)
    -- Original source height minima are constants.  No NPC marker data is
    -- loaded, created or polled; furniture floor classifications stay identical.
    local sourceMinima = assert(SOURCE_MINIMA[shop], 'Missing source minima '..shop)
    local minInside, minOutside = sourceMinima.inside, sourceMinima.outside
    local assignments = {}
    local summary = {inside = {}, outside = {}, count = #layout.objects}
    for i, item in ipairs(layout.objects) do
        local minY = item.outside and minOutside or minInside
        assert(minY < math.huge, 'Missing source layout minimum Y '..shop)
        local delta = item.p[2] - minY
        assert(delta >= -0.001, 'Invalid source Y '..shop..'/'..i)
        -- CITY BUILDER uses cvttss2si((itemY - minY) / 30): truncate toward zero.
        -- Our delta is nonnegative, so math.floor is equivalent for normal values.
        local floor
        if shop == '102-KenshiShop.mod' or shop == '103-KenshiShop.mod' then
            -- L-House: native 0 = enclosed shop floor, native 1 = OPEN rooftop.
            -- The ~63-Y suspended lamp belongs to floor 0 despite its height;
            -- only physical furnishings at Y >= 70 are placed on the roof.
            -- Exterior shop signs remain independent of indoor floor selection.
            floor = (not item.outside and item.p[2] >= 70) and 1 or 0
        elseif shop == '105-KenshiShop.mod' then
            -- Original Watchtower Police layout has four physical floor bands.
            -- The native Y clusters in interiors.level are 4, 135, 195-210, and 285.
            -- ~75-Y fixtures are mounted on the ground-storey walls.
            local y = item.p[2]
            if y < 105 then floor=0
            elseif y < 165 then floor=1
            elseif y < 250 then floor=2
            else floor=3 end
        else
            floor = math.floor(math.max(0, delta) / HEIGHT_PER_FLOOR)
        end
        assert(floor >= 0 and floor <= 16, 'Unexpected source floor '..shop..'/'..i)
        assignments[i] = {floor = floor, outside = item.outside, sourceY = item.p[2]}
        local bucket = item.outside and summary.outside or summary.inside
        bucket[floor] = (bucket[floor] or 0) + 1
    end
    cached[shop] = assignments
    summaries[shop] = summary
end

function M.forShop(shop) return cached[shop] end
function M.summary(shop) return summaries[shop] end
return M
