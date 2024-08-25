ESX = exports['so_213']:getSharedObject()
local TontonEvent = TriggerServerEvent
local clientVersion = "1.0.0"
local canSell = false -- Indique si le joueur peut vendre ou non
local deliveryNPC = nil -- Pour suivre le PNJ de livraison
local playerBlip = nil -- Blip unique pour le joueur qui a lancé /drugs

function checkVersion()
    TontonEvent("checkVersion", clientVersion)
end

Citizen.CreateThread(function()
    checkVersion()
end)

Drugs = {}

Drugs.Items = {
    ["weed"] = true,
    ["meth"] = true,
    ["coke"] = true,
    ["extasy"] = true
}

Drugs.Sell = false

function Drugs:GetRandomCoords()
    if not Drugs.Sell then return end
    
    local playerCoords = GetEntityCoords(PlayerPedId())
    local CoordsDrugs, SafeCoords = GetSafeCoordForPed(playerCoords.x + GetRandomIntInRange(-40, 40), playerCoords.y + GetRandomIntInRange(-40, 40), playerCoords.z, true, 0, 16)

    if not CoordsDrugs or GetDistanceBetweenCoords(playerCoords.x, playerCoords.y, playerCoords.z, SafeCoords.x, SafeCoords.y, SafeCoords.z) < 20 then
        return
    end

    local heading = GetRandomIntInRange(0, 360)

    return vector3(SafeCoords.x, SafeCoords.y, SafeCoords.z - 1.0), heading
end 

function Drugs:PlayerHasEnoughItems()
    for _, item in pairs(ESX.GetPlayerData().inventory) do
        if item.count >= 2 and Drugs.Items[item.name] then
            return item.name
        end
    end
    return nil
end

function Drugs:CreateBlip(pos, data)
    if playerBlip then 
        RemoveBlip(playerBlip) 
    end 
    playerBlip = AddBlipForCoord(pos)
    SetBlipSprite(playerBlip, data[1])
    SetBlipColour(playerBlip, data[2])
    SetBlipScale(playerBlip, data[4])
    SetBlipAsShortRange(playerBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data[3])
    EndTextCommandSetBlipName(playerBlip)
end

function Drugs:Anim(lib, anim)
    ESX.Streaming.RequestAnimDict(lib, function()
        TaskPlayAnim(PlayerPedId(), lib, anim, 8.0, -8.0, -1, 0, 0.0, false, false, false)
    end)
end

function Drugs:SpawnNPC(coords, heading)
    local hash = GetHashKey("a_m_y_stwhi_02")
    RequestModel(hash)
    while not HasModelLoaded(hash) do
        Wait(1)
    end

    local npc = CreatePed(4, hash, coords.x, coords.y, coords.z, heading, false, true)
    SetEntityAsMissionEntity(npc, true, true)
    TaskStartScenarioInPlace(npc, "WORLD_HUMAN_STAND_MOBILE", 0, true)
    return npc
end

function Drugs:StartBoucleForSelling()
    local playerHasEnoughItems = Drugs:PlayerHasEnoughItems()
    if not playerHasEnoughItems then 
        ESX.ShowNotification("~r~Vous n'avez pas assez de drogue sur vous pour commencer une vente.")
        return 
    end

    Drugs.Sell = true
    canSell = true -- Permet à ce joueur de vendre

    local deliveryPos, deliveryHeading = Drugs:GetRandomCoords()
    if deliveryPos then
        TontonEvent('Drugs:CreateNPC', deliveryPos, deliveryHeading)
        Drugs:CreateBlip(deliveryPos, {501, 2, "Livraison", 0.6}) -- Le blip est uniquement visible par le joueur qui a lancé /drugs
    end
end

RegisterNetEvent('Drugs:SpawnNPCForAll')
AddEventHandler('Drugs:SpawnNPCForAll', function(coords, heading, sourcePlayerId)
    deliveryNPC = Drugs:SpawnNPC(coords, heading)
    local playerCoords = GetEntityCoords(PlayerPedId())
    local delivery = {}
    delivery.npc = deliveryNPC
    delivery.point = coords

    if GetPlayerServerId(PlayerId()) == sourcePlayerId then
        canSell = true -- Ce joueur peut vendre
        Drugs:CreateBlip(coords, {501, 2, "Livraison", 0.6}) -- Créer le blip uniquement pour l'appelant de /drugs
    else
        canSell = false -- Les autres joueurs ne peuvent pas vendre
    end

    Citizen.CreateThread(function()
        while delivery.npc do
            local playerCoords = GetEntityCoords(PlayerPedId())
            
            if #(playerCoords - delivery.point) < 3.0 then
                if canSell then
                    ESX.ShowHelpNotification("Appuyez sur ~INPUT_CONTEXT~ pour ~g~donner~s~ la ~g~livraison~s~ au client.")
                    if IsControlJustReleased(0, 54) then
                        Drugs:Anim("mp_common", "givetake1_a")
                        FreezeEntityPosition(PlayerPedId(), true)
                        Wait(GetAnimDuration("mp_common", "givetake1_a") * 1000)

                        -- Synchronisation des animations pour tous les joueurs
                        TriggerServerEvent("Drugs:SyncAnim", "mp_common", "givetake1_a", "givetake1_b", delivery.npc)
                        TriggerServerEvent("Drugs:SyncAnim", "mp_common", "givetake2_a", "givetake2_b", delivery.npc)

                        ClearPedTasks(delivery.npc)
                        TaskPlayAnim(delivery.npc, "mp_common", "givetake1_b", 8.0, -8.0, -1, 0, 0.0, false, false, false)
                        Wait(2000)

                        TaskPlayAnim(delivery.npc, "mp_common", "givetake2_b", 8.0, -8.0, -1, 0, 0.0, false, false, false)
                        Wait(2000)

                        FreezeEntityPosition(PlayerPedId(), false)
                        if playerBlip then
                            RemoveBlip(playerBlip)
                            playerBlip = nil
                        end

                        -- Alerte la sasp avec un point rouge
                        TontonEvent("Drugs:AlertSasp", GetEntityCoords(PlayerPedId()))

                        TriggerServerEvent("Drugs:Sell", Drugs:PlayerHasEnoughItems())

                        TriggerServerEvent("Drugs:MoveNPC", coords) -- Déplacement du NPC pour tous les joueurs

                        delivery.npc = nil
                        canSell = false
                    end
                else
                    ESX.ShowHelpNotification("~r~Vous ne pouvez pas vendre à ce client.")
                end
            end

            Wait(0)
        end
    end)
end)

RegisterNetEvent('Drugs:MoveNPCForAll')
AddEventHandler('Drugs:MoveNPCForAll', function(coords)
    if deliveryNPC then
        TaskWanderStandard(deliveryNPC, 10.0, 10) -- Le NPC commence à marcher après la vente
        deliveryNPC = nil
    end
end)

RegisterNetEvent('Drugs:PlayAnimForAll')
AddEventHandler('Drugs:PlayAnimForAll', function(lib, anim, npc)
    if DoesEntityExist(npc) then
        TaskPlayAnim(npc, lib, anim, 8.0, -8.0, -1, 0, 0.0, false, false, false)
    end
end)

RegisterNetEvent('Drugs:CreateSaspBlip')
AddEventHandler('Drugs:CreateSaspBlip', function(coords)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161)
    SetBlipScale(blip, 1.2)
    SetBlipColour(blip, 1)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString("Trafic de drogue")
    EndTextCommandSetBlipName(blip)

    -- Le blip disparaît après 2 minutes
    Citizen.CreateThread(function()
        Wait(120000)
        RemoveBlip(blip)
    end)
end)

RegisterCommand("drugs", function()
    Drugs:StartBoucleForSelling()
end)
