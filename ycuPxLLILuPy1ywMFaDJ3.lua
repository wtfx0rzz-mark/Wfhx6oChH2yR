--[[ 
    99 Nights in the Forest | Baseline (Edited, Aura-Speed Variant)
    Changes in this version:
    - Kill aura & chop aura sped up and parallelized:
        • Kill aura: parallel InvokeServer per target, per wave.
        • Chop aura: single global wave (no per-tree inner loops), robust impact CFrame.
        • Tunables: AURA_SWING_DELAY and CHOP_SWING_DELAY.
    - Keeps the rest of your baseline features/UI intact.
]]

repeat task.wait() until game:IsLoaded()

-- =====================
-- Tunables
-- =====================
local AURA_SWING_DELAY = 0.55
local CHOP_SWING_DELAY = 0.50
local TREE_NAME        = "Small Tree"
local UID_SUFFIX       = "0000000000"

-- UI + Services
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local EquipItemHandle = RemoteEvents:WaitForChild("EquipItemHandle")
local UnequipItemHandle = RemoteEvents:FindFirstChild("UnequipItemHandle")
local ToolDamageObject = RemoteEvents:WaitForChild("ToolDamageObject")

-- =====================
-- Themes
-- =====================
WindUI:AddTheme({ Name = "Dark",   Accent = "#18181b", Dialog = "#18181b", Outline = "#FFFFFF", Text = "#FFFFFF", Placeholder = "#999999", Background = "#0e0e10", Button = "#52525b", Icon = "#a1a1aa" })
WindUI:AddTheme({ Name = "Light",  Accent = "#f4f4f5", Dialog = "#f4f4f5", Outline = "#000000", Text = "#000000", Placeholder = "#666666", Background = "#ffffff", Button = "#e4e4e7", Icon = "#52525b" })
WindUI:AddTheme({ Name = "Gray",   Accent = "#374151", Dialog = "#374151", Outline = "#d1d5db", Text = "#f9fafb", Placeholder = "#9ca3af", Background = "#1f2937", Button = "#4b5563", Icon = "#d1d5db" })
WindUI:AddTheme({ Name = "Blue",   Accent = "#1e40af", Dialog = "#1e3a8a", Outline = "#93c5fd", Text = "#f0f9ff", Placeholder = "#60a5fa", Background = "#1e293b", Button = "#3b82f6", Icon = "#93c5fd" })
WindUI:AddTheme({ Name = "Green",  Accent = "#059669", Dialog = "#047857", Outline = "#6ee7b7", Text = "#ecfdf5", Placeholder = "#34d399", Background = "#064e3b", Button = "#10b981", Icon = "#6ee7b7" })
WindUI:AddTheme({ Name = "Purple", Accent = "#7c3aed", Dialog = "#6d28d9", Outline = "#c4b5fd", Text = "#faf5ff", Placeholder = "#a78bfa", Background = "#581c87", Button = "#8b5cf6", Icon = "#c4b5fd" })

WindUI:SetNotificationLower(true)

local themes = {"Dark", "Light", "Gray", "Blue", "Green", "Purple"}
local currentThemeIndex = 1

if not getgenv().TransparencyEnabled then
    getgenv().TransparencyEnabled = false
end

-- =====================
-- Combat state
-- =====================
local killAuraToggle = false
local chopAuraToggle = false
local auraRadius = 50
local currentammount = 0

local _hitCounter = 0
local function nextHitId()
    _hitCounter += 1
    return tostring(_hitCounter) .. "_" .. UID_SUFFIX
end

local toolsDamageIDs = {
    ["Old Axe"]    = "3_7367831688",
    ["Good Axe"]   = "112_7367831688",
    ["Strong Axe"] = "116_7367831688",
    ["Chainsaw"]   = "647_8992824875",
    ["Spear"]      = "196_8999010016"
}

-- =====================
-- Auto Food
-- =====================
local autoFeedToggle = false
local selectedFood = {}
local hungerThreshold = 75
local alwaysFeedEnabledItems = {}
local alimentos = { "Apple","Berry","Carrot","Cake","Chili","Cooked Morsel","Cooked Steak" }

-- =====================
-- ESP lists
-- =====================
local ie = {
    "Bandage","Bolt","Broken Fan","Broken Microwave","Cake","Carrot","Chair","Coal","Coin Stack",
    "Cooked Morsel","Cooked Steak","Fuel Canister","Iron Body","Leather Armor","Log","MadKit","Metal Chair",
    "MedKit","Old Car Engine","Old Flashlight","Old Radio","Revolver","Revolver Ammo","Rifle","Rifle Ammo",
    "Morsel","Sheet Metal","Steak","Tyre","Washing Machine"
}
local me = {"Bunny","Wolf","Alpha Wolf","Bear","Cultist","Crossbow Cultist","Alien"}

-- =====================
-- Bring categories
-- =====================
local junkItems = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
local selectedJunkItems = {}

local fuelItems = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
local selectedFuelItems = {}

local foodItems = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
local selectedFoodItems = {}

local medicalItems = {"Bandage","MedKit"}
local selectedMedicalItems = {}

local equipmentItems = {"Revolver","Rifle","Leather Body","Iron Body","Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Strong Axe","Good Axe"}
local selectedEquipmentItems = {}

-- Bring helper
local BRING_INNER_RADIUS = 7
local BRING_MAX_RADIUS   = 2000
local BRING_BATCH_SIZE   = 40

local function isInsideSafeRing(hrpPos, partPos, innerRadius)
    return (partPos - hrpPos).Magnitude <= innerRadius
end

local function toLowerSet(list)
    local set = {}
    for _, n in ipairs(list or {}) do
        if type(n) == "string" then
            set[string.lower(n)] = true
        end
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

local function ringDropPosition(hrpPos, innerRadius)
    local r = math.max(2, innerRadius - 1)
    local theta = math.random() * math.pi * 2
    local x = hrpPos.X + math.cos(theta) * r
    local z = hrpPos.Z + math.sin(theta) * r
    local y = hrpPos.Y + 2.5
    return Vector3.new(x, y, z)
end

function bringItemsSmart(nameList, innerRadius, maxRadius, batchSize)
    local player = game.Players.LocalPlayer
    local char = player and player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    innerRadius = tonumber(innerRadius) or BRING_INNER_RADIUS
    maxRadius   = tonumber(maxRadius)   or BRING_MAX_RADIUS
    batchSize   = math.max(1, tonumber(batchSize) or BRING_BATCH_SIZE)

    local wanted = toLowerSet(nameList)
    if next(wanted) == nil then return end

    local hrpPos = hrp.Position
    local itemsFolder = workspace:FindFirstChild("Items")
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

    table.sort(candidates, function(a, b) return a.dist > b.dist end)

    local moved = 0
    for i = 1, math.min(batchSize, #candidates) do
        local entry = candidates[i]
        local model = entry.model
        local part  = entry.part
        if not part or not part.Parent or not part:IsDescendantOf(itemsFolder) then
            continue
        end
        if isInsideSafeRing(hrpPos, part.Position, innerRadius) then
            continue
        end

        local dropPos = ringDropPosition(hrpPos, innerRadius)
        pcall(function()
            if model:IsA("Model") and model.PrimaryPart then
                model:PivotTo(CFrame.new(dropPos))
            else
                part.CFrame = CFrame.new(dropPos)
            end

            if model:IsA("Model") then
                for _, sub in ipairs(model:GetDescendants()) do
                    if sub:IsA("BasePart") then
                        sub.Anchored = false
                        sub.CanCollide = true
                        sub:SetNetworkOwner(player)
                        sub.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                        sub.AssemblyLinearVelocity  = Vector3.new(0, -5, 0)
                        if sub.Massless then sub.Massless = false end
                    end
                end
            else
                part.Anchored = false
                part.CanCollide = true
                part:SetNetworkOwner(player)
                part.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                part.AssemblyLinearVelocity  = Vector3.new(0, -5, 0)
                if part.Massless then part.Massless = false end
            end
        end)

        moved = moved + 1
    end
end

local junkToggleEnabled = false
local fuelToggleEnabled = false
local foodToggleEnabled = false
local medicalToggleEnabled = false
local equipmentToggleEnabled = false

-- =====================
-- Utility
-- =====================
local function getAnyToolWithDamageID(isChopAura)
    for toolName, damageID in pairs(toolsDamageIDs) do
        if isChopAura and (toolName ~= "Old Axe" and toolName ~= "Good Axe" and toolName ~= "Strong Axe" and toolName ~= "Chainsaw") then
            continue
        end
        local inv = LocalPlayer:FindFirstChild("Inventory")
        local tool = inv and inv:FindFirstChild(toolName)
        if tool then
            return tool, damageID, toolName
        end
    end
    return nil, nil, nil
end

local function equipTool(tool)
    if tool then
        pcall(function()
            EquipItemHandle:FireServer("FireAllClients", tool)
        end)
    end
end

local function unequipTool(tool)
    if tool and UnequipItemHandle then
        pcall(function()
            UnequipItemHandle:FireServer("FireAllClients", tool)
        end)
    end
end

-- =====================
-- Impact CFrame for trees
-- =====================
local function bestTreeHitPart(tree: Instance)
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

local SYN_OFFSET = 1.0
local SYN_DEPTH  = 4.0
local function computeImpactCFrame(model, hitPart)
    if not (model and hitPart and hitPart:IsA("BasePart")) then
        return hitPart and CFrame.new(hitPart.Position) or CFrame.new()
    end
    local outward = hitPart.CFrame.LookVector.Unit
    local origin  = hitPart.Position + outward * SYN_OFFSET
    local dir     = -outward * (SYN_OFFSET + SYN_DEPTH)

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {model}

    local rc = Workspace:Raycast(origin, dir, params)
    local pos
    if rc then
        pos = rc.Position + rc.Normal * 0.02
    else
        pos = origin + dir * 0.6
    end

    local rot = hitPart.CFrame - hitPart.CFrame.Position
    return CFrame.new(pos) * rot
end

-- =====================
-- Kill Aura
-- =====================
local function killAuraLoop()
    while killAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local tool, damageID = getAnyToolWithDamageID(false)
            if tool and damageID then
                equipTool(tool)
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
                                        ToolDamageObject:InvokeServer(
                                            mob,
                                            tool,
                                            damageID,
                                            CFrame.new(part.Position)
                                        )
                                    end)
                                end)
                            end
                        end
                    end
                end
                task.wait(AURA_SWING_DELAY)
            else
                task.wait(0.5)
            end
        else
            task.wait(0.25)
        end
    end
end

-- =====================
-- Chop Aura
-- =====================
local function chopAuraLoop()
    while chopAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local tool = select(1, getAnyToolWithDamageID(true))
            if tool then
                equipTool(tool)

                local trees = {}
                local origin = hrp.Position
                local map = Workspace:FindFirstChild("Map")
                local function scanFolder(folder)
                    if not folder then return end
                    for _, obj in ipairs(folder:GetChildren()) do
                        if obj:IsA("Model") and obj.Name == TREE_NAME then
                            local part = bestTreeHitPart(obj) or obj:FindFirstChild("Trunk")
                            if part and (part.Position - origin).Magnitude <= auraRadius then
                                table.insert(trees, obj)
                            end
                        end
                    end
                end
                if map then
                    scanFolder(map:FindFirstChild("Foliage"))
                    scanFolder(map:FindFirstChild("Landmarks"))
                end

                for _, tree in ipairs(trees) do
                    if not chopAuraToggle then break end
                    task.spawn(function()
                        local hitPart = bestTreeHitPart(tree)
                        if hitPart then
                            local impactCF = computeImpactCFrame(tree, hitPart)
                            local hitId = nextHitId()
                            pcall(function()
                                ToolDamageObject:InvokeServer(
                                    tree,
                                    tool,
                                    hitId,
                                    impactCF
                                )
                            end)
                        end
                    end)
                end

                task.wait(CHOP_SWING_DELAY)
            else
                task.wait(0.5)
            end
        else
            task.wait(0.25)
        end
    end
end

-- =====================
-- Auto Feed helpers
-- =====================
local function firstSelectedFoodName()
    if type(selectedFood) == "table" then
        -- WindUI Multi dropdown returns table of names or map; handle both
        local any
        for k,v in pairs(selectedFood) do
            if typeof(k) == "string" and (v == true or v == 1) then
                return k
            end
            if typeof(v) == "string" then any = v end
        end
        return any or alimentos[1]
    elseif type(selectedFood) == "string" then
        return selectedFood
    end
    return alimentos[1]
end

local function wiki(nome)
    local c = 0
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then return 0 end
    for _, i in ipairs(itemsFolder:GetChildren()) do
        if i.Name == nome then
            c += 1
        end
    end
    return c
end

local function ghn()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return 100 end
    local ok, scale = pcall(function()
        return gui.Interface.StatBars.HungerBar.Bar.Size.X.Scale
    end)
    if ok and type(scale) == "number" then
        return math.floor(scale * 100)
    end
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

local function notifeed()
    WindUI:Notify({
        Title = "Auto Food Paused",
        Content = "The food is gone",
        Duration = 3
    })
end

-- =====================
-- Chest & Child helpers
-- =====================
local function getChests()
    local chests = {}
    local chestNames = {}
    local index = 1
    local items = Workspace:WaitForChild("Items")
    for _, item in ipairs(items:GetChildren()) do
        if item.Name:match("^Item Chest") and not item:GetAttribute("8721081708ed") then
            table.insert(chests, item)
            table.insert(chestNames, "Chest " .. index)
            index += 1
        end
    end
    return chests, chestNames
end
local currentChests, currentChestNames = getChests()
local selectedChest = currentChestNames[1] or nil

local function getMobs()
    local mobs = {}
    local mobNames = {}
    local index = 1
    local chars = Workspace:WaitForChild("Characters")
    for _, character in ipairs(chars:GetChildren()) do
        if character.Name:match("^Lost Child") and character:GetAttribute("Lost") == true then
            table.insert(mobs, character)
            table.insert(mobNames, character.Name)
            index += 1
        end
    end
    return mobs, mobNames
end
local currentMobs, currentMobNames = getMobs()
local selectedMob = currentMobNames[1] or nil

-- =====================
-- Teleports
-- =====================
function tp1()
	(game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart").CFrame =
CFrame.new(0.43132782, 15.77634621, -1.88620758, -0.270917892, 0.102997094, 0.957076371, 0.639657021, 0.762253821, 0.0990355015, -0.719334781, 0.639031112, -0.272391081)
end

local function tp2()
    local targetPart = workspace:FindFirstChild("Map")
        and workspace.Map:FindFirstChild("Landmarks")
        and workspace.Map.Landmarks:FindFirstChild("Stronghold")
        and workspace.Map.Landmarks.Stronghold:FindFirstChild("Functional")
        and workspace.Map.Landmarks.Stronghold.Functional:FindFirstChild("EntryDoors")
        and workspace.Map.Landmarks.Stronghold.Functional.EntryDoors:FindFirstChild("DoorRight")
        and workspace.Map.Landmarks.Stronghold.Functional.EntryDoors.DoorRight:FindFirstChild("Model")
    if targetPart then
        local children = targetPart:GetChildren()
        local destination = children[5]
        if destination and destination:IsA("BasePart") then
            local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.CFrame = destination.CFrame + Vector3.new(0, 5, 0)
            end
        end
    end
end

-- =====================
-- Window & Tabs
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
            currentThemeIndex = currentThemeIndex + 1
            if currentThemeIndex > #themes then currentThemeIndex = 1 end
            local newTheme = themes[currentThemeIndex]
            WindUI:SetTheme(newTheme)
            WindUI:Notify({ Title = "Theme Changed", Content = "Switched to " .. newTheme .. " theme!", Duration = 2, Icon = "palette" })
            print("Switched to " .. newTheme .. " theme")
        end,
    },
})
Window:SetToggleKey(Enum.KeyCode.V)

pcall(function()
    Window:CreateTopbarButton("TransparencyToggle", "eye", function()
        if getgenv().TransparencyEnabled then
            getgenv().TransparencyEnabled = false
            pcall(function() Window:ToggleTransparency(false) end)
            WindUI:Notify({ Title = "Transparency", Content = "Transparency disabled", Duration = 3, Icon = "eye" })
            print("Transparency = false")
        else
            getgenv().TransparencyEnabled = true
            pcall(function() Window:ToggleTransparency(true) end)
            WindUI:Notify({ Title = "Transparency", Content = "Transparency enabled", Duration = 3, Icon = "eye-off" })
            print("Transparency = true")
        end
        print("Debug - Current Transparency state:", getgenv().TransparencyEnabled)
    end, 990)
end)

Window:EditOpenButton({
    Title = "Toggle",
    Icon = "zap",
    CornerRadius = UDim.new(0, 6),
    StrokeThickness = 2,
    Color = ColorSequence.new(Color3.fromRGB(138, 43, 226), Color3.fromRGB(173, 216, 230)),
    Draggable = true,
})

local Tabs = {}
Tabs.Combat = Window:Tab({ Title = "Combat", Icon = "sword", Desc = "x" })
Tabs.Main   = Window:Tab({ Title = "Main",   Icon = "align-left", Desc = "x" })
Tabs.esp    = Window:Tab({ Title = "Esp",    Icon = "sparkles", Desc = "x" })
Tabs.br     = Window:Tab({ Title = "Bring",  Icon = "package",  Desc = "x" })
Tabs.Tp     = Window:Tab({ Title = "Teleport", Icon = "map",    Desc = "x" })
Tabs.Fly    = Window:Tab({ Title = "Player", Icon = "user",     Desc = "x" })
Tabs.Vision = Window:Tab({ Title = "Environment", Icon = "eye", Desc = "x" })

Window:SelectTab(1)

-- =====================
-- Combat UI
-- =====================
Tabs.Combat:Section({ Title = "Aura", Icon = "star" })

Tabs.Combat:Toggle({
    Title = "Kill Aura",
    Value = false,
    Callback = function(state)
        killAuraToggle = state
        if state then
            task.spawn(killAuraLoop)
        else
            local tool = select(1, getAnyToolWithDamageID(false))
            unequipTool(tool)
        end
    end
})

Tabs.Combat:Toggle({
    Title = "Chop Aura",
    Value = false,
    Callback = function(state)
        chopAuraToggle = state
        if state then
            task.spawn(chopAuraLoop)
        else
            local tool = select(1, getAnyToolWithDamageID(true))
            unequipTool(tool)
        end
    end
})

Tabs.Combat:Section({ Title = "Settings", Icon = "settings" })
Tabs.Combat:Slider({
    Title = "Aura Radius",
    Value = { Min = 50, Max = 2000, Default = 50 },
    Callback = function(value)
        auraRadius = math.clamp(value, 10, 2000)
    end
})

-- =====================
-- Main UI (Auto Feed)
-- =====================
Tabs.Main:Section({ Title = "Auto Feed", Icon = "utensils" })

Tabs.Main:Dropdown({
    Title = "Select Food",
    Desc = "Choose the food",
    Values = alimentos,
    Value = selectedFood,
    Multi = true,
    Callback = function(value)
        selectedFood = value
    end
})

Tabs.Main:Input({
    Title = "Feed %",
    Desc = "Eat when hunger reaches this %",
    Value = tostring(hungerThreshold),
    Placeholder = "Ex: 75",
    Numeric = true,
    Callback = function(value)
        local n = tonumber(value)
        if n then hungerThreshold = math.clamp(n, 0, 100) end
    end
})

Tabs.Main:Toggle({
    Title = "Auto Feed",
    Value = false,
    Callback = function(state)
        autoFeedToggle = state
        if state then
            task.spawn(function()
                while autoFeedToggle do
                    task.wait(0.1)
                    local fname = firstSelectedFoodName()
                    if wiki(fname) == 0 then
                        autoFeedToggle = false
                        pcall(function()
                            local ctrl = Tabs.Main:Find("Auto Feed")
                            if ctrl and ctrl.SetValue then ctrl:SetValue(false) end
                        end)
                        notifeed()
                        break
                    end
                    if ghn() <= hungerThreshold then
                        feed(fname)
                    end
                end
            end)
        end
    end
})

-- =====================
-- Teleport UI
-- =====================
Tabs.Tp:Section({ Title = "Teleport", Icon = "map" })
Tabs.Tp:Button({ Title = "Teleport to Campfire", Locked = false, Callback = function() tp1() end })
Tabs.Tp:Button({ Title = "Teleport to Stronghold", Locked = false, Callback = function() tp2() end })

Tabs.Tp:Section({ Title = "Children", Icon = "eye" })
local MobDropdown = Tabs.Tp:Dropdown({
    Title = "Select Child",
    Values = currentMobNames,
    Multi = false,
    AllowNone = true,
    Callback = function(options)
        selectedMob = options[#options] or currentMobNames[1] or nil
    end
})

Tabs.Tp:Button({
    Title = "Refresh List",
    Locked = false,
    Callback = function()
        currentMobs, currentMobNames = getMobs()
        if #currentMobNames > 0 then
            selectedMob = currentMobNames[1]
            MobDropdown:Refresh(currentMobNames)
        else
            selectedMob = nil
            MobDropdown:Refresh({ "No child found" })
        end
    end
})

Tabs.Tp:Button({
    Title = "Teleport to Child",
    Locked = false,
    Callback = function()
        if selectedMob and currentMobs then
            for i, name in ipairs(currentMobNames) do
                if name == selectedMob then
                    local targetMob = currentMobs[i]
                    if targetMob then
                        local part = targetMob.PrimaryPart or targetMob:FindFirstChildWhichIsA("BasePart")
                        local hrp = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if part and hrp then
                            hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
                        end
                    end
                    break
                end
            end
        end
    end
})

-- =====================
-- Bring UI (simple toggles)
-- =====================
Tabs.br:Section({ Title = "Bring (safe ring)", Icon = "package" })
Tabs.br:Toggle({
    Title = "Bring Junk",
    Value = false,
    Callback = function(state)
        junkToggleEnabled = state
        if state then
            task.spawn(function()
                while junkToggleEnabled do
                    bringItemsSmart(junkItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    task.wait(0.75)
                end
            end)
        end
    end
})
Tabs.br:Toggle({
    Title = "Bring Fuel",
    Value = false,
    Callback = function(state)
        fuelToggleEnabled = state
        if state then
            task.spawn(function()
                while fuelToggleEnabled do
                    bringItemsSmart(fuelItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    task.wait(0.75)
                end
            end)
        end
    end
})
Tabs.br:Toggle({
    Title = "Bring Food",
    Value = false,
    Callback = function(state)
        foodToggleEnabled = state
        if state then
            task.spawn(function()
                while foodToggleEnabled do
                    bringItemsSmart(foodItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    task.wait(0.75)
                end
            end)
        end
    end
})
Tabs.br:Toggle({
    Title = "Bring Medical",
    Value = false,
    Callback = function(state)
        medicalToggleEnabled = state
        if state then
            task.spawn(function()
                while medicalToggleEnabled do
                    bringItemsSmart(medicalItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    task.wait(0.75)
                end
            end)
        end
    end
})
Tabs.br:Toggle({
    Title = "Bring Equipment",
    Value = false,
    Callback = function(state)
        equipmentToggleEnabled = state
        if state then
            task.spawn(function()
                while equipmentToggleEnabled do
                    bringItemsSmart(equipmentItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    task.wait(0.75)
                end
            end)
        end
    end
})

-- =====================
-- Minimal placeholders for other tabs to avoid nil
-- =====================
Tabs.esp:Section({ Title = "ESP", Icon = "sparkles" })
Tabs.Fly:Section({ Title = "Player", Icon = "user" })
Tabs.Vision:Section({ Title = "Environment", Icon = "eye" })
