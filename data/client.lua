local Kits = Config.Kits
local busy = false

local kitZones = {
    tire_kit = 'tire',
    body_kit = 'body',
    engine_kit = 'engine',
    cleaning_kit = 'clean',
    full_kit = 'full'
}

local function notify(description, notifyType)
    lib.notify({
        title = 'Repair Kit',
        description = description,
        type = notifyType or 'inform'
    })
end

local function getClosestVehicle(maxDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = lib.getClosestVehicle(coords, maxDistance or Config.MaxRepairDistance, false)

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        return vehicle
    end
end

local function categoryAllowed(vehicle, kit)
    if not kit.categories or #kit.categories == 0 then return true end

    local class = GetVehicleClass(vehicle)
    for i = 1, #kit.categories do
        if kit.categories[i] == class then
            return true
        end
    end

    return false
end

local function isPlayerInFrontOfVehicle(vehicle)
    local pedCoords = GetEntityCoords(PlayerPedId())
    local vehicleCoords = GetEntityCoords(vehicle)
    local forward = GetEntityForwardVector(vehicle)
    local dx = pedCoords.x - vehicleCoords.x
    local dy = pedCoords.y - vehicleCoords.y
    local length = math.sqrt((dx * dx) + (dy * dy))

    if length < 0.01 then return false end

    -- Positive dot product means the player is on the forward/bonnet side.
    local dot = ((dx / length) * forward.x) + ((dy / length) * forward.y)
    return dot >= (Config.EngineFrontDot or 0.35)
end

local function requestControl(entity, timeoutMs)
    if NetworkHasControlOfEntity(entity) then return true end

    NetworkRequestControlOfEntity(entity)
    local timeout = GetGameTimer() + (timeoutMs or 1500)

    while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end

    return NetworkHasControlOfEntity(entity)
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > timeout then return false end
        Wait(10)
    end

    return true
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end

    RequestModel(hash)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then return nil end
        Wait(10)
    end

    return hash
end

local function createRepairProp(ped, propData)
    local model = type(propData) == 'table' and propData.model or propData
    if not model then return nil end

    local hash = loadModel(model)
    if not hash then return nil end

    local offset = (type(propData) == 'table' and propData.offset)
        or Config.PropOffsets[model]
        or Config.DefaultPropOffset

    local pos = offset.pos or { x = 0.0, y = 0.0, z = 0.0 }
    local rot = offset.rot or { x = 0.0, y = 0.0, z = 0.0 }
    local bone = GetPedBoneIndex(ped, 57005)

    local obj = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(
        obj, ped, bone,
        pos.x or 0.0, pos.y or 0.0, pos.z or 0.0,
        rot.x or 0.0, rot.y or 0.0, rot.z or 0.0,
        true, true, false, true, 1, true
    )

    SetModelAsNoLongerNeeded(hash)
    return obj
end

local cleanupRepair

local function getVehicleDimensions(vehicle)
    local minDim, maxDim = GetModelDimensions(GetEntityModel(vehicle))
    return minDim, maxDim
end

local function getVehicleLocalXY(vehicle, worldCoords)
    local vehicleCoords = GetEntityCoords(vehicle)
    local rightPoint = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0)
    local forwardPoint = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, 1.0, 0.0)

    local rightX = rightPoint.x - vehicleCoords.x
    local rightY = rightPoint.y - vehicleCoords.y
    local forwardX = forwardPoint.x - vehicleCoords.x
    local forwardY = forwardPoint.y - vehicleCoords.y

    local dx = worldCoords.x - vehicleCoords.x
    local dy = worldCoords.y - vehicleCoords.y

    return (dx * rightX) + (dy * rightY), (dx * forwardX) + (dy * forwardY)
end


-- GTA tyre indices do not always match the visual wheel-bone order. Keep the
-- bone-to-tyre mapping explicit so the dedicated Tyre Kit repairs only the
-- wheel the player is actually targeting/standing beside.
local tyreBoneMap = {
    { bone = 'wheel_lf',    index = 0 },
    { bone = 'wheel_rf',    index = 1 },
    { bone = 'wheel_lm1',   index = 2 },
    { bone = 'wheel_rm1',   index = 3 },
    { bone = 'wheel_lr',    index = 4 },
    { bone = 'wheel_rr',    index = 5 },
    { bone = 'wheel_lm2',   index = 45 },
    { bone = 'wheel_rm2',   index = 47 },
    { bone = 'wheel_front', index = 0 }, -- bikes / special vehicles
    { bone = 'wheel_rear',  index = 4 }, -- bikes / special vehicles
}

local function getClosestTyreIndex(vehicle, referenceCoords)
    referenceCoords = referenceCoords or GetEntityCoords(PlayerPedId())

    local bestIndex, bestDistance

    for i = 1, #tyreBoneMap do
        local entry = tyreBoneMap[i]
        local boneIndex = GetEntityBoneIndexByName(vehicle, entry.bone)

        if boneIndex ~= -1 then
            local wheelCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local distance = #(referenceCoords - wheelCoords)

            if not bestDistance or distance < bestDistance then
                bestDistance = distance
                bestIndex = entry.index
            end
        end
    end

    return bestIndex
end

local function getClosestWheelRepairPoint(vehicle)
    local pedCoords = GetEntityCoords(PlayerPedId())
    local wheelBones = (Config.TargetZones.wheels and Config.TargetZones.wheels.bones) or {}
    local sequence = Config.FullKitSequence or {}
    local tireConfig = sequence.tire or {}
    local standOffset = tireConfig.standOffset or sequence.wheelStandOffset or 0.6
    local forwardBias = tireConfig.forwardBias or 0.15
    local bestPoint, bestDistance

    for i = 1, #wheelBones do
        local boneIndex = GetEntityBoneIndexByName(vehicle, wheelBones[i])
        if boneIndex ~= -1 then
            local wheelCoords = GetWorldPositionOfEntityBone(vehicle, boneIndex)
            local localX, localY = getVehicleLocalXY(vehicle, wheelCoords)
            local sideSign = localX >= 0.0 and 1.0 or -1.0

            -- Offset laterally away from the vehicle rather than radially away from its centre.
            -- This keeps the player alongside the wheel instead of pushing rear-wheel repairs
            -- toward the bumper/trunk area.
            local standCoords = GetOffsetFromEntityInWorldCoords(
                vehicle,
                localX + (sideSign * standOffset),
                localY + forwardBias,
                0.0
            )

            local distance = #(pedCoords - standCoords)
            if not bestDistance or distance < bestDistance then
                bestPoint = {
                    standCoords = standCoords,
                    faceCoords = wheelCoords,
                    bone = wheelBones[i],
                    sideSign = sideSign
                }
                bestDistance = distance
            end
        end
    end

    if bestPoint then
        return bestPoint
    end

    -- Fallback for unusual vehicles without the standard wheel bones.
    local minDim, maxDim = getVehicleDimensions(vehicle)
    local sideSign = 1.0
    local fallbackY = minDim.y * 0.45
    local fallbackWheel = GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x, fallbackY, 0.0)
    return {
        standCoords = GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x + (standOffset * sideSign), fallbackY + forwardBias, 0.0),
        faceCoords = fallbackWheel,
        bone = 'fallback',
        sideSign = sideSign
    }
end

local function getSideRepairPoint(vehicle, requestedSideSign)
    local pedCoords = GetEntityCoords(PlayerPedId())
    local minDim, maxDim = getVehicleDimensions(vehicle)
    local sequence = Config.FullKitSequence or {}
    local bodyConfig = sequence.body or {}
    local sideOffset = bodyConfig.sideOffset or 0.62
    local longitudinalBias = bodyConfig.longitudinalBias or 0.0

    local leftStand = GetOffsetFromEntityInWorldCoords(vehicle, minDim.x - sideOffset, longitudinalBias, 0.0)
    local rightStand = GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x + sideOffset, longitudinalBias, 0.0)

    if requestedSideSign and requestedSideSign < 0 then
        return {
            standCoords = leftStand,
            faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, minDim.x, longitudinalBias, 0.0),
            sideSign = -1.0
        }
    elseif requestedSideSign and requestedSideSign > 0 then
        return {
            standCoords = rightStand,
            faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x, longitudinalBias, 0.0),
            sideSign = 1.0
        }
    end

    if #(pedCoords - leftStand) <= #(pedCoords - rightStand) then
        return {
            standCoords = leftStand,
            faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, minDim.x, longitudinalBias, 0.0),
            sideSign = -1.0
        }
    end

    return {
        standCoords = rightStand,
        faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, maxDim.x, longitudinalBias, 0.0),
        sideSign = 1.0
    }
end

local function getRearRepairPoint(vehicle)
    local minDim, maxDim = getVehicleDimensions(vehicle)
    local sequence = Config.FullKitSequence or {}
    local cleaningConfig = sequence.cleaning or {}
    local rearOffset = cleaningConfig.rearOffset or 0.55
    local lateralBias = cleaningConfig.lateralBias or 0.0
    local faceDepth = cleaningConfig.faceDepth or 0.30

    return {
        standCoords = GetOffsetFromEntityInWorldCoords(vehicle, lateralBias, minDim.y - rearOffset, 0.0),
        faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, lateralBias, math.min(maxDim.y, minDim.y + faceDepth), 0.0)
    }
end

local function getFrontRepairPoint(vehicle)
    local minDim, maxDim = getVehicleDimensions(vehicle)
    local sequence = Config.FullKitSequence or {}
    local engineConfig = sequence.engine or {}
    local frontOffset = engineConfig.frontOffset or 0.42
    local lateralBias = engineConfig.lateralBias or 0.0
    local faceDepth = engineConfig.faceDepth or 0.30

    return {
        standCoords = GetOffsetFromEntityInWorldCoords(vehicle, lateralBias, maxDim.y + frontOffset, 0.0),
        faceCoords = GetOffsetFromEntityInWorldCoords(vehicle, lateralBias, math.max(minDim.y, maxDim.y - faceDepth), 0.0)
    }
end

local function faceWorldCoord(ped, coords, duration)
    local pedCoords = GetEntityCoords(ped)
    local heading = GetHeadingFromVector_2d(coords.x - pedCoords.x, coords.y - pedCoords.y)
    TaskAchieveHeading(ped, heading, duration or 500)

    local timeout = GetGameTimer() + (duration or 500) + 150
    while GetGameTimer() < timeout do
        Wait(25)
    end

    SetEntityHeading(ped, heading)
end

local function alignPedToRepairPoint(ped, standCoords, faceCoords)
    local sequence = Config.FullKitSequence or {}
    if sequence.preciseAlignment == false then
        if faceCoords then faceWorldCoord(ped, faceCoords, 450) end
        return
    end

    -- Let navmesh handle the natural walk, then align only X/Y to the exact work point.
    -- Keeping the ped's current Z avoids floating/sinking on ramps, interiors and uneven floors.
    local current = GetEntityCoords(ped)
    SetEntityCoordsNoOffset(ped, standCoords.x, standCoords.y, current.z, false, false, false)
    Wait(50)

    if faceCoords then
        local heading = GetHeadingFromVector_2d(faceCoords.x - standCoords.x, faceCoords.y - standCoords.y)
        SetEntityHeading(ped, heading)
        Wait(100)
    end
end

local function walkToRepairPoint(ped, vehicle, coords, faceCoords)
    local sequence = Config.FullKitSequence or {}
    local stopDistance = sequence.stopDistance or 0.85
    local fallbackDistance = sequence.moveFallbackDistance or 1.6
    local timeout = GetGameTimer() + (sequence.moveTimeout or 9000)

    TaskFollowNavMeshToCoord(ped, coords.x, coords.y, coords.z, sequence.moveSpeed or 1.0, -1, stopDistance, 0, 0.0)

    while GetGameTimer() < timeout do
        if #(GetEntityCoords(ped) - coords) <= stopDistance then
            ClearPedTasks(ped)
            alignPedToRepairPoint(ped, coords, faceCoords)
            return true
        end
        Wait(100)
    end

    ClearPedTasks(ped)

    -- GTA pathing may stop slightly short around bumpers/wheels. If the ped reached the
    -- work area, accept the pathing result and use the precise alignment pass to finish.
    if #(GetEntityCoords(ped) - coords) <= fallbackDistance then
        alignPedToRepairPoint(ped, coords, faceCoords)
        return true
    end

    return false
end

local function runSequenceStage(ped, vehicle, stage, duration, openHood)
    local anim = stage.anim or { dict = 'mini@repair', name = 'fixing_a_player', flags = 49 }
    local props = {}
    local hoodVehicle = nil

    if openHood then
        requestControl(vehicle, 1000)
        SetVehicleDoorOpen(vehicle, 4, false, false)
        hoodVehicle = vehicle
        Wait(350)
    end

    if not loadAnimDict(anim.dict) then
        cleanupRepair(ped, props, hoodVehicle)
        return false, 'Unable to load the repair animation.'
    end

    if stage.props then
        for i = 1, #stage.props do
            local obj = createRepairProp(ped, stage.props[i])
            if obj then props[#props + 1] = obj end
        end
    end

    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, anim.flags or 49, 0.0, false, false, false)

    local completed = lib.progressBar({
        duration = duration,
        label = stage.label or 'Repairing vehicle',
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true }
    })

    cleanupRepair(ped, props, hoodVehicle)
    if not completed then
        return false, 'Full repair cancelled.'
    end

    return true
end

local function runFullRepairSequence(ped, vehicle, kit)
    local sequence = Config.FullKitSequence or {}
    local totalDuration = kit.duration or 16000
    local tireDuration = math.max(1000, math.floor(totalDuration / 4))
    local bodyDuration = math.max(1000, math.floor(totalDuration / 4))
    local engineDuration = math.max(1000, math.floor(totalDuration / 4))
    local cleaningDuration = math.max(1000, totalDuration - tireDuration - bodyDuration - engineDuration)

    local tireStage = sequence.tire or {}
    local bodyStage = sequence.body or {}
    local engineStage = sequence.engine or {}
    local cleaningStage = sequence.cleaning or {}

    local wheelPoint = getClosestWheelRepairPoint(vehicle)
    if not walkToRepairPoint(ped, vehicle, wheelPoint.standCoords, wheelPoint.faceCoords) then
        return false, 'Unable to reach a tire on the vehicle.'
    end
    local ok, message = runSequenceStage(ped, vehicle, tireStage, tireDuration, false)
    if not ok then return false, message end

    -- Always cross to the opposite side of the vehicle for the body stage.
    local tireSideSign = wheelPoint.sideSign or 1.0
    local bodyPoint = getSideRepairPoint(vehicle, -tireSideSign)
    if not walkToRepairPoint(ped, vehicle, bodyPoint.standCoords, bodyPoint.faceCoords) then
        return false, 'Unable to reach the opposite side of the vehicle.'
    end
    ok, message = runSequenceStage(ped, vehicle, bodyStage, bodyDuration, false)
    if not ok then return false, message end

    local enginePoint = getFrontRepairPoint(vehicle)
    if not walkToRepairPoint(ped, vehicle, enginePoint.standCoords, enginePoint.faceCoords) then
        return false, 'Unable to reach the front of the vehicle.'
    end
    ok, message = runSequenceStage(ped, vehicle, engineStage, engineDuration, true)
    if not ok then return false, message end

    -- Final Full Kit process stage: walk to the rear/trunk and clean the vehicle.
    local cleaningPoint = getRearRepairPoint(vehicle)
    if not walkToRepairPoint(ped, vehicle, cleaningPoint.standCoords, cleaningPoint.faceCoords) then
        return false, 'Unable to reach the rear of the vehicle.'
    end
    ok, message = runSequenceStage(ped, vehicle, cleaningStage, cleaningDuration, false)
    if not ok then return false, message end

    return true
end

cleanupRepair = function(ped, props, hoodVehicle)
    ClearPedTasks(ped)

    for i = 1, #props do
        local obj = props[i]
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end

    if hoodVehicle and DoesEntityExist(hoodVehicle) then
        requestControl(hoodVehicle, 750)
        SetVehicleDoorShut(hoodVehicle, 4, false)
    end
end

local function preflightRepair(kitName, vehicle)
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if not netId or netId == 0 then
        return false, 'Unable to identify the vehicle.'
    end

    local result = lib.callback.await('repairkits:canUse', false, kitName, netId)
    if not result or result.allowed ~= true then
        return false, (result and result.message) or 'You cannot use this repair kit right now.'
    end

    return true, nil, netId
end

local function runRepair(kitName, vehicle, zoneType, fromTarget, tyreIndex)
    if busy then
        notify('You are already repairing a vehicle.', 'error')
        return
    end

    local kit = Kits[kitName]
    if not kit then
        notify('Invalid repair kit.', 'error')
        return
    end

    vehicle = vehicle or getClosestVehicle(Config.MaxRepairDistance)
    if not vehicle then
        notify('No vehicle is close enough to repair.', 'error')
        return
    end

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        notify('Exit the vehicle before using a repair kit.', 'error')
        return
    end

    if not categoryAllowed(vehicle, kit) then
        notify('This repair kit cannot be used on this type of vehicle.', 'error')
        return
    end

    zoneType = zoneType or kitZones[kitName] or 'full'

    -- Dedicated tyre kits operate on one wheel only. When the item is used from
    -- inventory there is no target hit coordinate, so use the wheel nearest to
    -- the player. ox_target supplies a more precise wheel via its hit coords.
    if zoneType == 'tire' and kitName == 'tire_kit' and tyreIndex == nil then
        tyreIndex = getClosestTyreIndex(vehicle, GetEntityCoords(ped))
        if tyreIndex == nil then
            notify('Unable to identify a tyre to repair.', 'error')
            return
        end
    end

    if zoneType == 'tire' and kitName == 'tire_kit' then
        if not (IsVehicleTyreBurst(vehicle, tyreIndex, false) or IsVehicleTyreBurst(vehicle, tyreIndex, true)) then
            notify('The selected tyre is not damaged.', 'error')
            return
        end
    end

    if zoneType == 'engine' and not isPlayerInFrontOfVehicle(vehicle) then
        notify('You must be standing in front of the vehicle to repair the engine.', 'error')
        return
    end

    if zoneType == 'clean' and GetVehicleDirtLevel(vehicle) <= 0.01 then
        notify('The vehicle is already clean.', 'error')
        return
    end

    -- Validate job/item/cooldown/distance before starting any minigame, animation, prop, or progress bar.
    local allowed, message, netId = preflightRepair(kitName, vehicle)
    if not allowed then
        notify(message, 'error')
        return
    end

    busy = true

    -- When launched from ox_target, runRepair is started in its own thread. This short yield
    -- ensures the target NUI callback has fully released focus before ox_lib opens skillCheck.
    if fromTarget then Wait(150) end

    if kitName == 'full_kit' then
        local passed = lib.skillCheck(kit.skill or { 'medium' })
        if not passed then
            TriggerServerEvent('repairkits:skillFailed', kitName, netId)
            busy = false
            return
        end

        local completed, sequenceMessage = runFullRepairSequence(ped, vehicle, kit)
        if not completed then
            busy = false
            notify(sequenceMessage or 'Full repair cancelled.', 'error')
            return
        end

        if not DoesEntityExist(vehicle) then
            busy = false
            notify('Vehicle is no longer available.', 'error')
            return
        end

        TriggerServerEvent('repairkits:requestRepair', kitName, netId, 'full')
        return
    end

    local anim = kit.anim or { dict = 'mini@repair', name = 'fixing_a_player', flags = 49 }
    local props = {}
    local hoodVehicle = nil

    if zoneType == 'engine' then
        requestControl(vehicle, 1000)
        TaskTurnPedToFaceEntity(ped, vehicle, 650)
        Wait(650)
        SetVehicleDoorOpen(vehicle, 4, false, false)
        hoodVehicle = vehicle
        Wait(400)
    end

    if not loadAnimDict(anim.dict) then
        cleanupRepair(ped, props, hoodVehicle)
        busy = false
        notify('Unable to load the repair animation.', 'error')
        return
    end

    if kit.props then
        for i = 1, #kit.props do
            local obj = createRepairProp(ped, kit.props[i])
            if obj then props[#props + 1] = obj end
        end
    end

    local passed = lib.skillCheck(kit.skill or { 'easy' })
    if not passed then
        cleanupRepair(ped, props, hoodVehicle)
        TriggerServerEvent('repairkits:skillFailed', kitName, netId)
        busy = false
        return
    end

    TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, anim.flags or 49, 0.0, false, false, false)

    local completed = lib.progressBar({
        duration = kit.duration or 8000,
        label = ('Using %s'):format(kit.label or kitName),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    cleanupRepair(ped, props, hoodVehicle)

    if not completed then
        busy = false
        notify('Repair cancelled.', 'error')
        return
    end

    -- Re-check the vehicle still exists after the animation/progress sequence.
    if not DoesEntityExist(vehicle) then
        busy = false
        notify('Vehicle is no longer available.', 'error')
        return
    end

    TriggerServerEvent('repairkits:requestRepair', kitName, netId, zoneType, tyreIndex)
end

-- ox_inventory client exports.
exports('tire_kit', function(data, slot)
    runRepair('tire_kit')
end)

exports('body_kit', function(data, slot)
    runRepair('body_kit')
end)

exports('engine_kit', function(data, slot)
    runRepair('engine_kit')
end)

exports('cleaning_kit', function(data, slot)
    runRepair('cleaning_kit')
end)

exports('full_kit', function(data, slot)
    runRepair('full_kit')
end)

-- Bone-aware ox_target support. Target selection is moved into a new thread so the
-- ox_target NUI callback can return before ox_lib starts its skillCheck UI.
CreateThread(function()
    Wait(500)

    for kitName, kit in pairs(Kits) do
        local thisKitName = kitName
        local thisKit = kit
        local zoneName = kitZones[thisKitName]
        local targetZone = Config.TargetZones[zoneName == 'tire' and 'wheels' or zoneName == 'body' and 'panels' or zoneName == 'engine' and 'engine' or zoneName == 'clean' and 'clean' or 'vehicle']

        exports.ox_target:addGlobalVehicle({
            {
                name = 'repairkit_' .. thisKitName,
                label = thisKit.label or thisKitName,
                icon = 'fa-solid fa-screwdriver-wrench',
                distance = 2.5,
                bones = targetZone and targetZone.bones or nil,
                items = thisKit.item,
                canInteract = function(entity)
                    if busy or not entity or entity == 0 then return false end
                    if not categoryAllowed(entity, thisKit) then return false end
                    if zoneName == 'engine' and not isPlayerInFrontOfVehicle(entity) then return false end
                    return true
                end,
                onSelect = function(data)
                    local entity = data.entity
                    local selectedTyreIndex = nil

                    if thisKitName == 'tire_kit' and zoneName == 'tire' then
                        -- data.coords is the ox_target shape-test hit position. Since this
                        -- option is restricted to wheel bones, the closest wheel bone is
                        -- the exact tyre the player selected.
                        selectedTyreIndex = getClosestTyreIndex(entity, data.coords)
                    end

                    CreateThread(function()
                        runRepair(thisKitName, entity, zoneName, true, selectedTyreIndex)
                    end)
                end
            }
        })
    end
end)

local function snapshotTyres(vehicle)
    local tyres = {}
    for i = 0, 7 do
        tyres[i] = IsVehicleTyreBurst(vehicle, i, false) or IsVehicleTyreBurst(vehicle, i, true)
    end
    return tyres
end

local function restoreBurstTyres(vehicle, tyres)
    for i = 0, 7 do
        if tyres[i] then
            SetVehicleTyreBurst(vehicle, i, true, 1000.0)
        end
    end
end

local function applyBodyRepair(vehicle, repairPercent)
    local bodyHealth = GetVehicleBodyHealth(vehicle)
    local bodyMissing = math.max(0.0, 1000.0 - bodyHealth)
    local newBodyHealth = math.min(1000.0, bodyHealth + (bodyMissing * repairPercent))

    -- SetVehicleFixed is required to reliably clear visible GTA body deformation.
    -- Preserve non-body state so a Body Kit cannot repair the engine or tyres.
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local petrolTankHealth = GetVehiclePetrolTankHealth(vehicle)
    local tyres = snapshotTyres(vehicle)

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)

    SetVehicleEngineHealth(vehicle, engineHealth)
    SetVehiclePetrolTankHealth(vehicle, petrolTankHealth)
    restoreBurstTyres(vehicle, tyres)
    SetVehicleBodyHealth(vehicle, newBodyHealth)

    return newBodyHealth > bodyHealth + 0.01
end

RegisterNetEvent('repairkits:applyRepair', function(netId, kitName, zoneType, percent, tyreIndex)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        busy = false
        TriggerServerEvent('repairkits:repairApplied', false, kitName, netId, zoneType, {})
        return
    end

    requestControl(vehicle, 1500)

    local applied = {}
    local success = false
    local repairPercent = math.max(0, math.min(100, percent or 100)) / 100.0

    if zoneType == 'tire' then
        -- A dedicated Tyre Kit repairs only the selected/nearest tyre. It must
        -- not repair every burst tyre on the vehicle.
        if tyreIndex ~= nil and (IsVehicleTyreBurst(vehicle, tyreIndex, false) or IsVehicleTyreBurst(vehicle, tyreIndex, true)) then
            SetVehicleTyreFixed(vehicle, tyreIndex)
            applied[1] = ('tire_%d'):format(tyreIndex)
            success = true
        end
    elseif zoneType == 'body' then
        success = applyBodyRepair(vehicle, repairPercent)
        if success then applied[1] = 'body' end
    elseif zoneType == 'engine' then
        local engineHealth = GetVehicleEngineHealth(vehicle)
        local engineMissing = math.max(0.0, 1000.0 - engineHealth)
        local newEngineHealth = math.min(1000.0, engineHealth + (engineMissing * repairPercent))

        SetVehicleEngineHealth(vehicle, newEngineHealth)
        success = newEngineHealth > engineHealth + 0.01
        if success then applied[1] = 'engine' end
    elseif zoneType == 'clean' then
        local currentDirt = GetVehicleDirtLevel(vehicle)
        local newDirt = math.max(0.0, currentDirt * (1.0 - repairPercent))

        SetVehicleDirtLevel(vehicle, newDirt)
        success = newDirt < currentDirt - 0.01
        if success then applied[1] = 'clean' end
    elseif zoneType == 'full' then
        local bodyHealth = GetVehicleBodyHealth(vehicle)
        local bodyMissing = math.max(0.0, 1000.0 - bodyHealth)
        local newBodyHealth = math.min(1000.0, bodyHealth + (bodyMissing * repairPercent))

        local engineHealth = GetVehicleEngineHealth(vehicle)
        local engineMissing = math.max(0.0, 1000.0 - engineHealth)
        local newEngineHealth = math.min(1000.0, engineHealth + (engineMissing * repairPercent))

        -- Full kit intentionally refreshes all repairable vehicle visuals/components.
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleBodyHealth(vehicle, newBodyHealth)
        SetVehicleEngineHealth(vehicle, newEngineHealth)

        -- Full Kit remains the complete repair option and fixes every supported
        -- tyre position, including the extra middle-wheel indices used by some
        -- multi-axle vehicles.
        local allTyreIndices = { 0, 1, 2, 3, 4, 5, 45, 47 }
        for i = 1, #allTyreIndices do
            local tyre = allTyreIndices[i]
            if IsVehicleTyreBurst(vehicle, tyre, false) or IsVehicleTyreBurst(vehicle, tyre, true) then
                SetVehicleTyreFixed(vehicle, tyre)
            end
        end

        SetVehicleDirtLevel(vehicle, 0.0)

        applied[1] = 'body'
        applied[2] = 'engine'
        applied[3] = 'tires'
        applied[4] = 'clean'
        success = true
    end

    TriggerServerEvent('repairkits:repairApplied', success, kitName, netId, zoneType, applied)
end)

RegisterNetEvent('repairkits:serverResult', function(success, message)
    busy = false
    notify(message or (success and 'Repair successful.' or 'Repair failed.'), success and 'success' or 'error')
end)
