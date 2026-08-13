local cooldowns = {}
local pending = {}

local function notify(src, description, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Repair Kit',
        description = description,
        type = notifyType or 'inform'
    })
end

local function appendLog(line)
    local logging = Config.Logging
    if not logging or logging.Enabled == false then return end

    local timestamp = os.date('%Y-%m-%d %H:%M:%S')
    local output = ('[%s] %s'):format(timestamp, line)

    if logging.Console ~= false then
        print(output)
    end

    if logging.File ~= false and SaveResourceFile then
        local fileName = logging.FileName or 'repair_kits_log.txt'
        local current = LoadResourceFile(GetCurrentResourceName(), fileName) or ''
        SaveResourceFile(GetCurrentResourceName(), fileName, current .. output .. '\n', -1)
    end
end

local function hasJobAccess(xPlayer, jobs)
    if not jobs or #jobs == 0 then return true end
    if not xPlayer.job then return false end

    local grade = tonumber(xPlayer.job.grade) or 0

    for i = 1, #jobs do
        local rule = jobs[i]
        if xPlayer.job.name == rule.name and grade >= (rule.minGrade or 0) then
            return true
        end
    end

    return false
end

local function hasItem(src, itemName)
    return (exports.ox_inventory:Search(src, 'count', itemName) or 0) > 0
end

local function getValidationDistance(kit)
    -- Server entity coordinates are the vehicle origin/centre, not the exact panel being worked on.
    -- Staged kits can therefore need a larger radius when the player is correctly positioned
    -- at the front/rear of a long vehicle. Individual kits keep the normal global distance.
    return tonumber(kit and kit.validationDistance) or ((Config.MaxRepairDistance or 2.5) + 0.5)
end

local function validateRepairRequest(src, kitName, netId)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false, 'Player not found.' end

    local kit = Config.Kits[kitName]
    if not kit or kit.item ~= kitName then
        return false, 'Invalid repair kit.'
    end

    if not hasJobAccess(xPlayer, kit.jobs) then
        return false, 'You do not have permission to use this repair kit.'
    end

    local key = ('%s:%s'):format(src, kitName)
    local now = os.time()
    local cooldown = kit.cooldown or Config.DefaultCooldown

    if cooldowns[key] and (now - cooldowns[key]) < cooldown then
        local remaining = cooldown - (now - cooldowns[key])
        return false, ('Repair kit is on cooldown for %d more seconds.'):format(remaining)
    end

    if not hasItem(src, kit.item) then
        return false, ('You do not have a %s.'):format(kit.label or kit.item)
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Vehicle not found.'
    end

    local ped = GetPlayerPed(src)
    local pedCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(vehicle)

    if #(pedCoords - vehicleCoords) > getValidationDistance(kit) then
        return false, 'You are too far from the vehicle.'
    end

    return true, nil, xPlayer, kit
end

-- Client preflight. This is called before any skill check/animation/progress bar starts.
lib.callback.register('repairkits:canUse', function(src, kitName, netId)
    local allowed, message = validateRepairRequest(src, kitName, netId)
    return {
        allowed = allowed == true,
        message = message
    }
end)

RegisterNetEvent('repairkits:skillFailed', function(kitName, netId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local kit = Config.Kits[kitName]

    if not xPlayer or not kit or kit.item ~= kitName then
        return
    end

    -- The normal preflight already runs before the minigame. Re-check the important
    -- inventory/job/distance conditions before deciding whether a failed kit is lost.
    if not hasJobAccess(xPlayer, kit.jobs) or not hasItem(src, kit.item) then
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair failed.')
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair failed.')
        return
    end

    local ped = GetPlayerPed(src)
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > getValidationDistance(kit) then
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair failed.')
        return
    end

    local removalChance = math.max(0, math.min(100, tonumber(kit.failRemovePercent) or 0))
    local removed = false

    if removalChance > 0 and math.random(1, 100) <= removalChance then
        removed = exports.ox_inventory:RemoveItem(src, kit.item, 1) == true
    end

    if removed then
        appendLog(('PLAYER %s (%s) failed %s minigame; kit removed (chance=%s%%)')
            :format(src, xPlayer.identifier or 'unknown', kitName, removalChance))
        TriggerClientEvent('repairkits:serverResult', src, false,
            ('Repair failed. The %s was damaged and removed.'):format(kit.label or kit.item))
    else
        appendLog(('PLAYER %s (%s) failed %s minigame; kit retained (chance=%s%%)')
            :format(src, xPlayer.identifier or 'unknown', kitName, removalChance))
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair failed. The kit was not consumed.')
    end
end)

RegisterNetEvent('repairkits:requestRepair', function(kitName, netId, zoneType, tyreIndex)
    local src = source
    local allowed, message, xPlayer, kit = validateRepairRequest(src, kitName, netId)

    if zoneType == 'tire' then
        local validTyreIndices = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [45] = true, [47] = true }
        tyreIndex = tonumber(tyreIndex)
        if not validTyreIndices[tyreIndex] then
            TriggerClientEvent('repairkits:serverResult', src, false, 'Unable to identify the selected tyre.')
            return
        end
    end

    if not allowed then
        TriggerClientEvent('repairkits:serverResult', src, false, message or 'Repair validation failed.')
        return
    end

    pending[src] = {
        kitName = kitName,
        netId = netId,
        zoneType = zoneType,
        tyreIndex = tyreIndex,
        expires = os.time() + 10
    }

    TriggerClientEvent('repairkits:applyRepair', src, netId, kitName, zoneType, kit.percent or 100, tyreIndex)
end)

RegisterNetEvent('repairkits:repairApplied', function(success, kitName, netId, zoneType, applied)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    local request = pending[src]
    pending[src] = nil

    if not xPlayer or not request then return end

    if request.expires < os.time()
        or request.kitName ~= kitName
        or request.netId ~= netId
        or request.zoneType ~= zoneType then
        appendLog(('REJECTED invalid repair response from player %s'):format(src))
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair validation failed.')
        return
    end

    local kit = Config.Kits[kitName]
    if not kit then return end

    if not success then
        if zoneType == 'tire' then
            TriggerClientEvent('repairkits:serverResult', src, false, 'No damaged tyres were found.')
        elseif zoneType == 'body' then
            TriggerClientEvent('repairkits:serverResult', src, false, 'No body damage was found.')
        elseif zoneType == 'engine' then
            TriggerClientEvent('repairkits:serverResult', src, false, 'No engine damage was found.')
        elseif zoneType == 'clean' then
            TriggerClientEvent('repairkits:serverResult', src, false, 'The vehicle is already clean.')
        else
            TriggerClientEvent('repairkits:serverResult', src, false, 'Repair could not be applied.')
        end
        return
    end

    if not hasItem(src, kit.item) then
        TriggerClientEvent('repairkits:serverResult', src, false, 'Repair kit is no longer in your inventory.')
        return
    end

    local removed = exports.ox_inventory:RemoveItem(src, kit.item, 1)
    if not removed then
        TriggerClientEvent('repairkits:serverResult', src, false, 'Unable to remove the repair kit from your inventory.')
        return
    end

    cooldowns[('%s:%s'):format(src, kitName)] = os.time()

    appendLog(('PLAYER %s (%s) used %s on vehicle %s zone=%s applied=%s')
        :format(src, xPlayer.identifier or 'unknown', kitName, netId, zoneType, table.concat(applied or {}, ',')))

    TriggerClientEvent('repairkits:serverResult', src, true, zoneType == 'clean' and 'Vehicle cleaned successfully.' or 'Repair successful.')
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)

ESX.RegisterCommand('repair_clearcd', 'admin', function(xPlayer)
    cooldowns = {}
    xPlayer.showNotification('Repair cooldowns cleared', 'success')
end, true, { help = 'Clear repair kit cooldowns' })
