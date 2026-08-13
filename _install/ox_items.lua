-- Add these entries inside ox_inventory/data/items.lua
-- consume = 0 is intentional: dss-repairkits handles item removal server-side after successful use,
-- and can optionally remove the item when an ox_lib skill check fails via Config.Kits.*.failRemovePercent.

['cleaning_kit'] = {
    label = 'Vehicle Cleaning Kit',
    weight = 1000,
    stack = true,
    close = true,
    consume = 0,
    description = 'Cleans dirt from a vehicle.',
    client = {
        export = 'dss-repairkits.cleaning_kit'
    }
},

['tire_kit'] = {
    label = 'Tire Repair Kit',
    weight = 1000,
    stack = true,
    close = true,
    consume = 0,
    description = 'Repairs damaged vehicle tyres.',
    client = {
        export = 'dss-repairkits.tire_kit'
    }
},

['body_kit'] = {
    label = 'Body Repair Kit',
    weight = 1500,
    stack = true,
    close = true,
    consume = 0,
    description = 'Repairs vehicle body damage.',
    client = {
        export = 'dss-repairkits.body_kit'
    }
},

['engine_kit'] = {
    label = 'Engine Repair Kit',
    weight = 2000,
    stack = true,
    close = true,
    consume = 0,
    description = 'Repairs vehicle engine damage.',
    client = {
        export = 'dss-repairkits.engine_kit'
    }
},

['full_kit'] = {
    label = 'Full Repair Kit',
    weight = 3000,
    stack = true,
    close = true,
    consume = 0,
    description = 'Performs a complete vehicle repair.',
    client = {
        export = 'dss-repairkits.full_kit'
    }
},
