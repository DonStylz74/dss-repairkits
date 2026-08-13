![Awesome ReadME](https://imgur.com/tWs4iCZ.png)



# DSS Repairkits

A configurable FiveM vehicle repair and cleaning system built for ESX Legacy using ox_lib, ox_target, and ox_inventory.

DSS Repair Kits provides multiple specialised vehicle repair items, skill checks, repair animations, configurable job restrictions, cooldowns, vehicle-class restrictions, targeted vehicle-part interactions, configurable repair percentages, failed-minigame item-loss chances, logging, and a multi-stage Full Repair Kit sequence.

# **FEATURES**

| Feature | DSS Repairkit |
| --- | --- |
| ESX Legacy support | ✅ |
| ox_inventory usable items | ✅ |
| ox_target | ✅ |
| ox_lib skill checks | ✅ |
| ox_lib progress bars | ✅ |
| ox_lib notifications | ✅ |
| Configurable repair percentages | ✅ |
| Configurable repair durations | ✅ |
| Configurable skill-check difficulty | ✅ |
| Configurable cooldowns | ✅ |
| Configurable job and minimum-grade restrictions | ✅ |
| Configurable vehicle-class restrictions | ✅ |
| Configurable chance to lose a kits | ✅ |
| Per-kit server-side validation | ✅ |
| Repair animations and attached repair props | ✅ |
| Bone-based targeting for wheels, body panels, engine areas and trunk areas | ✅ |
| Dedicated vehicle cleaning kit | ✅ |
| Multi-stage Full Repair Kit sequence | ✅ |
| Individual tyre repairs | ✅ |
| Body-only repairs | ✅ |
| Engine-only repairs | ✅ |
| Configurable logging | ✅ |
| Server-side inventory validation and item removal | ✅ |
| Admin cooldown reset command | ✅ |
| Support for multi-axle tyre indexes used by some vehicles | ✅ |

[📱 Visit this Project](https://github.com/DonStylz74)



## Getting Started

| Kit type | Repair/Cleaning Effect |
| --- | --- |
| cleaning_kit | Removes vehicle dirt |
| tire_kit | Repairs one targeted or nearest damaged tyre |
| body_kit | Repairs body health only |
| engine_kit | Repairs engine health only |
| full_kit | Repairs body, engine, all damaged tyres and fully cleans vehicle |

| Full kit stage | Action |
| --- | --- |
| 1 | Tyre repair function |
| 2 | Body repair function |
| 3 | Engine repair function |
| 4 | Vehicle cleaning function |
| Final | Complete vehicle repair is applied |

The resource includes an admin command:

- /repair_clearcd

It clears the repair-kit cooldown table.



## Prerequisites

Before you begin, ensure you have met the following requirements:

- ESX Legacy
- ox_lib
- ox_target
- ox_inventory



### Installation

1. Place the resource in your FiveM resources directory: /resources/dss-repairkits

2. Ensure the required dependencies are installed and started.

3. Add the resource to your server configuration:

- ensure ox_lib
- ensure ox_target
- ensure ox_inventory
- ensure dss_scuba

4. Add the repair kit items to your ox_inventory items configuration.

5. Add repair kit images to your ox_inventory/web/images folder.

Example:

```lua
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
```

6. Configure Repair kits via config.lua file.
7. Restart the resource or server.



## Authors
- **Don Stylz** - [Don_Stylz74](https://github.com/DonStylz74)



## License
Review the LICENSE file included with the resource for the licensing terms that apply to this version.

Because DSS Scuba is derived from an existing project, retain the appropriate original copyright, licence notices and attribution where required.



## License

I've released this project under the [MIT License](LICENSE.md).

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)