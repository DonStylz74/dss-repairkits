Config = {}

-- Kits configuration
-- item: inventory item name
-- label: display name
-- categories: array of CFX vehicle category index numbers (use numbers from server's vehicle list)
--    Use the CFX category index numbers below when restricting kits to vehicle categories.
--    Vehicle Categories (CFX index numbers):
--      0  - Compacts
--      1  - Sedans
--      2  - SUVs
--      3  - Coupes
--      4  - Muscle
--      5  - Sports Classics
--      6  - Sports
--      7  - Super
--      8  - Motorcycles
--      9  - Off-road
--      10 - Industrial
--      11 - Utility
--      12 - Vans
--      13 - Cycles
--      14 - Boats
--      15 - Helicopters
--      16 - Planes
--      17 - Service
--      18 - Emergency
--      19 - Military
--      20 - Commercial
--      21 - Trains
-- -- anim: {dict, name, flags}
-- skill: ox_lib skillCheck difficulty array
-- duration: repair duration in ms
-- percent: percent of damage/health restored (0-100)
-- jobs: optional array of job rules {name = 'mechanic', minGrade = 2} or empty/nil for everyone
-- cooldown: seconds
-- failRemovePercent: chance (0-100) the kit is removed if the ox_lib skill check is failed
-- validationDistance: optional server-side distance from vehicle centre for this kit; useful for staged/full repairs
-- props: optional props to attach during repair (each can have optional offset/rot override)

Config.Kits = {
  cleaning_kit = {
    item = 'cleaning_kit',
    label = 'Vehicle Cleaning Kit',
    categories = {},
    anim = {dict = 'timetable@floyd@clean_kitchen@base', name = 'base', flags = 33},
    skill = {'easy', 'easy'},
    duration = 10000,
    percent = 100, -- removes this percentage of the vehicle's current dirt
    jobs = nil,
    cooldown = 20,
    failRemovePercent = 0, -- chance item is removed when the skill check is failed
    props = { {model = 'sf_prop_sf_cleaning_pad_01a' } }
  },
  tire_kit = {
    item = 'tire_kit',
    label = 'Tire Repair Kit',
    categories = {}, -- {} all categories or {replace with your server indexes 1,2,3,9}
    anim = {dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', name = 'machinic_loop_mechandplayer', flags = 33},
    skill = {'easy', 'medium', 'easy'},
    duration = 9000,
    percent = 100, -- repair %
    jobs = nil, -- nil :available to everyone or jobs = { {name = 'mechanic', minGrade = 0}, {name = 'tow', minGrade = 2} }
    cooldown = 20,
    failRemovePercent = 0, -- chance item is removed when the skill check is failed
    props = { {model = 'prop_wrench_01'} }
  },
  body_kit = {
    item = 'body_kit',
    label = 'Body Repair Kit',
    categories = {}, -- empty means all categories
    anim = {dict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', name = 'weed_stand_checkingleaves_kneeling_01_inspectorfemale', flags = 33},
    skill = {'easy', 'medium', 'medium'},
    duration = 13000,
    percent = 60,
    jobs = nil,
    cooldown = 30,
    failRemovePercent = 0, -- chance item is removed when the skill check is failed
    props = { {model = 'prop_wrench_01'} }
  },
  engine_kit = {
    item = 'engine_kit',
    label = 'Engine Repair Kit',
    categories = {},
    anim = {dict = 'mini@repair', name = 'fixing_a_ped', flags = 33},
    skill = {'medium', 'medium', 'medium'},
    duration = 17000,
    percent = 100,
    jobs = { {name = 'mechanic', minGrade = 0}, {name = 'tow', minGrade = 2} },
    cooldown = 300,
    failRemovePercent = 0, -- chance item is removed when the skill check is failed
    props = { {model = 'prop_wrench_01'} }
  },
  full_kit = {
    item = 'full_kit',
    label = 'Full Repair Kit',
    categories = {},
    skill = {'medium', 'medium','hard'},
    duration = 40000,
    percent = 100,
    jobs = { {name = 'mechanic', minGrade = 1} },
    cooldown = 45,
    failRemovePercent = 0, -- chance item is removed when the skill check is failed
    validationDistance = 4.5 -- staged repair finishes at trunk; measured from vehicle centre server-side
  }
}


-- Full Repair Kit staged animation/process settings.
-- The Full Kit's total Config.Kits.full_kit.duration is split across these four stages.
-- These stages are visual/process only; after all four complete, the normal Full Kit
-- repair is applied to the complete vehicle.
Config.FullKitSequence = {
  moveSpeed = 1.0,
  moveTimeout = 9000,
  stopDistance = 0.85,
  moveFallbackDistance = 1.6,

  -- After walking close to each work area, align the player to the exact X/Y position
  -- and heading before the animation starts. Disable only if another movement resource
  -- conflicts with SetEntityCoordsNoOffset.
  preciseAlignment = true,

  tire = {
    label = 'Repairing tires',
    anim = {dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', name = 'machinic_loop_mechandplayer', flags = 33},
    props = { {model = 'prop_wrench_01'} },

    -- Fine tuning from in-game testing/screenshots.
    -- standOffset: lateral distance outside the wheel.
    -- forwardBias: shifts the player slightly toward the front of the vehicle.
    standOffset = 0.60,
    forwardBias = 0.15
  },

  body = {
    label = 'Repairing vehicle body',
    anim = {dict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', name = 'weed_stand_checkingleaves_kneeling_01_inspectorfemale', flags = 33},
    props = { {model = 'prop_wrench_01'} },

    -- Body stage is forced to the opposite side from the tire stage.
    -- Distance outside the body panel and front/back shift along the vehicle.
    sideOffset = 0.62,
    longitudinalBias = 0.00
  },

  engine = {
    label = 'Repairing engine',
    anim = {dict = 'mini@repair', name = 'fixing_a_ped', flags = 33},
    props = { {model = 'prop_wrench_01'} },

    -- Pulls the player closer to the bonnet and keeps them centred on the engine bay.
    frontOffset = 0.42,
    lateralBias = 0.00,
    faceDepth = 0.30
  },

  cleaning = {
    label = 'Cleaning vehicle',
    anim = {dict = 'timetable@floyd@clean_kitchen@base', name = 'base', flags = 33},
    props = { {model = 'sf_prop_sf_cleaning_pad_01a'} },

    -- Rear/trunk work position for the final Full Kit cleaning stage.
    -- Further fine-tuned from screenshots to bring the player closer to the
    -- trunk while keeping enough space for the animation to play cleanly.
    rearOffset = 0.06,
    lateralBias = 0.00,
    faceDepth = 0.65
  }
}


-- Target zones mapping - bones and detection radiuses
-- Use precise vehicle bone names (common names provided). Each zone has bone name(s) and a hit radius.
-- wheels: common wheel bone names. If a vehicle is missing wheel entity, we still attempt to detect by proximity to wheel bone coords.
-- panels: body bones that indicate body damage area
-- engine: engine/bonnet area (bones differ by model; check your vehicle models if necessary)
-- vehicle: full vehicle repair (no specific bones)

Config.TargetZones = {
  wheels = {
    bones = {
      'wheel_lf', 'wheel_rf', 'wheel_lm1', 'wheel_rm1', 'wheel_lm2', 'wheel_rm2',
      'wheel_lm3', 'wheel_rm3', 'wheel_lr', 'wheel_rr', 'wheel_rear', 'wheel_front'
    },
    radius = 0.9,
    type = 'tire'
  },
  panels = {
    -- Broad body/panel coverage. Engine/bonnet and rear/trunk targeting have their own kit options.
    bones = {
      'chassis', 'chassis_dummy', 'bodyshell',
      'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r',
      'bumper_f', 'bumper_r', 'wing_lf', 'wing_rf',
      'windscreen', 'window_lf', 'window_rf', 'window_lr', 'window_rr',
      'roof'
    },
    radius = 1.2,
    type = 'body'
  },
  engine = {
    bones = {
      'engine', 'bonnet', 'bonnet_1'
    },
    radius = 1.5,
    type = 'engine'
  },
  clean = {
    -- Cleaning kit can be used while targeting normal exterior body panels.
    bones = {
      'chassis', 'chassis_dummy', 'bodyshell',
      'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r',
      'bumper_f', 'bumper_r', 'wing_lf', 'wing_rf',
      'windscreen', 'window_lf', 'window_rf', 'window_lr', 'window_rr',
      'roof', 'bonnet', 'boot'
    },
    radius = 1.2,
    type = 'clean'
  },
  vehicle = {
    -- Full kit is only shown when targeting the trunk/rear area.
    bones = {
      'boot', 'boot_latch', 'bumper_r', 'taillight_l', 'taillight_r'
    },
    radius = 1.5,
    type = 'full'
  }
}


-- How far around the front half of a vehicle the player may stand for engine repairs.
-- 0.35 is a generous front cone; increase toward 1.0 to require the player to be more directly centered at the hood.
Config.EngineFrontDot = 0.35

-- Prop attach offsets (position + rotation) relative to bone/coords when spawning props during repair
-- Default will be used when a prop entry doesn't specify its own offset
-- Offset format: {pos = vector3(x,y,z), rot = vector3(xRot,yRot,zRot)}
Config.DefaultPropOffset = {
  pos = { x = 0.0, y = 0.0, z = 0.0 },
  rot = { x = 0.0, y = 0.0, z = 0.0 }
}

-- Per-prop override examples
Config.PropOffsets = {
  ['prop_wrench_01'] = { pos = { x = 0.05, y = 0.02, z = -0.02 }, rot = { x = 0.0, y = 180.0, z = 90.0 } },
  ['sf_prop_sf_cleaning_pad_01a'] = { pos = { x = 0.16, y = 0.00, z = 0.00 }, rot = { x = 0.0, y = 0.0, z = 0.0 } },
}

-- Logging settings
-- Enabled: master logging switch
-- Console: print repair log entries to the server console
-- File: append repair log entries to a resource-local log file
Config.Logging = {
  Enabled = false,
  Console = false,
  File = false,
  FileName = 'repair_kits_log.txt'
}

-- Max distance to vehicle when validating server-side
Config.MaxRepairDistance = 2.5

-- Default cooldown (if kit missing) in seconds
Config.DefaultCooldown = 30

return Config
