-- KenshiShop 0.3.0-alpha.11 — full furnishing on NEW construction.
-- All furniture is placed in one bounded construction event per building.
-- Use a separate test save; native Kenshi behavior is not verified.
return {
    mode = 'full', -- 'full' = 346 physical items across all six buildings; 'disabled' = no furniture
    -- A diagnostic probe mode remains available manually, but is NOT enabled.
    probes = {
        ['100-KenshiShop.mod'] = {1},
        ['101-KenshiShop.mod'] = {1},
        ['102-KenshiShop.mod'] = {1},
        ['103-KenshiShop.mod'] = {1},
        ['104-KenshiShop.mod'] = {1},
        ['105-KenshiShop.mod'] = {1},
    },
}
