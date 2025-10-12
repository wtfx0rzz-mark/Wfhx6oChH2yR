--[[ 
    99 Nights in the Forest | Baseline (Edited, Aura-Speed Variant)
    Changes in this version:
    - Kill aura & chop aura sped up and parallelized:
        • Kill aura: parallel InvokeServer per target, per wave.
        • Chop aura: single global wave (no per-tree inner loops), robust impact CFrame.
        • Tunables: AURA_SWING_DELAY and CHOP_SWING_DELAY.
    - Keeps the rest of your baseline features/UI intact.
]]

-- Wait for game
repeat task.wait() until game:IsLoaded()

-- =====================
-- Tunables (new)
-- =====================
local AURA_SWING_DELAY = 0.55   -- time between kill-aura waves (lower = faster; be mindful of server limits)
local CHOP_SWING_DELAY = 0.50   -- time between chop-aura waves (lower = faster; 0.10–0.15 is a sweet spot)
local TREE_NAME        = "Small Tree"
local UID_SUFFIX       = "0000000000" -- matches your original suffix pattern for tree hit IDs

-- UI + Services
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

-- Shortcuts to remotes (avoid repeated WaitForChild)
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local EquipItemHandle = RemoteEvents:WaitForChild("EquipItemHandle")
local UnequipItemHandle = RemoteEvents:FindFirstChild("UnequipItemHandle")
local ToolDamageObject = RemoteEvents:WaitForChild("ToolDamageObject")

-- =====================
-- Themes (unchanged)
-- =====================
WindUI:AddTheme({
    Name = "Dark",
    Accent = "#18181b",
    Dialog = "#18181b", 
    Outline = "#FFFFFF",
    Text = "#FFFFFF",
    Placeholder = "#999999",
    Background = "#0e0e10",
    Button = "#52525b",
    Icon = "#a1a1aa",
})
WindUI:AddTheme({
    Name = "Light",
    Accent = "#f4f4f5",
    Dialog = "#f4f4f5",
    Outline = "#000000", 
    Text = "#000000",
    Placeholder = "#666666",
    Background = "#ffffff",
    Button = "#e4e4e7",
    Icon = "#52525b",
})
WindUI:AddTheme({
    Name = "Gray",
    Accent = "#374151",
    Dialog = "#374151",
    Outline = "#d1d5db", 
    Text = "#f9fafb",
    Placeholder = "#9ca3af",
    Background = "#1f2937",
    Button = "#4b5563",
    Icon = "#d1d5db",
})
WindUI:AddTheme({
    Name = "Blue",
    Accent = "#1e40af",
    Dialog = "#1e3a8a",
    Outline = "#93c5fd", 
    Text = "#f0f9ff",
    Placeholder = "#60a5fa",
    Background = "#1e293b",
    Button = "#3b82f6",
    Icon = "#93c5fd",
})
WindUI:AddTheme({
    Name = "Green",
    Accent = "#059669",
    Dialog = "#047857",
    Outline = "#6ee7b7", 
    Text = "#ecfdf5",
    Placeholder = "#34d399",
    Background = "#064e3b",
    Button = "#10b981",
    Icon = "#6ee7b7",
})
WindUI:AddTheme({
    Name = "Purple",
    Accent = "#7c3aed",
    Dialog = "#6d28d9",
    Outline = "#c4b5fd", 
    Text = "#faf5ff",
    Placeholder = "#a78bfa",
    Background = "#581c87",
    Button = "#8b5cf6",
    Icon = "#c4b5fd",
})

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
local currentammount = 0   -- kept for compatibility (unused by new tree hitId)

-- simple unique hit id for trees
local _hitCounter = 0
local function nextHitId()
    _hitCounter += 1
    return tostring(_hitCounter) .. "_" .. UID_SUFFIX
end

local toolsDamageIDs = {
    ["Old Axe"]   = "3_7367831688",
    ["Good Axe"]  = "112_7367831688",
    ["Strong Axe"]= "116_7367831688",
    ["Chainsaw"]  = "647_8992824875",
    ["Spear"]     = "196_8999010016"
}

-- =====================
-- Auto Food (unchanged logic/UI)
-- =====================
local autoFeedToggle = false
local selectedFood = {}
local hungerThreshold = 75
local alwaysFeedEnabledItems = {}
local alimentos = {
    "Apple",
    "Berry",
    "Carrot",
    "Cake",
    "Chili",
    "Cooked Morsel",
    "Cooked Steak"
}

-- =====================
-- ESP lists (unchanged)
-- =====================
local ie = {
    "Bandage", "Bolt", "Broken Fan", "Broken Microwave", "Cake", "Carrot", "Chair", "Coal", "Coin Stack",
    "Cooked Morsel", "Cooked Steak", "Fuel Canister", "Iron Body", "Leather Armor", "Log", "MadKit", "Metal Chair",
    "MedKit", "Old Car Engine", "Old Flashlight", "Old Radio", "Revolver", "Revolver Ammo", "Rifle", "Rifle Ammo",
    "Morsel", "Sheet Metal", "Steak", "Tyre", "Washing Machine"
}
local me = {"Bunny", "Wolf", "Alpha Wolf", "Bear", "Cultist", "Crossbow Cultist", "Alien"}

-- =====================
-- Bring categories (UI-facing names unchanged but "Medicine" -> "Medical")
-- =====================
local junkItems = {"Tyre", "Bolt", "Broken Fan", "Broken Microwave", "Sheet Metal", "Old Radio", "Washing Machine", "Old Car Engine"}
local selectedJunkItems = {}

local fuelItems = {"Log", "Chair", "Coal", "Fuel Canister", "Oil Barrel"}
local selectedFuelItems = {}

local foodItems = {"Cake", "Cooked Steak", "Cooked Morsel", "Steak", "Morsel", "Berry", "Carrot"}
local selectedFoodItems = {}

local medicalItems = {"Bandage", "MedKit"} -- renamed UI section to "Medical" below
local selectedMedicalItems = {}

local equipmentItems = {"Revolver", "Rifle", "Leather Body", "Iron Body", "Revolver Ammo", "Rifle Ammo", "Giant Sack", "Good Sack", "Strong Axe", "Good Axe"}
local selectedEquipmentItems = {}

-- === Smarter “Bring” helper (safe-zone, capped batch, physics settle) ===
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

    -- CHANGED: sort farthest → closest
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
-- Utility from baseline (used by other features)
-- =====================
local function getAnyToolWithDamageID(isChopAura)
    for toolName, damageID in pairs(toolsDamageIDs) do
        if isChopAura and toolName ~= "Old Axe" and toolName ~= "Good Axe" and toolName ~= "Strong Axe" and toolName ~= "Chainsaw" then
            -- allow Chainsaw for chopping too (fastest) — retained tool filter but included Chainsaw
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
-- Impact CFrame helper for trees (more reliable server hits)
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
-- Kill Aura (parallel wave)
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
                                            damageID,                 -- keep using your weapon-specific ID for NPCs
                                            CFrame.new(part.Position) -- simple, valid impact
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
-- Chop Aura (global parallel wave; no per-tree inner loop)
-- =====================
local function chopAuraLoop()
    while chopAuraToggle do
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local tool, _damageIdMaybe, toolName = getAnyToolWithDamageID(true)
            if tool then
                equipTool(tool)

                -- Collect trees in range
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

                -- Parallel wave: one hit per tree per wave
                for _, tree in ipairs(trees) do
                    if not chopAuraToggle then break end
                    task.spawn(function()
                        local hitPart = bestTreeHitPart(tree)
                        if hitPart then
                            local impactCF = computeImpactCFrame(tree, hitPart)
                            local hitId = nextHitId() -- "N_0000000000"
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

-- Helpers used by Auto Feed UI (still present)
local function wiki(nome)
    local c = 0
    local itemsFolder = Workspace:FindFirstChild("Items")
    if not itemsFolder then return 0 end
    for _, i in ipairs(itemsFolder:GetChildren()) do
        if i.Name == nome then
            c = c + 1
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
-- Chest & Child helpers (used by Teleport UI)
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
            index = index + 1
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
            index = index + 1
        end
    end
    return mobs, mobNames
end
local currentMobs, currentMobNames = getMobs()
local selectedMob = currentMobNames[1] or nil

-- =====================
-- Teleports (unchanged)
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
-- Window & Tabs (without Auto/Info)
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
            if currentThemeIndex > #themes then
                currentThemeIndex = 1
            end
            local newTheme = themes[currentThemeIndex]
            WindUI:SetTheme(newTheme)
            WindUI:Notify({
                Title = "Theme Changed",
                Content = "Switched to " .. newTheme .. " theme!",
                Duration = 2,
                Icon = "palette"
            })
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

-- Select a safe existing tab index (1 = Combat)
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
            local tool, _ = getAnyToolWithDamageID(false)
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
            local tool, _ = getAnyToolWithDamageID(true)
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
        if n then
            hungerThreshold = math.clamp(n, 0, 100)
        end
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
                    task.wait(0.075)
                    if wiki(selectedFood) == 0 then
                        autoFeedToggle = false
                        Tabs.Combat:Find("Auto Feed"):SetValue(false)
                        notifeed()
                        break
                    end
                    if ghn() <= hungerThreshold then
                        feed(selectedFood)
                    end
                end
            end)
        end
    end
})

-- =====================
-- Teleport UI (unchanged)
-- =====================
Tabs.Tp:Section({ Title = "Teleport", Icon = "map" })

Tabs.Tp:Button({
    Title = "Teleport to Campfire",
    Locked = false,
    Callback = function() tp1() end
})

Tabs.Tp:Button({
    Title = "Teleport to Stronghold",
    Locked = false,
    Callback = function() tp2() end
})

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
                        if part and game.Players.LocalPlayer.Character then
                            local hrp = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            if hrp then
                                hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
                            end
                        end
                    end
                    break
                end
            end
        end
    end
})

Tabs.Tp:Section({ Title = "Chest", Icon = "box" })
local ChestDropdown = Tabs.Tp:Dropdown({
    Title = "Select Chest",
    Values = currentChestNames,
    Multi = false,
    AllowNone = true,
    Callback = function(options)
        selectedChest = options[#options] or currentChestNames[1] or nil
    end
})

Tabs.Tp:Button({
    Title = "Refresh List",
    Locked = false,
    Callback = function()
        currentChests, currentChestNames = getChests()
        if #currentChestNames > 0 then
            selectedChest = currentChestNames[1]
            ChestDropdown:Refresh(currentChestNames)
        else
            selectedChest = nil
            ChestDropdown:Refresh({ "No chests found" })
        end
    end
})

Tabs.Tp:Button({
    Title = "Teleport to Chest",
    Locked = false,
    Callback = function()
        if selectedChest and currentChests then
            local chestIndex = 1
            for i, name in ipairs(currentChestNames) do
                if name == selectedChest then
                    chestIndex = i
                    break
                end
            end
            local targetChest = currentChests[chestIndex]
            if targetChest then
                local part = targetChest.PrimaryPart or targetChest:FindFirstChildWhichIsA("BasePart")
                if part and game.Players.LocalPlayer.Character then
                    local hrp = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        hrp.CFrame = part.CFrame + Vector3.new(0, 5, 0)
                    end
                end
            end
        end
    end
})

-- =====================
-- BRING: donor-style bring implementation (fixed)
-- =====================

-- cooldown map so recently moved items are not re-picked immediately
local recentlyMoved = {}               -- [Instance] = lastTick
local COOLDOWN_SEC = 1.25              -- time before re-pick is allowed
local DROP_Y_OFFSET = 1.5              -- spawn a bit above ground for a visible drop
local NUDGE = Vector3.new(0, -5, 0)    -- slight downward velocity

local function moveItemOnce(modelOrPart, dropCF)
    local parts = {}
    if modelOrPart:IsA("Model") then
        modelOrPart:PivotTo(dropCF)
        for _, sub in ipairs(modelOrPart:GetDescendants()) do
            if sub:IsA("BasePart") then table.insert(parts, sub) end
        end
    else
        modelOrPart.CFrame = dropCF
        table.insert(parts, modelOrPart)
    end

    for _, p in ipairs(parts) do
        p.Anchored = false
        p.CanCollide = true
        if typeof(p.SetNetworkOwner) == "function" then
            pcall(function() p:SetNetworkOwner(game.Players.LocalPlayer) end)
        end
        p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        p.AssemblyLinearVelocity  = NUDGE
        if p.Massless then p.Massless = false end
    end
end

-- Example: Bring Logs with a scatter around you
local function bringLogsScatter()
    local player = game.Players.LocalPlayer
    local char = player and player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local rootCF = hrp.CFrame
    local itemsFolder = workspace:FindFirstChild("Items")
    if not itemsFolder then return end

    local now = tick()
    for _, item in ipairs(itemsFolder:GetChildren()) do
        if item:IsA("Model") and string.find(string.lower(item.Name), "log", 1, true) then
            local last = recentlyMoved[item]
            if not (last and (now - last) <= COOLDOWN_SEC) then
                local main = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
                if main then
                    local offset = CFrame.new(math.random(-5, 5), DROP_Y_OFFSET, math.random(-5, 5))
                    local dropCF = rootCF * offset
                    moveItemOnce(item, dropCF)
                    recentlyMoved[item] = now
                end
            end
        end
    end
end

-- Bring toggles (state only; behavior uses bringItemsSmart)
local junkToggleEnabled = false
local fuelToggleEnabled = false
local foodToggleEnabled = false
local medicalToggleEnabled = false
local equipmentToggleEnabled = false

-- =====================
-- Bring UI (Junk / Fuel / Food / Medical / Equipment)
-- =====================

Tabs.br:Section({ Title = "Junk", Icon = "box" })
Tabs.br:Dropdown({
    Title = "Select Junk Items",
    Desc = "Choose items to bring",
    Values = junkItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedJunkItems = options
    end
})
Tabs.br:Toggle({
    Title = "Bring Junk Items",
    Desc = "",
    Default = false,
    Callback = function(on)
        junkToggleEnabled = on
        if on then
            task.spawn(function()
                while junkToggleEnabled do
                    if #selectedJunkItems > 0 then
                        bringItemsSmart(selectedJunkItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    end
                    task.wait(0.6)
                end
            end)
        end
    end
})

Tabs.br:Section({ Title = "Fuel", Icon = "flame" })
Tabs.br:Dropdown({
    Title = "Select Fuel Items",
    Desc = "Choose items to bring",
    Values = fuelItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedFuelItems = options
    end
})
Tabs.br:Toggle({
    Title = "Bring Fuel Items",
    Desc = "",
    Default = false,
    Callback = function(on)
        fuelToggleEnabled = on
        if on then
            task.spawn(function()
                while fuelToggleEnabled do
                    if #selectedFuelItems > 0 then
                        bringItemsSmart(selectedFuelItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    end
                    task.wait(0.6)
                end
            end)
        end
    end
})

Tabs.br:Section({ Title = "Food", Icon = "utensils" })
Tabs.br:Dropdown({
    Title = "Select Food Items",
    Desc = "Choose items to bring",
    Values = foodItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedFoodItems = options
    end
})
Tabs.br:Toggle({
    Title = "Bring Food Items",
    Desc = "",
    Default = false,
    Callback = function(on)
        foodToggleEnabled = on
        if on then
            task.spawn(function()
                while foodToggleEnabled do
                    if #selectedFoodItems > 0 then
                        bringItemsSmart(selectedFoodItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    end
                    task.wait(0.6)
                end
            end)
        end
    end
})

Tabs.br:Section({ Title = "Medical", Icon = "bandage" }) -- renamed from Medicine
Tabs.br:Dropdown({
    Title = "Select Medical Items",
    Desc = "Choose items to bring",
    Values = medicalItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedMedicalItems = options
    end
})
Tabs.br:Toggle({
    Title = "Bring Medical Items",
    Desc = "",
    Default = false,
    Callback = function(on)
        medicalToggleEnabled = on
        if on then
            task.spawn(function()
                while medicalToggleEnabled do
                    if #selectedMedicalItems > 0 then
                        bringItemsSmart(selectedMedicalItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    end
                    task.wait(0.6)
                end
            end)
        end
    end
})

Tabs.br:Section({ Title = "Equipment", Icon = "sword" })
Tabs.br:Dropdown({
    Title = "Select Equipment Items",
    Desc = "Choose items to bring",
    Values = equipmentItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedEquipmentItems = options
    end
})
Tabs.br:Toggle({
    Title = "Bring Equipment Items",
    Desc = "",
    Default = false,
    Callback = function(on)
        equipmentToggleEnabled = on
        if on then
            task.spawn(function()
                while equipmentToggleEnabled do
                    if #selectedEquipmentItems > 0 then
                        bringItemsSmart(selectedEquipmentItems, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE)
                    end
                    task.wait(0.6)
                end
            end)
        end
    end
})

-- =====================
-- Fly / Player UI (unchanged from baseline)
-- =====================
local flyToggle = false
local flySpeed = 1
local FLYING = false
local flyKeyDown, flyKeyUp, mfly1, mfly2
local IYMouse = game:GetService("UserInputService")

local function sFLY()
    repeat task.wait() until Players.LocalPlayer and Players.LocalPlayer.Character and Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart") and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    repeat task.wait() until IYMouse
    if flyKeyDown or flyKeyUp then flyKeyDown:Disconnect(); flyKeyUp:Disconnect() end

    local T = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
    local lCONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
    local SPEED = flySpeed

    local function FLY()
        FLYING = true
        local BG = Instance.new('BodyGyro')
        local BV = Instance.new('BodyVelocity')
        BG.P = 9e4
        BG.Parent = T
        BV.Parent = T
        BG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        BG.CFrame = T.CFrame
        BV.Velocity = Vector3.new(0, 0, 0)
        BV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        task.spawn(function()
            while FLYING do
                task.wait()
                if not flyToggle and Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid') then
                    Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid').PlatformStand = true
                end
                if CONTROL.L + CONTROL.R ~= 0 or CONTROL.F + CONTROL.B ~= 0 or CONTROL.Q + CONTROL.E ~= 0 then
                    SPEED = flySpeed
                elseif not (CONTROL.L + CONTROL.R ~= 0 or CONTROL.F + CONTROL.B ~= 0 or CONTROL.Q + CONTROL.E ~= 0) and SPEED ~= 0 then
                    SPEED = 0
                end
                if (CONTROL.L + CONTROL.R) ~= 0 or (CONTROL.F + CONTROL.B) ~= 0 or (CONTROL.Q + CONTROL.E) ~= 0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector * (CONTROL.F + CONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame * CFrame.new(CONTROL.L + CONTROL.R, (CONTROL.F + CONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0).p) - workspace.CurrentCamera.CoordinateFrame.p)) * SPEED
                    lCONTROL = {F = CONTROL.F, B = CONTROL.B, L = CONTROL.L, R = CONTROL.R}
                elseif (CONTROL.L + CONTROL.R) == 0 and (CONTROL.F + CONTROL.B) == 0 and (CONTROL.Q + CONTROL.E) == 0 and SPEED ~= 0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector * (lCONTROL.F + lCONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame * CFrame.new(lCONTROL.L + lCONTROL.R, (lCONTROL.F + lCONTROL.B + CONTROL.Q + CONTROL.E) * 0.2, 0).p) - workspace.CurrentCamera.CoordinateFrame.p)) * SPEED
                else
                    BV.Velocity = Vector3.new(0, 0, 0)
                end
                BG.CFrame = workspace.CurrentCamera.CoordinateFrame
            end
            CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
            lCONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}
            SPEED = 0
            BG:Destroy()
            BV:Destroy()
            if Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid') then
                Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid').PlatformStand = false
            end
        end)
    end
    flyKeyDown = IYMouse.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local KEY = input.KeyCode.Name
            if KEY == "W" then
                CONTROL.F = flySpeed
            elseif KEY == "S" then
                CONTROL.B = -flySpeed
            elseif KEY == "A" then
                CONTROL.L = -flySpeed
            elseif KEY == "D" then 
                CONTROL.R = flySpeed
            elseif KEY == "E" then
                CONTROL.Q = flySpeed * 2
            elseif KEY == "Q" then
                CONTROL.E = -flySpeed * 2
            end
            pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Track end)
        end
    end)
    flyKeyUp = IYMouse.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local KEY = input.KeyCode.Name
            if KEY == "W" then
                CONTROL.F = 0
            elseif KEY == "S" then
                CONTROL.B = 0
            elseif KEY == "A" then
                CONTROL.L = 0
            elseif KEY == "D" then
                CONTROL.R = 0
            elseif KEY == "E" then
                CONTROL.Q = 0
            elseif KEY == "Q" then
                CONTROL.E = 0
            end
        end
    end)
    FLY()
end

local function NOFLY()
    FLYING = false
    if flyKeyDown then flyKeyDown:Disconnect() end
    if flyKeyUp then flyKeyUp:Disconnect() end
    if mfly1 then mfly1:Disconnect() end
    if mfly2 then mfly2:Disconnect() end
    if Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid') then
        Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid').PlatformStand = false
    end
    pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
end

local function UnMobileFly()
    pcall(function()
        FLYING = false
        local root = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        if root:FindFirstChild("BodyVelocity") then root:FindFirstChild("BodyVelocity"):Destroy() end
        if root:FindFirstChild("BodyGyro") then root:FindFirstChild("BodyGyro"):Destroy() end
        if Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid") then
            Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid").PlatformStand = false
        end
        if mfly1 then mfly1:Disconnect() end
        if mfly2 then mfly2:Disconnect() end
    end)
end

local function MobileFly()
    UnMobileFly()
    FLYING = true

    local root = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera
    local v3none = Vector3.new()
    local v3zero = Vector3.new(0, 0, 0)
    local v3inf = Vector3.new(9e9, 9e9, 9e9)

    local controlModule = require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    local bv = Instance.new("BodyVelocity")
    bv.Name = "BodyVelocity"
    bv.Parent = root
    bv.MaxForce = v3zero
    bv.Velocity = v3zero

    local bg = Instance.new("BodyGyro")
    bg.Name = "BodyGyro"
    bg.Parent = root
    bg.MaxTorque = v3inf
    bg.P = 1000
    bg.D = 50

    mfly1 = Players.LocalPlayer.CharacterAdded:Connect(function()
        local newRoot = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        local newBv = Instance.new("BodyVelocity")
        newBv.Name = "BodyVelocity"
        newBv.Parent = newRoot
        newBv.MaxForce = v3zero
        newBv.Velocity = v3zero

        local newBg = Instance.new("BodyGyro")
        newBg.Name = "BodyGyro"
        newBg.Parent = newRoot
        newBg.MaxTorque = v3inf
        newBg.P = 1000
        newBg.D = 50
    end)

    mfly2 = game:GetService("RunService").RenderStepped:Connect(function()
        root = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        camera = workspace.CurrentCamera
        if Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid") and root and root:FindFirstChild("BodyVelocity") and root:FindFirstChild("BodyGyro") then
            local humanoid = Players.LocalPlayer.Character:FindFirstChildWhichIsA("Humanoid")
            local VelocityHandler = root:FindFirstChild("BodyVelocity")
            local GyroHandler = root:FindFirstChild("BodyGyro")

            VelocityHandler.MaxForce = v3inf
            GyroHandler.MaxTorque = v3inf
            humanoid.PlatformStand = true
            GyroHandler.CFrame = camera.CoordinateFrame
            VelocityHandler.Velocity = v3none

            local direction = controlModule:GetMoveVector()
            if direction.X > 0 then
                VelocityHandler.Velocity = VelocityHandler.Velocity + camera.CFrame.RightVector * (direction.X * (flySpeed * 50))
            end
            if direction.X < 0 then
                VelocityHandler.Velocity = VelocityHandler.Velocity + camera.CFrame.RightVector * (direction.X * (flySpeed * 50))
            end
            if direction.Z > 0 then
                VelocityHandler.Velocity = VelocityHandler.Velocity - camera.CFrame.LookVector * (direction.Z * (flySpeed * 50))
            end
            if direction.Z < 0 then
                VelocityHandler.Velocity = VelocityHandler.Velocity - camera.CFrame.LookVector * (direction.Z * (flySpeed * 50))
            end
        end
    end)
end

Tabs.Fly:Section({ Title = "Main", Icon = "eye" })
Tabs.Fly:Slider({
    Title = "Fly Speed",
    Value = { Min = 1, Max = 20, Default = 1 },
    Callback = function(value)
        flySpeed = value
        if FLYING then
            task.spawn(function()
                while FLYING do
                    task.wait(0.1)
                    if UserInputService.TouchEnabled then
                        local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if root and root:FindFirstChild("BodyVelocity") then
                            local bv = root:FindFirstChild("BodyVelocity")
                            if bv.Velocity.Magnitude > 0 then
                                bv.Velocity = bv.Velocity.Unit * (flySpeed * 50)
                            end
                        end
                    end
                end
            end)
        end
    end
})

Tabs.Fly:Toggle({
    Title = "Enable Fly",
    Value = false,
    Callback = function(state)
        flyToggle = state
        if flyToggle then
            if UserInputService.TouchEnabled then
                MobileFly()
            else
                sFLY()
            end
        else
            NOFLY()
            UnMobileFly()
        end
    end
})

-- Speed controls
local speed = 16
local function setSpeed(val)
    local humanoid = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.WalkSpeed = val end
end
Tabs.Fly:Slider({
    Title = "Speed",
    Value = { Min = 16, Max = 150, Default = 16 },
    Callback = function(value) speed = value end
})
Tabs.Fly:Toggle({
    Title = "Enable Speed",
    Value = false,
    Callback = function(state) setSpeed(state and speed or 16) end
})

-- Noclip
local noclipConnection
Tabs.Fly:Toggle({
    Title = "Noclip",
    Value = false,
    Callback = function(state)
        if state then
            noclipConnection = RunService.Stepped:Connect(function()
                local char = Players.LocalPlayer.Character
                if char then
                    for _, part in ipairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end)
        else
            if noclipConnection then
                noclipConnection:Disconnect()
                noclipConnection = nil
            end
        end
    end
})

-- Infinite jump
local infJumpConnection
Tabs.Fly:Toggle({
    Title = "Inf Jump",
    Value = false,
    Callback = function(state)
        if state then
            infJumpConnection = UserInputService.JumpRequest:Connect(function()
                local char = Players.LocalPlayer.Character
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        else
            if infJumpConnection then
                infJumpConnection:Disconnect()
                infJumpConnection = nil
            end
        end
    end
})

-- =====================
-- ESP (unchanged baseline logic; using createESPText consistently)
-- =====================
local function createESPText(part, text, color)
    if part:FindFirstChild("ESPText") then return end

    local esp = Instance.new("BillboardGui")
    esp.Name = "ESPText"
    esp.Adornee = part
    esp.Size = UDim2.new(0, 100, 0, 20)
    esp.StudsOffset = Vector3.new(0, 2.5, 0)
    esp.AlwaysOnTop = true
    esp.MaxDistance = 300

    local label = Instance.new("TextLabel")
    label.Parent = esp
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(255,255,0)
    label.TextStrokeTransparency = 0.2
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold

    esp.Parent = part
end

local function Aesp(nome, tipo)
    local container
    local color
    if tipo == "item" then
        container = workspace:FindFirstChild("Items")
        color = Color3.fromRGB(0, 255, 0)
    elseif tipo == "mob" then
        container = workspace:FindFirstChild("Characters")
        color = Color3.fromRGB(255, 255, 0)
    else
        return
    end
    if not container then return end

    for _, obj in ipairs(container:GetChildren()) do
        if obj.Name == nome then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                createESPText(part, obj.Name, color)
            end
        end
    end
end

local function Desp(nome, tipo)
    local container
    if tipo == "item" then
        container = workspace:FindFirstChild("Items")
    elseif tipo == "mob" then
        container = workspace:FindFirstChild("Characters")
    else
        return
    end
    if not container then return end

    for _, obj in ipairs(container:GetChildren()) do
        if obj.Name == nome then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                for _, gui in ipairs(part:GetChildren()) do
                    if gui:IsA("BillboardGui") and gui.Name == "ESPText" then
                        gui:Destroy()
                    end
                end
            end
        end
    end
end

local selectedItems = {}
local selectedMobs = {}
local espItemsEnabled = false
local espMobsEnabled = false
local espConnections = {}

Tabs.esp:Section({ Title = "Esp Items", Icon = "package" })
Tabs.esp:Dropdown({
    Title = "Esp Items",
    Values = ie,
    Value = {},
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedItems = options
        if espItemsEnabled then
            for _, name in ipairs(ie) do
                if table.find(selectedItems, name) then
                    Aesp(name, "item")
                else
                    Desp(name, "item")
                end
            end
        else
            for _, name in ipairs(ie) do
                Desp(name, "item")
            end
        end
    end
})
Tabs.esp:Toggle({
    Title = "Enable Esp",
    Value = false,
    Callback = function(state)
        espItemsEnabled = state
        for _, name in ipairs(ie) do
            if state and table.find(selectedItems, name) then
                Aesp(name, "item")
            else
                Desp(name, "item")
            end
        end

        if state then
            if not espConnections["Items"] then
                local container = workspace:FindFirstChild("Items")
                if container then
                    espConnections["Items"] = container.ChildAdded:Connect(function(obj)
                        if table.find(selectedItems, obj.Name) then
                            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                            if part then
                                createESPText(part, obj.Name, Color3.fromRGB(0, 255, 0))
                            end
                        end
                    end)
                end
            end
        else
            if espConnections["Items"] then
                espConnections["Items"]:Disconnect()
                espConnections["Items"] = nil
            end
        end
    end
})

Tabs.esp:Section({ Title = "Esp Entity", Icon = "user" })
Tabs.esp:Dropdown({
    Title = "Esp Entity",
    Values = me,
    Value = {},
    Multi = true,
    AllowNone = true,
    Callback = function(options)
        selectedMobs = options
        if espMobsEnabled then
            for _, name in ipairs(me) do
                if table.find(selectedMobs, name) then
                    Aesp(name, "mob")
                else
                    Desp(name, "mob")
                end
            end
        else
            for _, name in ipairs(me) do
                Desp(name, "mob")
            end
        end
    end
})
Tabs.esp:Toggle({
    Title = "Enable Esp",
    Value = false,
    Callback = function(state)
        espMobsEnabled = state
        for _, name in ipairs(me) do
            if state and table.find(selectedMobs, name) then
                Aesp(name, "mob")
            else
                Desp(name, "mob")
            end
        end

        if state then
            if not espConnections["Mobs"] then
                local container = workspace:FindFirstChild("Characters")
                if container then
                    espConnections["Mobs"] = container.ChildAdded:Connect(function(obj)
                        if table.find(selectedMobs, obj.Name) then
                            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                            if part then
                                createESPText(part, obj.Name, Color3.fromRGB(255, 255, 0))
                            end
                        end
                    end)
                end
            end
        else
            if espConnections["Mobs"] then
                espConnections["Mobs"]:Disconnect()
                espConnections["Mobs"] = nil
            end
        end
    end
})

-- =====================
-- Main: Misc (unchanged baseline)
-- =====================
Tabs.Main:Section({ Title = "Misc", Icon = "settings" })

local instantInteractEnabled = false
local instantInteractConnection
local originalHoldDurations = {}

Tabs.Main:Toggle({
    Title = "Instant Interact",
    Value = false,
    Callback = function(state)
        instantInteractEnabled = state

        if state then
            originalHoldDurations = {}
            instantInteractConnection = task.spawn(function()
                while instantInteractEnabled do
                    for _, obj in ipairs(workspace:GetDescendants()) do
                        if obj:IsA("ProximityPrompt") then
                            if originalHoldDurations[obj] == nil then
                                originalHoldDurations[obj] = obj.HoldDuration
                            end
                            obj.HoldDuration = 0
                        end
                    end
                    task.wait(0.5)
                end
            end)
        else
            if instantInteractConnection then
                instantInteractEnabled = false
            end
            for obj, value in pairs(originalHoldDurations) do
                if obj and obj:IsA("ProximityPrompt") then
                    obj.HoldDuration = value
                end
            end
            originalHoldDurations = {}
        end
    end
})

local torchLoop = nil
Tabs.Main:Toggle({
    Title = "Auto Stun Deer",
    Value = false,
    Callback = function(state)
        if state then
            torchLoop = RunService.RenderStepped:Connect(function()
                pcall(function()
                    local remote = RemoteEvents:FindFirstChild("DeerHitByTorch")
                    local deer = workspace:FindFirstChild("Characters")
                        and workspace.Characters:FindFirstChild("Deer")
                    if remote and deer then
                        remote:InvokeServer(deer)
                    end
                end)
                task.wait(0.1)
            end)
        else
            if torchLoop then
                torchLoop:Disconnect()
                torchLoop = nil
            end
        end
    end
})

-- =====================
-- Vision (unchanged baseline)
-- =====================
Tabs.Vision:Section({ Title = "Vision", Icon = "eye" })

local originalParents = { Sky = nil, Bloom = nil, CampfireEffect = nil }
local function storeOriginalParents()
    local Lighting = game:GetService("Lighting")
    local sky = Lighting:FindFirstChild("Sky")
    local bloom = Lighting:FindFirstChild("Bloom")
    local campfireEffect = Lighting:FindFirstChild("CampfireEffect")
    if sky and not originalParents.Sky then originalParents.Sky = sky.Parent end
    if bloom and not originalParents.Bloom then originalParents.Bloom = bloom.Parent end
    if campfireEffect and not originalParents.CampfireEffect then originalParents.CampfireEffect = campfireEffect.Parent end
end
storeOriginalParents()

local originalColorCorrectionParent = nil
local function storeColorCorrectionParent()
    local Lighting = game:GetService("Lighting")
    local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
    if colorCorrection and not originalColorCorrectionParent then
        originalColorCorrectionParent = colorCorrection.Parent
    end
end
storeColorCorrectionParent()

Tabs.Vision:Toggle({
    Title = "Disable Fog",
    Desc = "",
    Value = false,
    Callback = function(state)
        local Lighting = game:GetService("Lighting")
        if state then
            local sky = Lighting:FindFirstChild("Sky")
            local bloom = Lighting:FindFirstChild("Bloom")
            local campfireEffect = Lighting:FindFirstChild("CampfireEffect")
            if sky then sky.Parent = nil end
            if bloom then bloom.Parent = nil end
            if campfireEffect then campfireEffect.Parent = nil end
        else
            local sky = game:FindFirstChild("Sky", true)
            local bloom = game:FindFirstChild("Bloom", true) 
            local campfireEffect = game:FindFirstChild("CampfireEffect", true)
            if not sky then sky = Lighting:FindFirstChild("Sky") end
            if not bloom then bloom = Lighting:FindFirstChild("Bloom") end
            if not campfireEffect then campfireEffect = Lighting:FindFirstChild("CampfireEffect") end
            if sky then sky.Parent = originalParents.Sky or Lighting end
            if bloom then bloom.Parent = originalParents.Bloom or Lighting end
            if campfireEffect then campfireEffect.Parent = originalParents.CampfireEffect or Lighting end
        end
    end
})

local originalLightingValues = {
    Brightness = nil,
    Ambient = nil,
    OutdoorAmbient = nil,
    ShadowSoftness = nil,
    GlobalShadows = nil,
    Technology = nil
}
local function storeOriginalLighting()
    local Lighting = game:GetService("Lighting")
    if not originalLightingValues.Brightness then
        originalLightingValues.Brightness = Lighting.Brightness
        originalLightingValues.Ambient = Lighting.Ambient
        originalLightingValues.OutdoorAmbient = Lighting.OutdoorAmbient
        originalLightingValues.ShadowSoftness = Lighting.ShadowSoftness
        originalLightingValues.GlobalShadows = Lighting.GlobalShadows
        originalLightingValues.Technology = Lighting.Technology
    end
end
storeOriginalLighting()

Tabs.Vision:Toggle({
    Title = "Disable NightCampFire Effect",
    Desc = "",
    Value = false,
    Callback = function(state)
        local Lighting = game:GetService("Lighting")
        if state then
            local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
            if colorCorrection then
                if not originalColorCorrectionParent then
                    originalColorCorrectionParent = colorCorrection.Parent
                end
                colorCorrection.Parent = nil
            end
        else
            local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
            if not colorCorrection then
                colorCorrection = game:FindFirstChild("ColorCorrection", true)
            end
            if colorCorrection then
                colorCorrection.Parent = Lighting
            end
        end
    end
})

Tabs.Vision:Toggle({
    Title = "Fullbright",
    Desc = "",
    Value = false,
    Callback = function(state)
        local Lighting = game:GetService("Lighting")
        if state then
            Lighting.Brightness = 2
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            Lighting.ShadowSoftness = 0
            Lighting.GlobalShadows = false
            Lighting.Technology = Enum.Technology.Compatibility
        else
            Lighting.Brightness = originalLightingValues.Brightness
            Lighting.Ambient = originalLightingValues.Ambient
            Lighting.OutdoorAmbient = originalLightingValues.OutdoorAmbient
            Lighting.ShadowSoftness = originalLightingValues.ShadowSoftness
            Lighting.GlobalShadows = originalLightingValues.GlobalShadows
            Lighting.Technology = originalLightingValues.Technology
        end
    end
})
