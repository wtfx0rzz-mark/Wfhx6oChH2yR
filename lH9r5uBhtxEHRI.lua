-- Load WindUI
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

-- ===============================
-- Themes
-- ===============================
WindUI:AddTheme({ Name = "Dark", Accent = "#18181b", Dialog = "#18181b", Outline = "#FFFFFF", Text = "#FFFFFF", Placeholder = "#999999", Background = "#0e0e10", Button = "#52525b", Icon = "#a1a1aa" })
WindUI:AddTheme({ Name = "Light", Accent = "#f4f4f5", Dialog = "#f4f4f5", Outline = "#000000", Text = "#000000", Placeholder = "#666666", Background = "#ffffff", Button = "#e4e4e7", Icon = "#52525b" })
WindUI:AddTheme({ Name = "Gray", Accent = "#374151", Dialog = "#374151", Outline = "#d1d5db", Text = "#f9fafb", Placeholder = "#9ca3af", Background = "#1f2937", Button = "#4b5563", Icon = "#d1d5db" })
WindUI:AddTheme({ Name = "Blue", Accent = "#1e40af", Dialog = "#1e3a8a", Outline = "#93c5fd", Text = "#f0f9ff", Placeholder = "#60a5fa", Background = "#1e293b", Button = "#3b82f6", Icon = "#93c5fd" })
WindUI:AddTheme({ Name = "Green", Accent = "#059669", Dialog = "#047857", Outline = "#6ee7b7", Text = "#ecfdf5", Placeholder = "#34d399", Background = "#064e3b", Button = "#10b981", Icon = "#6ee7b7" })
WindUI:AddTheme({ Name = "Purple", Accent = "#7c3aed", Dialog = "#6d28d9", Outline = "#c4b5fd", Text = "#faf5ff", Placeholder = "#a78bfa", Background = "#581c87", Button = "#8b5cf6", Icon = "#c4b5fd" })

WindUI:SetNotificationLower(true)
if not getgenv().TransparencyEnabled then getgenv().TransparencyEnabled = false end

-- ===============================
-- Window
-- ===============================
local themes = {"Dark","Light","Gray","Blue","Green","Purple"}
local currentThemeIndex = 1

local Window = WindUI:CreateWindow({
    Title = "99 Nights in forest | Axiora Hub (Bring)",
    Icon = "package",
    Author = "AXS Scripts",
    Folder = "AxsHub",
    Size = UDim2.fromOffset(520, 380),
    Transparent = getgenv().TransparencyEnabled,
    Theme = "Dark",
    Resizable = true,
    SideBarWidth = 150,
    BackgroundImageTransparency = 0.8,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    User = { Enabled = true, Anonymous = true, Callback = function()
        currentThemeIndex += 1
        if currentThemeIndex > #themes then currentThemeIndex = 1 end
        local newTheme = themes[currentThemeIndex]
        WindUI:SetTheme(newTheme)
        WindUI:Notify({ Title = "Theme", Content = "Switched to "..newTheme, Duration = 2, Icon = "palette" })
    end }
})
Window:SetToggleKey(Enum.KeyCode.V)

pcall(function()
    Window:CreateTopbarButton("TransparencyToggle", "eye", function()
        getgenv().TransparencyEnabled = not getgenv().TransparencyEnabled
        pcall(function() Window:ToggleTransparency(getgenv().TransparencyEnabled) end)
        WindUI:Notify({
            Title = "Transparency",
            Content = getgenv().TransparencyEnabled and "Enabled" or "Disabled",
            Duration = 2,
            Icon = getgenv().TransparencyEnabled and "eye-off" or "eye"
        })
    end, 990)
end)

Window:EditOpenButton({
    Title = "Toggle",
    Icon = "package",
    CornerRadius = UDim.new(0, 6),
    StrokeThickness = 2,
    Color = ColorSequence.new(Color3.fromRGB(138, 43, 226), Color3.fromRGB(173, 216, 230)),
    Draggable = true,
})

-- ===============================
-- Tabs (Bring-focused baseline)
-- ===============================
local Tabs = {}
Tabs.Bring = Window:Tab({ Title = "Bring", Icon = "package", Desc = "Non-moving drag/drop" })
Tabs.Utility = Window:Tab({ Title = "Utility", Icon = "settings", Desc = "Misc helpers" })

Window:SelectTab(1)

-- ===============================
-- Item category lists
-- ===============================
local junkItems       = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
local fuelItems       = {"Log","Chair","Coal","Fuel Canister","Oil Barrel","Biofuel"}
local foodItems       = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
local medicalItems    = {"Bandage","MedKit"}
local equipmentItems  = {"Revolver","Rifle","Leather Body","Iron Body","Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Strong Axe","Good Axe"}

-- Selected sets
local selectedJunkItems = {}
local selectedFuelItems = {}
local selectedFoodItems = {}
local selectedMedicalItems = {}
local selectedEquipmentItems = {}

-- ===============================
-- Client-safe noclip during drag
-- ===============================
local function setItemNoClip(item, enabled)
    if not item or not item.Parent then return end
    for _, p in ipairs(item:GetDescendants()) do
        if p:IsA("BasePart") then
            if enabled then
                p:SetAttribute("__orig_CanCollide", p.CanCollide)
                p.CanCollide = false
                p.Massless = true
                p.AssemblyLinearVelocity = Vector3.zero
                p.AssemblyAngularVelocity = Vector3.zero
            else
                local prev = p:GetAttribute("__orig_CanCollide")
                if prev ~= nil then p.CanCollide = prev else p.CanCollide = true end
                p.Massless = false
            end
        end
    end
end

-- ===============================
-- Helpers for drag/drop
-- ===============================
local function getPartFor(item)
    if not item or not item.Parent then return nil end
    if item:IsA("Model") then
        local p = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
        if not item.PrimaryPart and p then pcall(function() item.PrimaryPart = p end) end
        return p
    elseif item:IsA("BasePart") then
        return item
    end
    return nil
end

local function tryStartDrag(item)
    return pcall(function()
        ReplicatedStorage:WaitForChild("RemoteEvents").RequestStartDraggingItem:FireServer(item)
    end)
end

local function stopDrag(item)
    pcall(function()
        ReplicatedStorage:WaitForChild("RemoteEvents").StopDraggingItem:FireServer(item)
    end)
end

local function ringSlots(originCF, count, radius)
    local slots, n = {}, math.max(1, count)
    local o = originCF.Position
    for i = 1, n do
        local t = (i - 1) / n * (math.pi * 2)
        slots[i] = CFrame.new(Vector3.new(o.X + math.cos(t)*radius, o.Y, o.Z + math.sin(t)*radius))
    end
    return slots
end

local function findItemsByNames(namesSet, maxPerName)
    local buckets = {} -- name -> array of {item, part}
    for _, d in ipairs(Workspace:GetDescendants()) do
        if namesSet[d.Name] and (d:IsA("BasePart") or d:IsA("Model")) then
            local p = getPartFor(d)
            if p then
                local list = buckets[d.Name]; if not list then list = {}; buckets[d.Name] = list end
                if not maxPerName or #list < maxPerName then
                    table.insert(list, { item = d, part = p })
                end
            end
        end
    end
    return buckets
end

local function placeAt(item, cf)
    local part = getPartFor(item); if not part then return end
    if item:IsA("Model") then item:SetPrimaryPartCFrame(cf) else part.CFrame = cf end
    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
end

-- ===============================
-- Bring engine (non-moving drag)
-- ===============================
local isCollecting = false
local originalPosition = nil

local MAX_PER_ITEM   = 10
local DROP_RADIUS    = 6
local DROP_HEIGHT    = 3
local ATTACH_DELAY   = 0.25
local CADENCE        = 0.15

local function bringSelectedItems(nameList)
    if isCollecting then return end
    isCollecting = true

    local player = LocalPlayer
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then isCollecting = false return end

    originalPosition = hrp.CFrame
    local origin = originalPosition

    -- convert nameList array -> set for faster search
    local wanted = {}
    for _, n in ipairs(nameList) do wanted[n] = true end

    local buckets = findItemsByNames(wanted, MAX_PER_ITEM)
    -- flatten order by categories but preserve names
    for itemName, list in pairs(buckets) do
        -- compute ring for this batch
        local slots = ringSlots(origin, #list, DROP_RADIUS)
        for i, rec in ipairs(list) do
            if not rec.item or not rec.item.Parent or not rec.part then continue end

            local ok = tryStartDrag(rec.item)
            if not ok then continue end

            setItemNoClip(rec.item, true)
            pcall(function()
                if rec.part.SetNetworkOwner then rec.part:SetNetworkOwner(player) end
                rec.part.Anchored = false
                rec.part.CanCollide = false
            end)

            task.wait(ATTACH_DELAY)

            local dropCf = (slots[i] or origin) + Vector3.new(0, DROP_HEIGHT, 0)
            placeAt(rec.item, dropCf)

            stopDrag(rec.item)
            setItemNoClip(rec.item, false)
            task.wait(CADENCE)
        end
    end

    isCollecting = false
end

-- ===============================
-- UI: Bring Tab
-- ===============================
Tabs.Bring:Section({ Title = "Selection", Icon = "list" })

local function toSet(tbl) local s = {}; for _,v in ipairs(tbl) do s[v] = true end; return s end

Tabs.Bring:Dropdown({
    Title = "Junk Items",
    Desc = "Select junk to bring",
    Values = junkItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options) selectedJunkItems = options end
})

Tabs.Bring:Dropdown({
    Title = "Fuel Items",
    Desc = "Select fuel to bring",
    Values = fuelItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options) selectedFuelItems = options end
})

Tabs.Bring:Dropdown({
    Title = "Food Items",
    Desc = "Select food to bring",
    Values = foodItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options) selectedFoodItems = options end
})

Tabs.Bring:Dropdown({
    Title = "Medical Items",
    Desc = "Select medical to bring",
    Values = medicalItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options) selectedMedicalItems = options end
})

Tabs.Bring:Dropdown({
    Title = "Equipment Items",
    Desc = "Select equipment to bring",
    Values = equipmentItems,
    Multi = true,
    AllowNone = true,
    Callback = function(options) selectedEquipmentItems = options end
})

Tabs.Bring:Section({ Title = "Controls", Icon = "play" })

local bringLoopRunning = false

local function startBringLoop(getSelectedFunc, label)
    if bringLoopRunning then return end
    bringLoopRunning = true
    WindUI:Notify({ Title = "Bring", Content = "Starting "..label, Duration = 2, Icon = "play" })
    task.spawn(function()
        while bringLoopRunning do
            local list = getSelectedFunc()
            if list and #list > 0 then
                bringSelectedItems(list)
            end
            task.wait(2.0)
        end
    end)
end

local function stopBringLoop()
    bringLoopRunning = false
    WindUI:Notify({ Title = "Bring", Content = "Stopped", Duration = 2, Icon = "square" })
end

Tabs.Bring:Button({
    Title = "Bring Selected Junk",
    Locked = false,
    Callback = function()
        if not bringLoopRunning then
            startBringLoop(function() return selectedJunkItems end, "Junk")
        else
            stopBringLoop()
        end
    end
})

Tabs.Bring:Button({
    Title = "Bring Selected Fuel",
    Locked = false,
    Callback = function()
        if not bringLoopRunning then
            startBringLoop(function() return selectedFuelItems end, "Fuel")
        else
            stopBringLoop()
        end
    end
})

Tabs.Bring:Button({
    Title = "Bring Selected Food",
    Locked = false,
    Callback = function()
        if not bringLoopRunning then
            startBringLoop(function() return selectedFoodItems end, "Food")
        else
            stopBringLoop()
        end
    end
})

Tabs.Bring:Button({
    Title = "Bring Selected Medical",
    Locked = false,
    Callback = function()
        if not bringLoopRunning then
            startBringLoop(function() return selectedMedicalItems end, "Medical")
        else
            stopBringLoop()
        end
    end
})

Tabs.Bring:Button({
    Title = "Bring Selected Equipment",
    Locked = false,
    Callback = function()
        if not bringLoopRunning then
            startBringLoop(function() return selectedEquipmentItems end, "Equipment")
        else
            stopBringLoop()
        end
    end
})

Tabs.Bring:Toggle({
    Title = "Stop/Start Loop (Master)",
    Value = true,
    Callback = function(state)
        if not state then stopBringLoop() end
    end
})

-- ===============================
-- Utility Tab
-- ===============================
Tabs.Utility:Section({ Title = "Parameters", Icon = "sliders" })

local function sliderNum(min,max,default,cb)
    return Tabs.Utility:Slider({
        Title = "",
        Value = { Min = min, Max = max, Default = default },
        Callback = cb
    })
end

sliderNum(1, 20, MAX_PER_ITEM, function(v) MAX_PER_ITEM = math.clamp(v,1,20) end)
Tabs.Utility:Paragraph({ Title = "Max per item (1-20)", Desc = "How many of each item to bring per pass." })

sliderNum(3, 20, DROP_RADIUS, function(v) DROP_RADIUS = math.clamp(v,3,50) end)
Tabs.Utility:Paragraph({ Title = "Drop ring radius", Desc = "How far around you to place items." })

sliderNum(1, 10, DROP_HEIGHT, function(v) DROP_HEIGHT = math.clamp(v,1,20) end)
Tabs.Utility:Paragraph({ Title = "Drop height", Desc = "How high above your position to release items." })

-- Ensure clean shutdown when GUI is closed
local function onShutdown()
    bringLoopRunning = false
    isCollecting = false
end

game:BindToClose(onShutdown)
