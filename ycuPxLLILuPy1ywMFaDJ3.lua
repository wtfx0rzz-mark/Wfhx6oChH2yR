--[[
    99 Nights in the Forest | WindUI (Full Integration)
    Includes:
      • Bring physics fix (no floating; server-owned; downward nudge; ground-snap).
      • Auto Campfire drop (MainFire) + Auto Materials Grinder drop (nearby) — default ON.
      • Auto Collect Gold (Main tab).
      • "Don't spawn over head" option (default ON = drop to ground ring).
      • Big Trees Aura (TreeBig1/2/3).
      • Equip arbitration so auras don't constantly thrash tools.
      • All original tabs preserved (Combat, Main, Esp, Bring, Teleport, Player, Environment).
]]

repeat task.wait() until game:IsLoaded()

-- =====================
-- Tunables
-- =====================
local AURA_SWING_DELAY   = 0.55
local CHOP_SWING_DELAY   = 0.55
local BIGTREE_SWING_DELAY= 0.55

local TREE_NAME          = "Small Tree"
local BIG_TREE_NAMES     = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
local UID_SUFFIX         = "0000000000"

-- Bring tuning
local BRING_INNER_RADIUS = 7
local BRING_MAX_RADIUS   = 2000
local BRING_BATCH_SIZE   = 40
local BRING_GROUND_SNAP  = true     -- ray to place on terrain
local BRING_PUSH_DOWN    = 30       -- downward linear velocity
local BRING_ANGULAR_JIT  = 5        -- tiny random spin
local DROP_OVERHEAD      = false    -- if true: drop above head; if false: ground-ring (recommended)

-- Campfire auto-drop
local CAMPFIRE_PATH   = {"Map","Campground","MainFire"}
local CAMPFIRE_NEAR_R = 1.5
local CAMPFIRE_ABOVE_H= 6
local AUTO_TO_CAMPFIRE= true        -- default enabled

-- Materials Grinder auto-drop
local GRINDER_NEAR_R  = 2.0
local GRINDER_ABOVE_H = 7
local AUTO_TO_GRINDER = true        -- default enabled

-- UI + Services
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Helpers
local function waitForDescendant(root, name, timeout)
    timeout = timeout or 10
    local t0 = tick()
    local found = root:FindFirstChild(name, true)
    while not found and tick() - t0 < timeout do
        task.wait(0.05)
        found = root:FindFirstChild(name, true)
    end
    return found
end

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
                  or ReplicatedStorage:FindFirstChild("Remotes")
                  or waitForDescendant(ReplicatedStorage, "RemoteEvents", 10)

local EquipItemHandle   = RemoteEvents and (RemoteEvents:FindFirstChild("EquipItemHandle") or waitForDescendant(RemoteEvents,"EquipItemHandle",10))
local UnequipItemHandle = RemoteEvents and RemoteEvents:FindFirstChild("UnequipItemHandle")
local ToolDamageObject  = RemoteEvents and (RemoteEvents:FindFirstChild("ToolDamageObject")
                        or RemoteEvents:FindFirstChild("ToolDamage")
                        or RemoteEvents:FindFirstChild("DamageObject"))
                        or waitForDescendant(ReplicatedStorage,"ToolDamageObject",10)

-- =====================
-- Themes
-- =====================
WindUI:AddTheme({ Name="Dark",   Accent="#18181b", Dialog="#18181b", Outline="#FFFFFF", Text="#FFFFFF", Placeholder="#999999", Background="#0e0e10", Button="#52525b", Icon="#a1a1aa" })
WindUI:AddTheme({ Name="Light",  Accent="#f4f4f5", Dialog="#f4f4f5", Outline="#000000", Text="#000000", Placeholder="#666666", Background="#ffffff", Button="#e4e4e7", Icon="#52525b" })
WindUI:AddTheme({ Name="Gray",   Accent="#374151", Dialog="#374151", Outline="#d1d5db", Text="#f9fafb", Placeholder="#9ca3af", Background="#1f2937", Button="#4b5563", Icon="#d1d5db" })
WindUI:AddTheme({ Name="Blue",   Accent="#1e40af", Dialog="#1e3a8a", Outline="#93c5fd", Text="#f0f9ff", Placeholder="#60a5fa", Background="#1e293b", Button="#3b82f6", Icon="#93c5fd" })
WindUI:AddTheme({ Name="Green",  Accent="#059669", Dialog="#047857", Outline="#6ee7b7", Text="#ecfdf5", Placeholder="#34d399", Background="#064e3b", Button="#10b981", Icon="#6ee7b7" })
WindUI:AddTheme({ Name="Purple", Accent="#7c3aed", Dialog="#6d28d9", Outline="#c4b5fd", Text="#faf5ff", Placeholder="#a78bfa", Background="#581c87", Button="#8b5cf6", Icon="#c4b5fd" })
WindUI:SetNotificationLower(true)

local themes = {"Dark","Light","Gray","Blue","Green","Purple"}
local currentThemeIndex = 1
getgenv().TransparencyEnabled = getgenv().TransparencyEnabled or false

-- =====================
-- Combat state
-- =====================
local killAuraToggle = false
local chopAuraToggle = false
local bigTreeAuraToggle = false
local auraRadius = 50

-- hit ids
local _hitCounter = 0
local function nextHitId()
    _hitCounter += 1
    return tostring(_hitCounter) .. "_" .. UID_SUFFIX
end

-- tools & preferences
local toolsDamageIDs = {
    ["Old Axe"]    = "3_7367831688",
    ["Good Axe"]   = "112_7367831688",
    ["Strong Axe"] = "116_7367831688",
    ["Chainsaw"]   = "647_8992824875",
    ["Spear"]      = "196_8999010016"
}
local ChopPrefer = {"Chainsaw","Strong Axe","Good Axe","Old Axe"}
local KillPrefer = {"Spear","Strong Axe","Good Axe","Old Axe","Chainsaw"}

-- inventory helpers
local function findInInventory(name)
    local inv = LocalPlayer and LocalPlayer:FindFirstChild("Inventory")
    return inv and inv:FindFirstChild(name) or nil
end
local function getToolDamageId(toolName) return toolsDamageIDs[toolName] end
local function firstToolFromList(list)
    for _,n in ipairs(list) do
        local t = findInInventory(n)
        if t then return t, n end
    end
end
local function equippedToolName()
    local char = LocalPlayer.Character
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    return t and t.Name or nil
end
local function ensureEquipped(wantedName)
    if not wantedName then return nil end
    local cur = equippedToolName()
    if cur == wantedName then
        return findInInventory(wantedName)
    end
    local tool = findInInventory(wantedName)
    if tool and EquipItemHandle then
        pcall(function() EquipItemHandle:FireServer("FireAllClients", tool) end)
    end
    return tool
end

-- =====================
-- Auto Food helpers
-- =====================
local autoFeedToggle = false
local selectedFood = {}
local hungerThreshold = 75
local alimentos = {"Apple","Berry","Carrot","Cake","Chili","Cooked Morsel","Cooked Steak"}

local function wiki(nome)
    local c = 0
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then return 0 end
    for _, i in ipairs(itemsFolder:GetChildren()) do
        if i.Name == nome then c += 1 end
    end
    return c
end
local function ghn()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return 100 end
    local ok, scale = pcall(function()
        return gui.Interface.StatBars.HungerBar.Bar.Size.X.Scale
    end)
    if ok and type(scale)=="number" then return math.floor(scale*100) end
    return 100
end
local function feed(nome)
    local items = Workspace:FindFirstChild("Items")
    if not items then return end
    for _, item in ipairs(items:GetChildren()) do
        if item.Name == nome then
            pcall(function()
                ReplicatedStorage.RemoteEvents.RequestConsumeItem:InvokeServer(item)
            end)
            break
        end
    end
end

-- =====================
-- Tree hit CFrame
-- =====================
local function bestTreeHitPart(tree)
    if not tree or not tree:IsA("Model") then return nil end
    local hr = tree:FindFirstChild("HitRegisters")
    if hr then
        local t = hr:FindFirstChild("Trunk")
        if t and t:IsA("BasePart") then return t end
        local any = hr:FindFirstChildWhichIsA("BasePart")
        if any then return any end
    end
    return tree:FindFirstChild("Trunk")
end

local SYN_OFFSET, SYN_DEPTH = 1.0, 4.0
local function computeImpactCFrame(model, hitPart)
    if not (model and hitPart and hitPart:IsA("BasePart")) then
        return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
    end
    local outward = hitPart.CFrame.LookVector
    if outward.Magnitude == 0 then outward = Vector3.new(0,0,-1) end
    outward = outward.Unit
    local origin  = hitPart.Position + outward * SYN_OFFSET
    local dir     = -outward * (SYN_OFFSET + SYN_DEPTH)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {model}
    local rc = Workspace:Raycast(origin, dir, params)
    local pos = rc and (rc.Position + rc.Normal*0.02) or (origin + dir*0.6)
    local rot = hitPart.CFrame - hitPart.CFrame.Position
    return CFrame.new(pos) * rot
end

-- =====================
-- Aura loops
-- =====================
local function killAuraLoop()
    while killAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local tool, toolName = firstToolFromList(KillPrefer)
            -- If Chop/BigTree is running, follow whatever is already equipped to avoid contention
            if bigTreeAuraToggle or chopAuraToggle then
                toolName = equippedToolName() or toolName
                tool = toolName and findInInventory(toolName)
            end
            local damageID = toolName and getToolDamageId(toolName)
            if tool and damageID then
                ensureEquipped(toolName)
                local charsFolder = Workspace:FindFirstChild("Characters")
                if charsFolder then
                    local origin = hrp.Position
                    for _, mob in ipairs(charsFolder:GetChildren()) do
                        if not killAuraToggle then break end
                        if mob:IsA("Model") and mob ~= character then
                            local part = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart")
                            if part and (part.Position - origin).Magnitude <= auraRadius then
                                task.spawn(function()
                                    pcall(function()
                                        ToolDamageObject:InvokeServer(mob, tool, damageID, CFrame.new(part.Position))
                                    end)
                                end)
                            end
                        end
                    end
                end
                task.wait(AURA_SWING_DELAY)
            else
                task.wait(0.4)
            end
        else
            task.wait(0.2)
        end
    end
end

local function chopWaveForTrees(trees, swingDelay)
    local tool, name = firstToolFromList(ChopPrefer)
    if not tool then task.wait(0.4) return end
    ensureEquipped(name)
    for _, tree in ipairs(trees) do
        task.spawn(function()
            local hitPart = bestTreeHitPart(tree)
            if hitPart then
                local impactCF = computeImpactCFrame(tree, hitPart)
                local hitId = nextHitId()
                pcall(function()
                    ToolDamageObject:InvokeServer(tree, tool, hitId, impactCF)
                end)
            end
        end)
    end
    task.wait(swingDelay)
end

local function chopAuraLoop()
    while chopAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2) break end

        local origin = hrp.Position
        local trees = {}
        local map = Workspace:FindFirstChild("Map")
        local function scan(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj.Name == TREE_NAME then
                    local trunk = bestTreeHitPart(obj) or obj:FindFirstChild("Trunk")
                    if trunk and (trunk.Position - origin).Magnitude <= auraRadius then
                        trees[#trees+1] = obj
                    end
                end
            end
        end
        if map then scan(map:FindFirstChild("Foliage")); scan(map:FindFirstChild("Landmarks")) end
        if #trees > 0 then chopWaveForTrees(trees, CHOP_SWING_DELAY) else task.wait(0.3) end
    end
end

local function bigTreeAuraLoop()
    while bigTreeAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2) break end

        local origin = hrp.Position
        local trees = {}
        local foliage = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Foliage")
        if foliage then
            for _, m in ipairs(foliage:GetChildren()) do
                if m:IsA("Model") and BIG_TREE_NAMES[m.Name] then
                    local part = bestTreeHitPart(m) or m:FindFirstChild("Trunk") or m.PrimaryPart
                    if part and (part.Position - origin).Magnitude <= auraRadius then
                        trees[#trees+1] = m
                    end
                end
            end
        end
        if #trees > 0 then chopWaveForTrees(trees, BIGTREE_SWING_DELAY) else task.wait(0.3) end
    end
end

-- =====================
-- Campfire / Grinder Helpers
-- =====================
local function getCampfire()
    local cur = Workspace
    for _,n in ipairs(CAMPFIRE_PATH) do
        cur = cur and cur:FindFirstChild(n)
    end
    return cur
end
local function isNearCampfire(hrpPos)
    if not AUTO_TO_CAMPFIRE then return false, nil end
    local fire = getCampfire()
    local part = fire and fire:IsA("BasePart") and fire or (fire and fire:FindFirstChildWhichIsA("BasePart"))
    if not part then return false, nil end
    local pos = part.Position
    local horizontal = Vector2.new(hrpPos.X - pos.X, hrpPos.Z - pos.Z).Magnitude
    local above = (hrpPos.Y >= pos.Y) and (hrpPos.Y - pos.Y <= CAMPFIRE_ABOVE_H)
    if horizontal <= CAMPFIRE_NEAR_R or (horizontal <= CAMPFIRE_NEAR_R*1.2 and above) then
        return true, part
    end
    return false, part
end

local function findAnyGrinder()
    -- You can hard-path this if you know the exact object:
    -- local hard = Workspace:FindFirstChild("Map")
    --            and Workspace.Map:FindFirstChild("Campground")
    --            and Workspace.Map.Campground:FindFirstChild("MaterialsGrinder")
    -- if hard then return hard:IsA("BasePart") and hard or hard:FindFirstChildWhichIsA("BasePart") end

    -- Fallback: search by name
    for _, inst in ipairs(Workspace:GetDescendants()) do
        local n = tostring(inst.Name):lower()
        if (n:find("grinder") or n:find("material")) and (inst:IsA("BasePart") or inst:IsA("Model")) then
            return inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart")
        end
    end
    return nil
end
local function isNearGrinder(hrpPos)
    if not AUTO_TO_GRINDER then return false, nil end
    local part = findAnyGrinder()
    if not part then return false, nil end
    local pos = part.Position
    local horizontal = Vector2.new(hrpPos.X - pos.X, hrpPos.Z - pos.Z).Magnitude
    local above = (hrpPos.Y >= pos.Y) and (hrpPos.Y - pos.Y <= GRINDER_ABOVE_H)
    if horizontal <= GRINDER_NEAR_R or (horizontal <= GRINDER_NEAR_R*1.2 and above) then
        return true, part
    end
    return false, part
end

-- =====================
-- BRING (physics+targeting)
-- =====================
local function toLowerSet(list)
    local set = {}
    for _, n in ipairs(list or {}) do
        if type(n) == "string" then set[string.lower(n)] = true end
    end
    return set
end
local function getMainPart(obj)
    if not obj or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end
local function groundSnapAt(pos)
    local origin = pos + Vector3.new(0, 200, 0)
    local dir = Vector3.new(0, -500, 0)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    local rc = Workspace:Raycast(origin, dir, params)
    if rc then
        return rc.Position + Vector3.new(0, 1.2, 0)
    else
        return pos
    end
end

local function dropTargetCF(hrp)
    local hrpPos = hrp.Position

    -- 1) Campfire
    local nearFire, firePart = isNearCampfire(hrpPos)
    if nearFire and firePart then
        return CFrame.new(firePart.Position + Vector3.new(0, 2.2, 0)), "fire"
    end

    -- 2) Grinder
    local nearGrinder, grinderPart = isNearGrinder(hrpPos)
    if nearGrinder and grinderPart then
        return CFrame.new(grinderPart.Position + Vector3.new(0, 2.2, 0)), "grinder"
    end

    -- 3) Player area
    if DROP_OVERHEAD then
        return CFrame.new(hrpPos + Vector3.new(0, 5, 0)), "overhead"
    end
    local r = math.max(2, BRING_INNER_RADIUS - 1)
    local theta = math.random() * math.pi * 2
    local around = Vector3.new(hrpPos.X + math.cos(theta)*r, hrpPos.Y + 4, hrpPos.Z + math.sin(theta)*r)
    if BRING_GROUND_SNAP then around = groundSnapAt(around) end
    return CFrame.new(around), "ground"
end

local function wakePart(p)
    pcall(function() p:SetNetworkOwnershipAuto() end)
    pcall(function() p:SetNetworkOwner(nil) end)
    p.Anchored = false
    p.CanCollide = true
    if p.Massless then p.Massless = false end
    p.AssemblyLinearVelocity  = Vector3.new(0, -BRING_PUSH_DOWN, 0)
    p.AssemblyAngularVelocity = Vector3.new(
        math.rad(math.random()*BRING_ANGULAR_JIT),
        math.rad(math.random()*BRING_ANGULAR_JIT),
        math.rad(math.random()*BRING_ANGULAR_JIT)
    )
end

local function moveItemOnce(modelOrPart, dropCF)
    if modelOrPart:IsA("Model") then
        modelOrPart:PivotTo(dropCF)
        for _, sub in ipairs(modelOrPart:GetDescendants()) do
            if sub:IsA("BasePart") then wakePart(sub) end
        end
    else
        modelOrPart.CFrame = dropCF
        wakePart(modelOrPart)
    end
end

function bringItemsSmart(nameList, innerRadius, maxRadius, batchSize)
    local player = LocalPlayer
    local char = player and player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    innerRadius = tonumber(innerRadius) or BRING_INNER_RADIUS
    maxRadius   = tonumber(maxRadius)   or BRING_MAX_RADIUS
    batchSize   = math.max(1, tonumber(batchSize) or BRING_BATCH_SIZE)

    local wanted = toLowerSet(nameList)
    if next(wanted) == nil then return end

    local hrpPos = hrp.Position
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then return end

    local candidates = {}
    for _, obj in ipairs(itemsFolder:GetChildren()) do
        if wanted[string.lower(obj.Name or "")] then
            local part = getMainPart(obj)
            if part and part:IsDescendantOf(itemsFolder) then
                local d = (part.Position - hrpPos).Magnitude
                if d > innerRadius and d <= maxRadius then
                    table.insert(candidates, {part = part, model = obj, dist = d})
                end
            end
        end
    end
    if #candidates == 0 then return end

    table.sort(candidates, function(a,b) return a.dist > b.dist end)

    local dropCF, target = dropTargetCF(hrp)
    for i = 1, math.min(batchSize, #candidates) do
        local entry = candidates[i]
        if entry.part and entry.part.Parent and entry.part:IsDescendantOf(itemsFolder) then
            local jitter = CFrame.new(math.random(-1,1), 0, math.random(-1,1))
            moveItemOnce(entry.model, dropCF * jitter)
        end
    end

    if target == "fire" or target == "grinder" then
        task.delay(0.1, function()
            for i = 1, math.min(batchSize, #candidates) do
                local model = candidates[i].model
                if model and model.Parent then
                    for _, sub in ipairs(model:GetDescendants()) do
                        if sub:IsA("BasePart") then
                            sub.AssemblyLinearVelocity = Vector3.new(0, -BRING_PUSH_DOWN * 1.5, 0)
                        end
                    end
                end
            end
        end)
    end
end

-- =====================
-- Bring UI categories
-- =====================
local junkItems = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
local fuelItems = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
local foodItems = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
local medicalItems = {"Bandage","MedKit"}
local equipmentItems = {"Revolver","Rifle","Leather Body","Iron Body","Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Strong Axe","Good Axe"}

local selectedJunkItems, selectedFuelItems, selectedFoodItems = {}, {}, {}
local selectedMedicalItems, selectedEquipmentItems = {}, {}
local _bringFlags = {}

-- =====================
-- Window & Tabs (WindUI)
-- =====================
local Window = WindUI:CreateWindow({
    Title = "99 Nights in forest",
    Icon = "zap",
    Author = "Mark",
    Folder = "Mark",
    Size = UDim2.fromOffset(500, 350),
    Transparent = getgenv().TransparencyEnabled,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 150,
    BackgroundImageTransparency = 0.8,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    User = {
        Enabled = true,
        Anonymous = false,
        Callback = function()
            currentThemeIndex += 1
            if currentThemeIndex > #themes then currentThemeIndex = 1 end
            local newTheme = themes[currentThemeIndex]
            WindUI:SetTheme(newTheme)
            WindUI:Notify({ Title="Theme Changed", Content="Switched to " .. newTheme .. " theme!", Duration=2, Icon="palette" })
        end,
    },
})
Window:SetToggleKey(Enum.KeyCode.V)
pcall(function()
    Window:CreateTopbarButton("TransparencyToggle","eye",function()
        getgenv().TransparencyEnabled = not getgenv().TransparencyEnabled
        pcall(function() Window:ToggleTransparency(getgenv().TransparencyEnabled) end)
        WindUI:Notify({ Title="Transparency", Content=(getgenv().TransparencyEnabled and "Enabled" or "Disabled"), Duration=3, Icon=getgenv().TransparencyEnabled and "eye-off" or "eye" })
    end, 990)
end)
Window:EditOpenButton({ Title="Toggle", Icon="zap", CornerRadius=UDim.new(0,6), StrokeThickness=2, Color=ColorSequence.new(Color3.fromRGB(138,43,226), Color3.fromRGB(173,216,230)), Draggable=true })

local Tabs = {}
Tabs.Combat = Window:Tab({ Title="Combat", Icon="sword", Desc="x" })
Tabs.Main   = Window:Tab({ Title="Main",   Icon="align-left", Desc="x" })
Tabs.esp    = Window:Tab({ Title="Esp",    Icon="sparkles",   Desc="x" })
Tabs.br     = Window:Tab({ Title="Bring",  Icon="package",    Desc="x" })
Tabs.Tp     = Window:Tab({ Title="Teleport", Icon="map",      Desc="x" })
Tabs.Fly    = Window:Tab({ Title="Player", Icon="user",       Desc="x" })
Tabs.Vision = Window:Tab({ Title="Environment", Icon="eye",   Desc="x" })
Window:SelectTab(1)

-- =====================
-- Combat UI
-- =====================
Tabs.Combat:Section({ Title="Aura", Icon="star" })
Tabs.Combat:Toggle({
    Title = "Kill Aura",
    Value = false,
    Callback = function(state)
        killAuraToggle = state
        if state then task.spawn(killAuraLoop) end
    end
})
Tabs.Combat:Toggle({
    Title = "Chop Aura",
    Value = false,
    Callback = function(state)
        chopAuraToggle = state
        if state then task.spawn(chopAuraLoop) end
    end
})
Tabs.Combat:Toggle({
    Title = "Big Trees",
    Value = false,
    Callback = function(state)
        bigTreeAuraToggle = state
        if state then task.spawn(bigTreeAuraLoop) end
    end
})
Tabs.Combat:Section({ Title="Settings", Icon="settings" })
Tabs.Combat:Slider({
    Title = "Aura Radius",
    Value = { Min=50, Max=2000, Default=50 },
    Callback = function(value) auraRadius = math.clamp(value, 10, 2000) end
})

-- =====================
-- Main (Auto Feed + Auto Gold)
-- =====================
Tabs.Main:Section({ Title="Survival", Icon="heart" })
Tabs.Main:Toggle({
    Title = "Auto Feed",
    Value = false,
    Callback = function(state)
        autoFeedToggle = state
        if state then
            task.spawn(function()
                while autoFeedToggle do
                    task.wait(0.075)
                    if not selectedFood or #selectedFood == 0 then continue end
                    if ghn() <= hungerThreshold then
                        for _, foodName in ipairs(selectedFood) do
                            if wiki(foodName) > 0 then feed(foodName) break end
                        end
                    end
                    local anyLeft = false
                    for _, foodName in ipairs(selectedFood) do
                        if wiki(foodName) > 0 then anyLeft = true break end
                    end
                    if not anyLeft then
                        autoFeedToggle = false
                        WindUI:Notify({ Title="Auto Food Paused", Content="No selected food items remain.", Duration=3 })
                        break
                    end
                end
            end)
        end
    end
})

-- === Auto Collect Gold ===
local autoGold = false
local goldNames = {"Coin Stack","Gold Nugget","Gold Ore"} -- tweak for exact game names
Tabs.Main:Toggle({
    Title = "Auto Collect Gold",
    Value = false,
    Callback = function(state)
        autoGold = state
        if state then
            task.spawn(function()
                while autoGold do
                    -- Use smaller inner radius so stacks don’t spawn into your body
                    bringItemsSmart(goldNames, 6, 2000, 25)
                    task.wait(0.4)
                end
            end)
        end
    end
})

-- =====================
-- Teleport
-- =====================
local function tp1()
	(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart").CFrame =
CFrame.new(0.43132782, 15.77634621, -1.88620758, -0.270917892, 0.102997094, 0.957076371, 0.639657021, 0.762253821, 0.0990355015, -0.719334781, 0.639031112, -0.272391081)
end
local function tp2()
    local t = Workspace:FindFirstChild("Map")
        and Workspace.Map:FindFirstChild("Landmarks")
        and Workspace.Map.Landmarks:FindFirstChild("Stronghold")
        and Workspace.Map.Landmarks.Stronghold:FindFirstChild("Functional")
        and Workspace.Map.Landmarks.Stronghold.Functional:FindFirstChild("EntryDoors")
        and Workspace.Map.Landmarks.Stronghold.Functional.EntryDoors:FindFirstChild("DoorRight")
        and Workspace.Map.Landmarks.Stronghold.Functional.EntryDoors.DoorRight:FindFirstChild("Model")
    if t then
        local children = t:GetChildren()
        local destination = children[5]
        if destination and destination:IsA("BasePart") then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = destination.CFrame + Vector3.new(0,5,0) end
        end
    end
end
Tabs.Tp:Section({ Title="Teleport", Icon="map" })
Tabs.Tp:Button({ Title="Teleport to Campfire", Locked=false, Callback=function() tp1() end })
Tabs.Tp:Button({ Title="Teleport to Stronghold", Locked=false, Callback=function() tp2() end })

-- =====================
-- BRING UI
-- =====================
local function addBringSection(title, values, selectedRef)
    Tabs.br:Section({ Title = title, Icon = (title=="Fuel" and "flame") or (title=="Equipment" and "sword") or (title=="Medical" and "bandage") or "box" })
    Tabs.br:Dropdown({
        Title = "Select "..title.." Items",
        Desc  = "Choose items to bring",
        Values = values,
        Multi = true,
        AllowNone = true,
        Callback = function(options)
            table.clear(selectedRef)
            for _,v in ipairs(options) do selectedRef[#selectedRef+1]=v end
        end
    })
    Tabs.br:Toggle({
        Title = "Bring "..title.." Items",
        Default = false,
        Callback = function(on)
            _bringFlags[title] = on
            if on then
                task.spawn(function()
                    while _bringFlags[title] do
                        if #selectedRef > 0 then
                            bringItemsSmart(selectedRef, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                        end
                        task.wait(0.6)
                    end
                end)
            end
        end
    })
end
addBringSection("Junk",      junkItems,      selectedJunkItems)
addBringSection("Fuel",      fuelItems,      selectedFuelItems)
addBringSection("Food",      foodItems,      selectedFoodItems)
addBringSection("Medical",   medicalItems,   selectedMedicalItems)
addBringSection("Equipment", equipmentItems, selectedEquipmentItems)

-- QoL for Bring
Tabs.br:Section({ Title="Bring • QoL", Icon="settings" })
Tabs.br:Toggle({
    Title = "Auto-target Campfire",
    Value = AUTO_TO_CAMPFIRE,
    Callback = function(v) AUTO_TO_CAMPFIRE = v end
})
Tabs.br:Toggle({
    Title = "Auto-target Grinder",
    Value = AUTO_TO_GRINDER,
    Callback = function(v) AUTO_TO_GRINDER = v end
})
Tabs.br:Toggle({
    Title = "Drop Overhead (pushes you)",
    Value = DROP_OVERHEAD,
    Callback = function(v) DROP_OVERHEAD = v end
})
Tabs.br:Toggle({
    Title = "Ground Snap",
    Value = BRING_GROUND_SNAP,
    Callback = function(v) BRING_GROUND_SNAP = v end
})
Tabs.br:Slider({
    Title = "Bring Radius (inner)",
    Value = { Min=2, Max=20, Default=BRING_INNER_RADIUS },
    Callback = function(v) BRING_INNER_RADIUS = math.clamp(v,2,20) end
})
Tabs.br:Slider({
    Title = "Batch Size",
    Value = { Min=5, Max=100, Default=BRING_BATCH_SIZE },
    Callback = function(v) BRING_BATCH_SIZE = math.clamp(v,5,100) end
})

-- =====================
-- Player (fly/speed/noclip/inf jump) + Instant Open
-- =====================
local flyToggle, flySpeed, FLYING = false, 1, false
local flyKeyDown, flyKeyUp, mfly1, mfly2
local IYMouse = UserInputService

local function sFLY()
    repeat task.wait() until Players.LocalPlayer and Players.LocalPlayer.Character and Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart") and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    repeat task.wait() until IYMouse
    if flyKeyDown or flyKeyUp then flyKeyDown:Disconnect(); flyKeyUp:Disconnect() end

    local T = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local CONTROL = {F=0,B=0,L=0,R=0,Q=0,E=0}
    local lCONTROL = {F=0,B=0,L=0,R=0,Q=0,E=0}
    local SPEED = flySpeed

    local function FLY()
        FLYING = true
        local BG = Instance.new('BodyGyro'); local BV = Instance.new('BodyVelocity')
        BG.P = 9e4; BG.Parent = T; BV.Parent = T
        BG.MaxTorque = Vector3.new(9e9, 9e9, 9e9); BG.CFrame = T.CFrame
        BV.Velocity = Vector3.new(0,0,0); BV.MaxForce = Vector3.new(9e9,9e9,9e9)
        task.spawn(function()
            while FLYING do
                task.wait()
                if not flyToggle and Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid') then
                    Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid').PlatformStand = true
                end
                if CONTROL.L+CONTROL.R ~= 0 or CONTROL.F+CONTROL.B ~= 0 or CONTROL.Q+CONTROL.E ~= 0 then
                    SPEED = flySpeed
                elseif SPEED ~= 0 then
                    SPEED = 0
                end
                if (CONTROL.L+CONTROL.R) ~= 0 or (CONTROL.F+CONTROL.B) ~= 0 or (CONTROL.Q+CONTROL.E) ~= 0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector*(CONTROL.F+CONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame*CFrame.new(CONTROL.L+CONTROL.R,(CONTROL.F+CONTROL.B+CONTROL.Q+CONTROL.E)*0.2,0).p)-workspace.CurrentCamera.CoordinateFrame.p))*SPEED
                    lCONTROL = {F=CONTROL.F,B=CONTROL.B,L=CONTROL.L,R=CONTROL.R}
                elseif (CONTROL.L+CONTROL.R)==0 and (CONTROL.F+CONTROL.B)==0 and (CONTROL.Q+CONTROL.E)==0 and SPEED~=0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector*(lCONTROL.F+lCONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame*CFrame.new(lCONTROL.L+lCONTROL.R,(lCONTROL.F+lCONTROL.B+CONTROL.Q+CONTROL.E)*0.2,0).p)-workspace.CurrentCamera.CoordinateFrame.p))*SPEED
                else
                    BV.Velocity = Vector3.new(0,0,0)
                end
                BG.CFrame = workspace.CurrentCamera.CoordinateFrame
            end
            CONTROL={F=0,B=0,L=0,R=0,Q=0,E=0}; lCONTROL={F=0,B=0,L=0,R=0,Q=0,E=0}; SPEED=0
            BG:Destroy(); BV:Destroy()
            local h = Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
            if h then h.PlatformStand=false end
        end)
    end
    flyKeyDown = IYMouse.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Keyboard then
            local KEY=input.KeyCode.Name
            if KEY=="W" then CONTROL.F=flySpeed
            elseif KEY=="S" then CONTROL.B=-flySpeed
            elseif KEY=="A" then CONTROL.L=-flySpeed
            elseif KEY=="D" then CONTROL.R=flySpeed
            elseif KEY=="E" then CONTROL.Q=flySpeed*2
            elseif KEY=="Q" then CONTROL.E=-flySpeed*2 end
            pcall(function() workspace.CurrentCamera.CameraType=Enum.CameraType.Track end)
        end
    end)
    flyKeyUp = IYMouse.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Keyboard then
            local KEY=input.KeyCode.Name
            if KEY=="W" then CONTROL.F=0
            elseif KEY=="S" then CONTROL.B=0
            elseif KEY=="A" then CONTROL.L=0
            elseif KEY=="D" then CONTROL.R=0
            elseif KEY=="E" then CONTROL.Q=0
            elseif KEY=="Q" then CONTROL.E=0 end
        end
    end)
    FLY()
end
local function NOFLY()
    FLYING=false
    if flyKeyDown then flyKeyDown:Disconnect() end
    if flyKeyUp then flyKeyUp:Disconnect() end
    if mfly1 then mfly1:Disconnect() end
    if mfly2 then mfly2:Disconnect() end
    local h = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid')
    if h then h.PlatformStand=false end
    pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
end
local function UnMobileFly()
    pcall(function()
        FLYING=false
        local root=Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        if root:FindFirstChild("BodyVelocity") then root.BodyVelocity:Destroy() end
        if root:FindFirstChild("BodyGyro") then root.BodyGyro:Destroy() end
        local h=Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        if h then h.PlatformStand=false end
        if mfly1 then mfly1:Disconnect() end
        if mfly2 then mfly2:Disconnect() end
    end)
end
local function MobileFly()
    UnMobileFly(); FLYING=true
    local root=Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local camera=workspace.CurrentCamera
    local v3none=Vector3.new(); local v3zero=Vector3.new(0,0,0); local v3inf=Vector3.new(9e9,9e9,9e9)
    local controlModule=require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    local bv=Instance.new("BodyVelocity"); bv.Name="BodyVelocity"; bv.Parent=root; bv.MaxForce=v3zero; bv.Velocity=v3zero
    local bg=Instance.new("BodyGyro"); bg.Name="BodyGyro"; bg.Parent=root; bg.MaxTorque=v3inf; bg.P=1000; bg.D=50
    mfly1=Players.LocalPlayer.CharacterAdded:Connect(function()
        local nr=Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        local nbv=Instance.new("BodyVelocity"); nbv.Name="BodyVelocity"; nbv.Parent=nr; nbv.MaxForce=v3zero; nbv.Velocity=v3zero
        local nbg=Instance.new("BodyGyro"); nbg.Name="BodyGyro"; nbg.Parent=nr; nbg.MaxTorque=v3inf; nbg.P=1000; nbg.D=50
    end)
    mfly2=RunService.RenderStepped:Connect(function()
        root=Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart"); camera=workspace.CurrentCamera
        local h=Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        if h and root and root:FindFirstChild("BodyVelocity") and root:FindFirstChild("BodyGyro") then
            local VH=root.BodyVelocity; local GH=root.BodyGyro
            VH.MaxForce=v3inf; GH.MaxTorque=v3inf; h.PlatformStand=true
            GH.CFrame=camera.CoordinateFrame; VH.Velocity=v3none
            local d=controlModule:GetMoveVector()
            if d.X ~= 0 then VH.Velocity = VH.Velocity + camera.CFrame.RightVector * (d.X*(flySpeed*50)) end
            if d.Z ~= 0 then VH.Velocity = VH.Velocity - camera.CFrame.LookVector * (d.Z*(flySpeed*50)) end
        end
    end)
end

Tabs.Fly:Section({ Title="Main", Icon="eye" })
Tabs.Fly:Slider({ Title="Fly Speed", Value={Min=1,Max=20,Default=1}, Callback=function(v) flySpeed=v end })
Tabs.Fly:Toggle({
    Title="Enable Fly", Value=false, Callback=function(state)
        flyToggle=state; if state then if UserInputService.TouchEnabled then MobileFly() else sFLY() end else NOFLY(); UnMobileFly() end
    end
})
-- Speed/Noclip/Inf Jump
local speed=16
local function setSpeed(val) local h=Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=val end end
Tabs.Fly:Slider({ Title="Speed", Value={Min=16,Max=150,Default=16}, Callback=function(v) speed=v end })
Tabs.Fly:Toggle({ Title="Enable Speed", Value=false, Callback=function(state) setSpeed(state and speed or 16) end })
local noclipConnection
Tabs.Fly:Toggle({ Title="Noclip", Value=false, Callback=function(state)
    if state then
        noclipConnection=RunService.Stepped:Connect(function()
            local char=Players.LocalPlayer.Character
            if char then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end end
        end)
    else if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end end
end })
local infJumpConnection
Tabs.Fly:Toggle({ Title="Inf Jump", Value=false, Callback=function(state)
    if state then
        infJumpConnection=UserInputService.JumpRequest:Connect(function()
            local char=Players.LocalPlayer.Character; local h=char and char:FindFirstChildOfClass("Humanoid"); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    else if infJumpConnection then infJumpConnection:Disconnect(); infJumpConnection=nil end end
end })

-- Quality of Life: Instant Open (Prompts)
Tabs.Fly:Section({ Title="Quality of Life", Icon="zap" })
local instantOpenEnabled=false
local promptRestore, promptAddedConn, promptRemovedConn, rescanLoop = {}, nil, nil, nil
local function applyInstantOpenToPrompt(pp) if pp and pp:IsA("ProximityPrompt") then if promptRestore[pp]==nil then promptRestore[pp]=pp.HoldDuration end pp.HoldDuration=0 end end
local function disableInstantOpen()
    if rescanLoop then rescanLoop=nil end
    if promptAddedConn then promptAddedConn:Disconnect() promptAddedConn=nil end
    if promptRemovedConn then promptRemovedConn:Disconnect() promptRemovedConn=nil end
    for pp,orig in pairs(promptRestore) do if pp and pp:IsA("ProximityPrompt") then pp.HoldDuration=orig end end
    promptRestore={}
end
local function enableInstantOpen()
    for _,o in ipairs(workspace:GetDescendants()) do if o:IsA("ProximityPrompt") then applyInstantOpenToPrompt(o) end end
    if not promptAddedConn then
        promptAddedConn=workspace.DescendantAdded:Connect(function(o) if instantOpenEnabled and o:IsA("ProximityPrompt") then applyInstantOpenToPrompt(o) end end)
    end
    if not promptRemovedConn then
        promptRemovedConn=workspace.DescendantRemoving:Connect(function(o) if o:IsA("ProximityPrompt") then promptRestore[o]=nil end end)
    end
    rescanLoop=task.spawn(function()
        while instantOpenEnabled do
            task.wait(0.5)
            for _,o in ipairs(workspace:GetDescendants()) do
                if o:IsA("ProximityPrompt") and (promptRestore[o]==nil or o.HoldDuration~=0) then
                    applyInstantOpenToPrompt(o)
                end
            end
        end
    end)
end
Tabs.Fly:Toggle({
    Title="Instant Open (Prompts)", Value=false, Callback=function(state)
        instantOpenEnabled=state; if state then enableInstantOpen() else disableInstantOpen() end
    end
})

-- =====================
-- ESP
-- =====================
local function createESPText(part, text, color)
    if part:FindFirstChild("ESPText") then return end
    local esp=Instance.new("BillboardGui")
    esp.Name="ESPText"; esp.Adornee=part; esp.Size=UDim2.new(0,100,0,20); esp.StudsOffset=Vector3.new(0,2.5,0); esp.AlwaysOnTop=true; esp.MaxDistance=300
    local label=Instance.new("TextLabel")
    label.Parent=esp; label.Size=UDim2.new(1,0,1,0); label.BackgroundTransparency=1; label.Text=text
    label.TextColor3=color or Color3.fromRGB(255,255,0); label.TextStrokeTransparency=0.2; label.TextScaled=true; label.Font=Enum.Font.GothamBold
    esp.Parent=part
end
local function Aesp(nome,tipo)
    local container,color = (tipo=="item" and workspace:FindFirstChild("Items") or workspace:FindFirstChild("Characters")),
                            (tipo=="item" and Color3.fromRGB(0,255,0) or Color3.fromRGB(255,255,0))
    if not container then return end
    for _,obj in ipairs(container:GetChildren()) do
        if obj.Name==nome then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then createESPText(part, obj.Name, color) end
        end
    end
end
local function Desp(nome,tipo)
    local container = (tipo=="item" and workspace:FindFirstChild("Items") or workspace:FindFirstChild("Characters"))
    if not container then return end
    for _,obj in ipairs(container:GetChildren()) do
        if obj.Name==nome then
            local part=obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then for _,gui in ipairs(part:GetChildren()) do if gui:IsA("BillboardGui") and gui.Name=="ESPText" then gui:Destroy() end end end
        end
    end
end

local ie = {
    "Bandage","Bolt","Broken Fan","Broken Microwave","Cake","Carrot","Chair","Coal","Coin Stack",
    "Cooked Morsel","Cooked Steak","Fuel Canister","Iron Body","Leather Armor","Log","MadKit","Metal Chair",
    "MedKit","Old Car Engine","Old Flashlight","Old Radio","Revolver","Revolver Ammo","Rifle","Rifle Ammo",
    "Morsel","Sheet Metal","Steak","Tyre","Washing Machine"
}
local me = {"Bunny","Wolf","Alpha Wolf","Bear","Cultist","Crossbow Cultist","Alien"}

local selectedItems, selectedMobs = {}, {}
local espItemsEnabled, espMobsEnabled = false, false
local espConnections = {}

Tabs.esp:Section({ Title="Esp Items", Icon="package" })
Tabs.esp:Dropdown({
    Title="Esp Items", Values=ie, Value={}, Multi=true, AllowNone=true,
    Callback=function(options)
        selectedItems=options
        if espItemsEnabled then for _,name in ipairs(ie) do if table.find(selectedItems,name) then Aesp(name,"item") else Desp(name,"item") end end
        else for _,name in ipairs(ie) do Desp(name,"item") end end
    end
})
Tabs.esp:Toggle({
    Title="Enable Esp", Value=false, Callback=function(state)
        espItemsEnabled=state
        for _,name in ipairs(ie) do if state and table.find(selectedItems,name) then Aesp(name,"item") else Desp(name,"item") end end
        if state and not espConnections.Items then
            local container=workspace:FindFirstChild("Items")
            if container then
                espConnections.Items=container.ChildAdded:Connect(function(obj)
                    if table.find(selectedItems, obj.Name) then
                        local part=obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                        if part then createESPText(part,obj.Name,Color3.fromRGB(0,255,0)) end
                    end
                end)
            end
        elseif not state and espConnections.Items then espConnections.Items:Disconnect(); espConnections.Items=nil end
    end
})

Tabs.esp:Section({ Title="Esp Entity", Icon="user" })
Tabs.esp:Dropdown({
    Title="Esp Entity", Values=me, Value={}, Multi=true, AllowNone=true,
    Callback=function(options)
        selectedMobs=options
        if espMobsEnabled then for _,name in ipairs(me) do if table.find(selectedMobs,name) then Aesp(name,"mob") else Desp(name,"mob") end end
        else for _,name in ipairs(me) do Desp(name,"mob") end end
    end
})
Tabs.esp:Toggle({
    Title="Enable Esp", Value=false, Callback=function(state)
        espMobsEnabled=state
        for _,name in ipairs(me) do if state and table.find(selectedMobs,name) then Aesp(name,"mob") else Desp(name,"mob") end end
        if state and not espConnections.Mobs then
            local container=workspace:FindFirstChild("Characters")
            if container then
                espConnections.Mobs=container.ChildAdded:Connect(function(obj)
                    if table.find(selectedMobs, obj.Name) then
                        local part=obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                        if part then createESPText(part,obj.Name,Color3.fromRGB(255,255,0)) end
                    end
                end)
            end
        elseif not state and espConnections.Mobs then espConnections.Mobs:Disconnect(); espConnections.Mobs=nil end
    end
})

-- =====================
-- Main: Misc (Deer stun)
-- =====================
Tabs.Main:Section({ Title="Misc", Icon="settings" })
local deerLoop=nil
Tabs.Main:Toggle({
    Title="Auto Stun Deer", Value=false, Callback=function(state)
        if state then
            deerLoop=RunService.RenderStepped:Connect(function()
                pcall(function()
                    local remote=RemoteEvents and RemoteEvents:FindFirstChild("DeerHitByTorch")
                    local deer=workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("Deer")
                    if remote and deer then remote:InvokeServer(deer) end
                end)
                task.wait(0.1)
            end)
        else if deerLoop then deerLoop:Disconnect(); deerLoop=nil end end
    end
})

-- =====================
-- Vision
-- =====================
Tabs.Vision:Section({ Title="Vision", Icon="eye" })
local originalParents={ Sky=nil, Bloom=nil, CampfireEffect=nil }
local function storeOriginalParents()
    local L=game:GetService("Lighting")
    local sky=L:FindFirstChild("Sky"); local bloom=L:FindFirstChild("Bloom"); local camp=L:FindFirstChild("CampfireEffect")
    if sky and not originalParents.Sky then originalParents.Sky=sky.Parent end
    if bloom and not originalParents.Bloom then originalParents.Bloom=bloom.Parent end
    if camp and not originalParents.CampfireEffect then originalParents.CampfireEffect=camp.Parent end
end
storeOriginalParents()
local originalColorCorrectionParent=nil
local function storeColorCorrectionParent()
    local L=game:GetService("Lighting"); local cc=L:FindFirstChild("ColorCorrection")
    if cc and not originalColorCorrectionParent then originalColorCorrectionParent=cc.Parent end
end
storeColorCorrectionParent()

Tabs.Vision:Toggle({
    Title="Disable Fog", Value=false, Callback=function(state)
        local L=game:GetService("Lighting")
        if state then
            local sky=L:FindFirstChild("Sky"); local bloom=L:FindFirstChild("Bloom"); local camp=L:FindFirstChild("CampfireEffect")
            if sky then sky.Parent=nil end; if bloom then bloom.Parent=nil end; if camp then camp.Parent=nil end
        else
            local sky=game:FindFirstChild("Sky",true); local bloom=game:FindFirstChild("Bloom",true); local camp=game:FindFirstChild("CampfireEffect",true)
            if not sky then sky=L:FindFirstChild("Sky") end; if not bloom then bloom=L:FindFirstChild("Bloom") end; if not camp then camp=L:FindFirstChild("CampfireEffect") end
            if sky then sky.Parent=originalParents.Sky or L end
            if bloom then bloom.Parent=originalParents.Bloom or L end
            if camp then camp.Parent=originalParents.CampfireEffect or L end
        end
    end
})

local originalLightingValues={ Brightness=nil, Ambient=nil, OutdoorAmbient=nil, ShadowSoftness=nil, GlobalShadows=nil, Technology=nil }
local function storeOriginalLighting()
    local L=game:GetService("Lighting")
    if not originalLightingValues.Brightness then
        originalLightingValues.Brightness=L.Brightness; originalLightingValues.Ambient=L.Ambient; originalLightingValues.OutdoorAmbient=L.OutdoorAmbient
        originalLightingValues.ShadowSoftness=L.ShadowSoftness; originalLightingValues.GlobalShadows=L.GlobalShadows; originalLightingValues.Technology=L.Technology
    end
end
storeOriginalLighting()

Tabs.Vision:Toggle({
    Title="Disable NightCampFire Effect", Value=false, Callback=function(state)
        local L=game:GetService("Lighting")
        if state then
            local cc=L:FindFirstChild("ColorCorrection")
            if cc then if not originalColorCorrectionParent then originalColorCorrectionParent=cc.Parent end; cc.Parent=nil end
        else
            local cc=L:FindFirstChild("ColorCorrection"); if not cc then cc=game:FindFirstChild("ColorCorrection",true) end
            if cc then cc.Parent=L end
        end
    end
})
Tabs.Vision:Toggle({
    Title="Fullbright", Value=false, Callback=function(state)
        local L=game:GetService("Lighting")
        if state then
            L.Brightness=2; L.Ambient=Color3.new(1,1,1); L.OutdoorAmbient=Color3.new(1,1,1); L.ShadowSoftness=0; L.GlobalShadows=false; L.Technology=Enum.Technology.Compatibility
        else
            L.Brightness=originalLightingValues.Brightness; L.Ambient=originalLightingValues.Ambient
            L.OutdoorAmbient=originalLightingValues.OutdoorAmbient; L.ShadowSoftness=originalLightingValues.ShadowSoftness
            L.GlobalShadows=originalLightingValues.GlobalShadows; L.Technology=originalLightingValues.Technology
        end
    end
})
