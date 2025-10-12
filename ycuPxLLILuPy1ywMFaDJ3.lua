-- 99 Nights in the Forest | WindUI – Full Build (all requests merged)
repeat task.wait() until game:IsLoaded()

-- =====================
-- Tunables (quick edits)
-- =====================
local AURA_SWING_DELAY = 0.55     -- kill aura cadence (s)
local CHOP_SWING_DELAY = 0.55     -- small/normal trees cadence (s)
local BIGTREE_SWING_DELAY = 0.55  -- big trees cadence (s)
local TREE_SMALL_NAME   = "Small Tree"
local BIG_TREE_NAMES    = { TreeBig1 = true, TreeBig2 = true, TreeBig3 = true }
local UID_SUFFIX        = "0000000000" -- hit id suffix

-- Requeue (trees missing TreeHealth)
local REQUEUE_RETRY_SECS = 0.20   -- retry cadence
local REQUEUE_MAX        = 400    -- cap queue size

-- Bring
local BRING_INNER_RADIUS = 7
local BRING_MAX_RADIUS   = 2000
local BRING_BATCH_SIZE   = 40
local BRING_GROUND_SNAP  = true   -- snap to terrain when dropping
local BRING_PUSH_DOWN    = 30     -- downward linear vel nudge
local BRING_ANGULAR_JIT  = 5      -- small angular jitter (deg/s)

-- Campground preference
local SCRAPPER_PREF_RAD  = 35     -- prefer “Movers” on Scrapper when within this radius
local CAMPFIRE_RAD       = 35     -- otherwise feed campfire when within this radius

-- ESP
local ESP_MAX_DIST       = 300

-- Highlights (SelectionBox)
local H_LINE_THICKNESS   = 0.08
local H_ZINDEX           = 10

-- =====================
-- Services & Libs
-- =====================
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local LocalPlayer        = Players.LocalPlayer

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

-- =====================
-- Themes / Window
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
        Enabled = true, Anonymous = false,
        Callback = function()
            currentThemeIndex = currentThemeIndex % #themes + 1
            local t = themes[currentThemeIndex]
            WindUI:SetTheme(t)
            WindUI:Notify({ Title="Theme", Content="Switched to "..t, Duration=2, Icon="palette" })
        end,
    },
})
Window:SetToggleKey(Enum.KeyCode.V)
pcall(function()
    Window:CreateTopbarButton("TransparencyToggle","eye",function()
        getgenv().TransparencyEnabled = not getgenv().TransparencyEnabled
        pcall(function() Window:ToggleTransparency(getgenv().TransparencyEnabled) end)
        WindUI:Notify({ Title="Transparency", Content=(getgenv().TransparencyEnabled and "Enabled" or "Disabled"), Duration=2 })
    end, 990)
end)
Window:EditOpenButton({ Title="Toggle", Icon="zap", CornerRadius=UDim.new(0,6), StrokeThickness=2, Color=ColorSequence.new(Color3.fromRGB(138,43,226), Color3.fromRGB(173,216,230)), Draggable=true })

-- =====================
-- Tabs
-- =====================
local Tabs = {}
Tabs.Combat      = Window:Tab({ Title="Combat",      Icon="sword",       Desc="Auras" })
Tabs.Main        = Window:Tab({ Title="Main",        Icon="align-left",  Desc="Utility" })
Tabs.Esp         = Window:Tab({ Title="Esp",         Icon="sparkles",    Desc="ESP" })
Tabs.Bring       = Window:Tab({ Title="Bring",       Icon="package",     Desc="Mover" })
Tabs.Teleport    = Window:Tab({ Title="Teleport",    Icon="map",         Desc="Waypoints" })
Tabs.Player      = Window:Tab({ Title="Player",      Icon="user",        Desc="Movement" })
Tabs.Environment = Window:Tab({ Title="Environment", Icon="eye",         Desc="Lighting" })
Window:SelectTab(1)

-- =====================
-- Helpers / Remotes
-- =====================
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

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
                      or ReplicatedStorage:FindFirstChild("Remotes")
                      or waitForDescendant(ReplicatedStorage, "RemoteEvents", 10)

local EquipItemHandle   = RemoteEvents and (RemoteEvents:FindFirstChild("EquipItemHandle") or waitForDescendant(RemoteEvents,"EquipItemHandle",10))
local ToolDamageObject  = RemoteEvents and (RemoteEvents:FindFirstChild("ToolDamageObject")
                        or RemoteEvents:FindFirstChild("ToolDamage")
                        or RemoteEvents:FindFirstChild("DamageObject"))
                        or waitForDescendant(ReplicatedStorage,"ToolDamageObject",10)
local FeedCampfire      = RemoteEvents and (RemoteEvents:FindFirstChild("FeedCampfire") or RemoteEvents:FindFirstChild("CampfireFeed"))
local FeedScrapper      = RemoteEvents and (RemoteEvents:FindFirstChild("FeedScrapper") or RemoteEvents:FindFirstChild("ScrapperFeed"))
local CollectCoin       = RemoteEvents and (RemoteEvents:FindFirstChild("CollectCoin") or RemoteEvents:FindFirstChild("PickupCoin"))

local function HRP()
    local c = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return c:FindFirstChild("HumanoidRootPart")
end
local function dist(a,b) return (a-b).Magnitude end
local function now() return os.clock() end

-- =====================
-- Inventory / Equip
-- =====================
local toolsDamageIDs = {
    ["Old Axe"]    = "3_7367831688",
    ["Good Axe"]   = "112_7367831688",
    ["Strong Axe"] = "116_7367831688",
    ["Chainsaw"]   = "647_8992824875",
    ["Spear"]      = "196_8999010016"
}
local ChopPrefer = {"Chainsaw","Strong Axe","Good Axe","Old Axe"}
local KillPrefer = {"Spear","Strong Axe","Good Axe","Old Axe","Chainsaw"}

local function findInInventory(name)
    local inv = LocalPlayer and LocalPlayer:FindFirstChild("Inventory")
    return inv and inv:FindFirstChild(name) or nil
end
local function equippedToolName()
    local char = LocalPlayer.Character
    if not char then return nil end
    local t = char:FindFirstChildOfClass("Tool")
    return t and t.Name or nil
end
local function ensureEquipped(wantedName)
    if not wantedName then return nil end
    if equippedToolName() == wantedName then return findInInventory(wantedName) end
    local t = findInInventory(wantedName)
    if t and EquipItemHandle then pcall(function() EquipItemHandle:FireServer("FireAllClients", t) end) end
    return t
end

-- =====================
-- Target classifiers
-- =====================
local function isOnScreen(part)
    local cam = Workspace.CurrentCamera
    if not cam or not part then return false end
    local v, on = cam:WorldToViewportPoint(part.Position)
    if not on then return false end
    return v.Z > 0
end

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
local _hitCounter = 0
local function nextHitId() _hitCounter += 1; return tostring(_hitCounter) .. "_" .. UID_SUFFIX end
local SYN_OFFSET, SYN_DEPTH = 1.0, 4.0
local function computeImpactCFrame(model, part)
    if not (model and part and part:IsA("BasePart")) then
        return part and CFrame.new(part.Position) or CFrame.new()
    end
    local outward = part.CFrame.LookVector
    if outward.Magnitude == 0 then outward = Vector3.new(0,0,-1) end
    outward = outward.Unit
    local origin = part.Position + outward * SYN_OFFSET
    local dir    = -outward * (SYN_OFFSET + SYN_DEPTH)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Include
    p.FilterDescendantsInstances = {model}
    local rc = Workspace:Raycast(origin, dir, p)
    local pos = rc and (rc.Position + rc.Normal*0.02) or (origin + dir*0.6)
    local rot = part.CFrame - part.CFrame.Position
    return CFrame.new(pos) * rot
end

-- =====================
-- Highlights (SelectionBox)
-- =====================
local HFolder = Workspace:FindFirstChild("__AuraHighlights__") or (function()
    local f = Instance.new("Folder"); f.Name="__AuraHighlights__"; f.Parent=Workspace; return f
end)()
local activeBoxes = {} -- [Instance]=SelectionBox
local function ensureBox(adorn)
    local sb = activeBoxes[adorn]
    if not sb then
        sb = Instance.new("SelectionBox")
        sb.Name="__AuraSB"
        sb.Adornee = adorn
        sb.LineThickness = H_LINE_THICKNESS
        sb.SurfaceTransparency = 1
        sb.Color3 = Color3.new(1,1,0)
        sb.ZIndex = H_ZINDEX
        sb.Parent = HFolder
        activeBoxes[adorn] = sb
    end
    return sb
end
local function clearHighlights() for inst, box in pairs(activeBoxes) do if box then box:Destroy() end activeBoxes[inst]=nil end end

-- =====================
-- Requeue for TreeHealth
-- =====================
local Requeue = {} -- { model=Model, last=timestamp, rangeAtQueue=number }
local function enqueueTree(model, range, onlyIfNotPresent)
    if #Requeue >= REQUEUE_MAX then return end
    if onlyIfNotPresent then
        for _,q in ipairs(Requeue) do if q.model==model then return end end
    end
    table.insert(Requeue, {model=model, last=0, keepRange=range})
end
local function processRequeue(origin, currentRange, visibleOnly)
    local nowt = now()
    for i = #Requeue, 1, -1 do
        local q = Requeue[i]
        local m = q.model
        if not m or not m.Parent then table.remove(Requeue, i) continue end
        if nowt - (q.last or 0) < REQUEUE_RETRY_SECS then continue end
        local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
        if not pp then table.remove(Requeue, i) continue end
        -- only while still in valid range of *current* player
        if dist(origin, pp.Position) > (currentRange or q.keepRange or 0) then
            table.remove(Requeue, i); continue
        end
        -- visibleOnly: must also be on-screen
        if visibleOnly and not isOnScreen(pp) then
            q.last = nowt; continue
        end
        -- has TreeHealth yet?
        local has = (m:GetAttribute("Health") ~= nil) or m:FindFirstChild("TreeHealth") or m:FindFirstChild("Health")
        if has then
            -- do a chop now
            local toolName = (ensureEquipped(ChopPrefer[1]) and ChopPrefer[1]) or equippedToolName()
            local tool = toolName and findInInventory(toolName)
            local id = nextHitId()
            local hit = bestTreeHitPart(m) or pp
            local cf  = computeImpactCFrame(m, hit)
            if tool and ToolDamageObject then pcall(function() ToolDamageObject:InvokeServer(m, tool, id, cf) end) end
            table.remove(Requeue, i)
        else
            q.last = nowt
        end
    end
end

-- =====================
-- Auras (state)
-- =====================
local killAuraToggle, chopAuraToggle, bigTreeAuraToggle = false, false, false
local highlightTrees, highlightAnimals = false, false
local visibleOnly = false
local auraRadius = 50

-- =====================
-- Kill Aura
-- =====================
local function killAuraLoop()
    while killAuraToggle do
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2) break end

        local toolName = equippedToolName()
        if not toolName then
            for _,n in ipairs(KillPrefer) do if findInInventory(n) then toolName=n break end end
        end
        local tool = toolName and ensureEquipped(toolName)
        local damageID = toolName and toolsDamageIDs[toolName]
        if tool and damageID and ToolDamageObject then
            local folder = Workspace:FindFirstChild("Characters")
            if folder then
                local origin = hrp.Position
                for _, mob in ipairs(folder:GetChildren()) do
                    if not killAuraToggle then break end
                    if mob:IsA("Model") and mob ~= char then
                        local part = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart")
                        if part then
                            if visibleOnly and not isOnScreen(part) then goto cont end
                            if not visibleOnly and dist(part.Position, origin) > auraRadius then goto cont end
                            pcall(function() ToolDamageObject:InvokeServer(mob, tool, damageID, CFrame.new(part.Position)) end)
                            if highlightAnimals then ensureBox(part) end
                        end
                    end
                    ::cont::
                end
            end
            task.wait(AURA_SWING_DELAY)
        else
            task.wait(0.35)
        end
    end
end

-- =====================
-- Chop (Small) + Big Trees
-- =====================
local function chopWave(trees, delaySecs)
    local toolName
    for _,n in ipairs(ChopPrefer) do if findInInventory(n) then toolName=n break end end
    if not toolName then task.wait(0.35) return end
    local tool = ensureEquipped(toolName)
    for _, tree in ipairs(trees) do
        task.spawn(function()
            local hit = bestTreeHitPart(tree)
            if hit then
                local id = nextHitId()
                local cf = computeImpactCFrame(tree, hit)
                pcall(function() ToolDamageObject:InvokeServer(tree, tool, id, cf) end)
            end
        end)
    end
    task.wait(delaySecs)
end

local function chopAuraLoop()
    while chopAuraToggle do
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2) break end
        local origin = hrp.Position

        local trees = {}
        local map = Workspace:FindFirstChild("Map")
        local function scan(folder)
            if not folder then return end
            for _, obj in ipairs(folder:GetChildren()) do
                if obj:IsA("Model") and obj.Name == TREE_SMALL_NAME then
                    local trunk = bestTreeHitPart(obj) or obj:FindFirstChild("Trunk") or obj.PrimaryPart
                    if trunk then
                        if visibleOnly and not isOnScreen(trunk) then goto cont end
                        if not visibleOnly and dist(trunk.Position, origin) > auraRadius then goto cont end
                        if (obj:GetAttribute("Health") ~= nil) or obj:FindFirstChild("TreeHealth") or obj:FindFirstChild("Health") then
                            table.insert(trees, obj)
                        else
                            enqueueTree(obj, (visibleOnly and 99999 or auraRadius), true)
                        end
                        if highlightTrees then ensureBox(trunk) end
                    end
                end
                ::cont::
            end
        end
        if map then scan(map:FindFirstChild("Foliage")); scan(map:FindFirstChild("Landmarks")) end

        processRequeue(origin, (visibleOnly and 99999 or auraRadius), visibleOnly)
        if #trees > 0 then chopWave(trees, CHOP_SWING_DELAY) else task.wait(0.25) end
    end
end

local function bigTreeAuraLoop()
    while bigTreeAuraToggle do
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.2) break end
        local origin = hrp.Position

        local trees = {}
        local foliage = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Foliage")
        if foliage then
            for _, m in ipairs(foliage:GetChildren()) do
                if m:IsA("Model") and BIG_TREE_NAMES[m.Name] then
                    local part = bestTreeHitPart(m) or m:FindFirstChild("Trunk") or m.PrimaryPart
                    if part then
                        if visibleOnly and not isOnScreen(part) then goto cont end
                        if not visibleOnly and dist(part.Position, origin) > auraRadius then goto cont end
                        if (m:GetAttribute("Health") ~= nil) or m:FindFirstChild("TreeHealth") or m:FindFirstChild("Health") then
                            trees[#trees+1] = m
                        else
                            enqueueTree(m, (visibleOnly and 99999 or auraRadius), true)
                        end
                        if highlightTrees then ensureBox(part) end
                    end
                end
                ::cont::
            end
        end
        processRequeue(origin, (visibleOnly and 99999 or auraRadius), visibleOnly)
        if #trees > 0 then chopWave(trees, BIGTREE_SWING_DELAY) else task.wait(0.25) end
    end
end

-- =====================
-- Campground feed preference (Scrapper Movers > Campfire)
-- =====================
local function nearestByName(center, names, maxR)
    local best, bestD
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") then
            for _, n in ipairs(names) do
                if m.Name == n then
                    local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if pp then
                        local d = dist(center, pp.Position)
                        if d <= maxR and (not bestD or d < bestD) then best, bestD = m, d end
                    end
                end
            end
        end
    end
    return best
end

RunService.Heartbeat:Connect(function()
    local hrp = HRP(); if not hrp then return end
    local center = hrp.Position
    local scrapper = nearestByName(center, {"Movers","Scrapper"}, SCRAPPER_PREF_RAD)
    if scrapper and FeedScrapper then pcall(function() FeedScrapper:FireServer(scrapper) end) return end
    local camp = nearestByName(center, {"Campfire","MainFire"}, CAMPFIRE_RAD)
    if camp and FeedCampfire then pcall(function() FeedCampfire:FireServer(camp) end) end
end)

-- =====================
-- BRING (physics-solid)
-- =====================
local function toLowerSet(list)
    local set = {}
    for _, n in ipairs(list or {}) do if type(n)=="string" then set[string.lower(n)]=true end end
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
    local origin = pos + Vector3.new(0,200,0)
    local dir = Vector3.new(0,-500,0)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    p.FilterDescendantsInstances = {LocalPlayer.Character}
    local rc = Workspace:Raycast(origin, dir, p)
    return rc and (rc.Position + Vector3.new(0,1.2,0)) or pos
end
local function wakePart(p)
    pcall(function() p:SetNetworkOwnershipAuto() end)
    pcall(function() p:SetNetworkOwner(nil) end)
    p.Anchored = false; p.CanCollide = true; p.Massless = false
    p.AssemblyLinearVelocity  = Vector3.new(0,-BRING_PUSH_DOWN,0)
    p.AssemblyAngularVelocity = Vector3.new(
        math.rad(math.random()*BRING_ANGULAR_JIT),
        math.rad(math.random()*BRING_ANGULAR_JIT),
        math.rad(math.random()*BRING_ANGULAR_JIT)
    )
end
local function dropCF(hrp)
    local hrpPos = hrp.Position
    local r = math.max(2, BRING_INNER_RADIUS-1)
    local th = math.random()*math.pi*2
    local around = Vector3.new(hrpPos.X + math.cos(th)*r, hrpPos.Y + 4, hrpPos.Z + math.sin(th)*r)
    if BRING_GROUND_SNAP then around = groundSnapAt(around) end
    return CFrame.new(around)
end
local function moveOnce(modelOrPart, cf)
    if modelOrPart:IsA("Model") then
        modelOrPart:PivotTo(cf)
        for _,sub in ipairs(modelOrPart:GetDescendants()) do if sub:IsA("BasePart") then wakePart(sub) end end
    else
        modelOrPart.CFrame = cf; wakePart(modelOrPart)
    end
end
local function bringItemsSmart(nameList, innerRadius, maxRadius, batchSize)
    local hrp = HRP(); if not hrp then return end
    innerRadius = tonumber(innerRadius) or BRING_INNER_RADIUS
    maxRadius   = tonumber(maxRadius)   or BRING_MAX_RADIUS
    batchSize   = math.max(1, tonumber(batchSize) or BRING_BATCH_SIZE)

    local wanted = toLowerSet(nameList)
    if next(wanted)==nil then return end

    local hrpPos = hrp.Position
    local itemsFolder = Workspace:FindFirstChild("Items"); if not itemsFolder then return end

    local cands = {}
    for _,obj in ipairs(itemsFolder:GetChildren()) do
        if wanted[string.lower(obj.Name or "")] then
            local p = getMainPart(obj)
            if p then
                local d = dist(p.Position, hrpPos)
                if d > innerRadius and d <= maxRadius then
                    cands[#cands+1] = {model=obj, part=p, d=d}
                end
            end
        end
    end
    if #cands == 0 then return end
    table.sort(cands, function(a,b) return a.d > b.d end)

    local cf = dropCF(hrp)
    for i=1, math.min(batchSize, #cands) do
        local e=cands[i]
        if e.part and e.model and e.model.Parent then
            local jitter = CFrame.new(math.random(-1,1),0,math.random(-1,1))
            moveOnce(e.model, cf * jitter)
        end
    end
end

-- =====================
-- Gold collector
-- =====================
local autoGold = false
local goldConn
local function collectCoinModel(m)
    if CollectCoin then pcall(function() CollectCoin:FireServer(m) end) return end
    local prompt = m:FindFirstChildOfClass("ProximityPrompt") or m:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and typeof(fireproximityprompt)=="function" then pcall(function() prompt.HoldDuration=0; fireproximityprompt(prompt) end) end
end
local function scanGold()
    local items = Workspace:FindFirstChild("Items"); if not items then return end
    for _,ch in ipairs(items:GetChildren()) do
        if ch:IsA("Model") and ch.Name=="Coin Stack" then collectCoinModel(ch) end
    end
end
local function hookGold(enabled)
    if goldConn then goldConn:Disconnect(); goldConn=nil end
    if not enabled then return end
    local items = Workspace:FindFirstChild("Items"); if not items then return end
    goldConn = items.ChildAdded:Connect(function(ch)
        if autoGold and ch:IsA("Model") and ch.Name=="Coin Stack" then task.defer(collectCoinModel, ch) end
    end)
end

-- =====================
-- ESP
-- =====================
local function createESPText(part, text, color)
    if part:FindFirstChild("ESPText") then return end
    local esp = Instance.new("BillboardGui")
    esp.Name = "ESPText"
    esp.Adornee = part
    esp.Size = UDim2.new(0, 100, 0, 20)
    esp.StudsOffset = Vector3.new(0, 2.5, 0)
    esp.AlwaysOnTop = true
    esp.MaxDistance = ESP_MAX_DIST
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
    local container, color
    if tipo=="item" then container=workspace:FindFirstChild("Items"); color=Color3.fromRGB(0,255,0)
    elseif tipo=="mob" then container=workspace:FindFirstChild("Characters"); color=Color3.fromRGB(255,255,0) else return end
    if not container then return end
    for _, obj in ipairs(container:GetChildren()) do
        if obj.Name == nome then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then createESPText(part, obj.Name, color) end
        end
    end
end
local function Desp(nome, tipo)
    local container
    if tipo=="item" then container=workspace:FindFirstChild("Items")
    elseif tipo=="mob" then container=workspace:FindFirstChild("Characters") else return end
    if not container then return end
    for _, obj in ipairs(container:GetChildren()) do
        if obj.Name == nome then
            local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                for _, gui in ipairs(part:GetChildren()) do
                    if gui:IsA("BillboardGui") and gui.Name=="ESPText" then gui:Destroy() end
                end
            end
        end
    end
end

-- =====================
-- COMBAT UI
-- =====================
Tabs.Combat:Section({ Title="Aura", Icon="star" })
Tabs.Combat:Toggle({ Title="Kill Aura", Value=false, Callback=function(s) killAuraToggle=s; if s then task.spawn(killAuraLoop) end end })
Tabs.Combat:Toggle({ Title="Chop Aura", Value=false, Callback=function(s) chopAuraToggle=s; if s then task.spawn(chopAuraLoop) end end })
Tabs.Combat:Toggle({ Title="Big Trees", Value=false, Callback=function(s) bigTreeAuraToggle=s; if s then task.spawn(bigTreeAuraLoop) end end })

Tabs.Combat:Section({ Title="Settings", Icon="settings" })
local radiusSlider
radiusSlider = Tabs.Combat:Slider({
    Title = "Aura Radius",
    Value = { Min=50, Max=2000, Default=auraRadius },
    Callback = function(v) if not visibleOnly then auraRadius = math.clamp(v, 10, 2000) else radiusSlider:Set(auraRadius) end end
})
Tabs.Combat:Toggle({
    Title = "Visible Only (on-screen targets; ignores radius)",
    Value = false,
    Callback = function(state)
        visibleOnly = state
        pcall(function() radiusSlider:SetInteractable(not state) end)  -- disable slider while ON
        if state then WindUI:Notify({ Title="Aura", Content="Visible Only: enabled (radius ignored)", Duration=2 }) end
    end
})

-- =====================
-- MAIN UI (Highlights + Gold)
-- =====================
Tabs.Main:Section({ Title="Highlights", Icon="highlighter" })
Tabs.Main:Toggle({ Title="Highlight Trees (Yellow)",  Value=false, Callback=function(s) highlightTrees=s; if not s and not highlightAnimals then clearHighlights() end end })
Tabs.Main:Toggle({ Title="Highlight Animals (Yellow)",Value=false, Callback=function(s) highlightAnimals=s; if not s and not highlightTrees then clearHighlights() end end })

Tabs.Main:Section({ Title="Gold", Icon="coins" })
Tabs.Main:Toggle({
    Title="Auto Collect Gold (Coin Stack)", Value=false,
    Callback=function(s) autoGold=s; hookGold(s); if s then task.spawn(function() while autoGold do scanGold(); task.wait(0.35) end end) end end
})

-- =====================
-- BRING UI
-- =====================
local junkItems = {"Tyre","Bolt","Broken Fan","Broken Microwave","Sheet Metal","Old Radio","Washing Machine","Old Car Engine"}
local fuelItems = {"Log","Chair","Coal","Fuel Canister","Oil Barrel"}
local foodItems = {"Cake","Cooked Steak","Cooked Morsel","Steak","Morsel","Berry","Carrot"}
local medicalItems = {"Bandage","MedKit"}
local equipmentItems = {"Revolver","Rifle","Leather Body","Iron Body","Revolver Ammo","Rifle Ammo","Giant Sack","Good Sack","Strong Axe","Good Axe"}

local function addBringSection(title, values)
    Tabs.Bring:Section({ Title=title, Icon=(title=="Fuel" and "flame") or (title=="Equipment" and "sword") or (title=="Medical" and "bandage") or "box" })
    local selected = {}
    Tabs.Bring:Dropdown({
        Title="Select "..title.." Items", Values=values, Multi=true, AllowNone=true,
        Callback=function(opts) table.clear(selected); for _,v in ipairs(opts) do selected[#selected+1]=v end end
    })
    Tabs.Bring:Toggle({
        Title="Bring "..title.." Items", Value=false,
        Callback=function(on)
            _G["__bring_"..title.."_enabled"] = on
            if on then
                task.spawn(function()
                    while _G["__bring_"..title.."_enabled"] do
                        if #selected>0 then bringItemsSmart(selected, BRING_INNER_RADIUS, BRING_MAX_RADIUS, BRING_BATCH_SIZE) end
                        task.wait(0.6)
                    end
                end)
            end
        end
    })
end
addBringSection("Junk", junkItems)
addBringSection("Fuel", fuelItems)
addBringSection("Food", foodItems)
addBringSection("Medical", medicalItems)
addBringSection("Equipment", equipmentItems)

-- =====================
-- TELEPORT (sample)
-- =====================
local function tpCampfire()
    (LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart").CFrame =
        CFrame.new(0.43132782, 15.77634621, -1.88620758, -0.270917892, 0.102997094, 0.957076371, 0.639657021, 0.762253821, 0.0990355015, -0.719334781, 0.639031112, -0.272391081)
end
local function tpStronghold()
    local t = Workspace:FindFirstChild("Map")
        and Workspace.Map:FindFirstChild("Landmarks")
        and Workspace.Map.Landmarks:FindFirstChild("Stronghold")
        and Workspace.Map.Landmarks.Stronghold:FindFirstChild("Functional")
        and Workspace.Map.Landmarks.Stronghold.Functional:FindFirstChild("EntryDoors")
        and Workspace.Map.Landmarks.Stronghold.Functional.EntryDoors:FindFirstChild("DoorRight")
        and Workspace.Map.Landmarks.Stronghold.Functional.EntryDoors.DoorRight:FindFirstChild("Model")
    if t then
        local children = t:GetChildren()
        local dest = children[5]
        if dest and dest:IsA("BasePart") then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = dest.CFrame + Vector3.new(0,5,0) end
        end
    end
end
Tabs.Teleport:Section({ Title="Teleport", Icon="map" })
Tabs.Teleport:Button({ Title="Campfire", Locked=false, Callback=tpCampfire })
Tabs.Teleport:Button({ Title="Stronghold", Locked=false, Callback=tpStronghold })

-- =====================
-- PLAYER (fly/speed/noclip/inf jump) – unchanged core
-- =====================
local flyToggle, flySpeed, FLYING = false, 1, false
local flyKeyDown, flyKeyUp, mfly1, mfly2
local IYMouse = UserInputService
local function sFLY()
    repeat task.wait() until Players.LocalPlayer and Players.LocalPlayer.Character and Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart") and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    repeat task.wait() until IYMouse
    if flyKeyDown then flyKeyDown:Disconnect() end
    if flyKeyUp   then flyKeyUp:Disconnect() end
    local T = Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local CONTROL, lCONTROL = {F=0,B=0,L=0,R=0,Q=0,E=0}, {F=0,B=0,L=0,R=0,Q=0,E=0}
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
                if CONTROL.L+CONTROL.R ~= 0 or CONTROL.F+CONTROL.B ~= 0 or CONTROL.Q+CONTROL.E ~= 0 then
                    SPEED = flySpeed
                elseif SPEED ~= 0 then SPEED = 0 end
                if (CONTROL.L+CONTROL.R) ~= 0 or (CONTROL.F+CONTROL.B) ~= 0 or (CONTROL.Q+CONTROL.E) ~= 0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector*(CONTROL.F+CONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame*CFrame.new(CONTROL.L+CONTROL.R,(CONTROL.F+CONTROL.B+CONTROL.Q+CONTROL.E)*0.2,0).p)-workspace.CurrentCamera.CoordinateFrame.p))*SPEED
                    lCONTROL = {F=CONTROL.F,B=CONTROL.B,L=CONTROL.L,R=CONTROL.R,Q=CONTROL.Q,E=CONTROL.E}
                elseif SPEED~=0 then
                    BV.Velocity = ((workspace.CurrentCamera.CoordinateFrame.lookVector*(lCONTROL.F+lCONTROL.B)) + ((workspace.CurrentCamera.CoordinateFrame*CFrame.new(lCONTROL.L+lCONTROL.R,(lCONTROL.F+lCONTROL.B+lCONTROL.Q+lCONTROL.E)*0.2,0).p)-workspace.CurrentCamera.CoordinateFrame.p))*SPEED
                else BV.Velocity = Vector3.new(0,0,0) end
                BG.CFrame = workspace.CurrentCamera.CoordinateFrame
            end
            CONTROL={F=0,B=0,L=0,R=0,Q=0,E=0}; lCONTROL=CONTROL; SPEED=0
            BG:Destroy(); BV:Destroy()
            local h = Players.LocalPlayer.Character:FindFirstChildOfClass('Humanoid'); if h then h.PlatformStand=false end
        end)
    end
    flyKeyDown = IYMouse.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Keyboard then
            local k=input.KeyCode.Name
            if k=="W" then CONTROL.F=flySpeed elseif k=="S" then CONTROL.B=-flySpeed
            elseif k=="A" then CONTROL.L=-flySpeed elseif k=="D" then CONTROL.R=flySpeed
            elseif k=="E" then CONTROL.Q=flySpeed*2 elseif k=="Q" then CONTROL.E=-flySpeed*2 end
        end
    end)
    flyKeyUp = IYMouse.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Keyboard then
            local k=input.KeyCode.Name
            if k=="W" then CONTROL.F=0 elseif k=="S" then CONTROL.B=0
            elseif k=="A" then CONTROL.L=0 elseif k=="D" then CONTROL.R=0
            elseif k=="E" then CONTROL.Q=0 elseif k=="Q" then CONTROL.E=0 end
        end
    end)
    FLY()
end
local function NOFLY()
    FLYING=false
    if flyKeyDown then flyKeyDown:Disconnect() end
    if flyKeyUp   then flyKeyUp:Disconnect() end
    local h=Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"); if h then h.PlatformStand=false end
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
    local v3none=Vector3.new()
    local v3inf=Vector3.new(9e9,9e9,9e9)
    local controlModule=require(Players.LocalPlayer.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))
    local bv=Instance.new("BodyVelocity"); bv.Name="BodyVelocity"; bv.Parent=root; bv.MaxForce=Vector3.new(); bv.Velocity=v3none
    local bg=Instance.new("BodyGyro"); bg.Name="BodyGyro"; bg.Parent=root; bg.MaxTorque=v3inf; bg.P=1000; bg.D=50
    mfly1=Players.LocalPlayer.CharacterAdded:Connect(function()
        local nr=Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
        local nbv=Instance.new("BodyVelocity"); nbv.Name="BodyVelocity"; nbv.Parent=nr; nbv.MaxForce=Vector3.new(); nbv.Velocity=v3none
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

Tabs.Player:Section({ Title="Main", Icon="eye" })
Tabs.Player:Slider({ Title="Fly Speed", Value={Min=1,Max=20,Default=1}, Callback=function(v) flySpeed=v end })
Tabs.Player:Toggle({
    Title="Enable Fly", Value=false, Callback=function(s)
        flyToggle=s; if s then if UserInputService.TouchEnabled then MobileFly() else sFLY() end else NOFLY(); UnMobileFly() end
    end
})
local speed=16
local function setSpeed(v) local h=Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid"); if h then h.WalkSpeed=v end end
Tabs.Player:Slider({ Title="Speed", Value={Min=16,Max=150,Default=16}, Callback=function(v) speed=v end })
Tabs.Player:Toggle({ Title="Enable Speed", Value=false, Callback=function(s) setSpeed(s and speed or 16) end })
local noclipConnection
Tabs.Player:Toggle({ Title="Noclip", Value=false, Callback=function(s)
    if s then
        noclipConnection=RunService.Stepped:Connect(function()
            local char=Players.LocalPlayer.Character
            if char then for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end end
        end)
    else if noclipConnection then noclipConnection:Disconnect(); noclipConnection=nil end end
end })
local infJumpConnection
Tabs.Player:Toggle({ Title="Inf Jump", Value=false, Callback=function(s)
    if s then
        infJumpConnection=UserInputService.JumpRequest:Connect(function()
            local c=Players.LocalPlayer.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    else if infJumpConnection then infJumpConnection:Disconnect(); infJumpConnection=nil end end
end })

-- Instant Open (Prompts)
Tabs.Player:Section({ Title="Quality of Life", Icon="zap" })
local instantOpenEnabled=false
local promptRestore={}, promptAddedConn, promptRemovedConn
local function applyInstantOpenToPrompt(pp) if pp and pp:IsA("ProximityPrompt") then if promptRestore[pp]==nil then promptRestore[pp]=pp.HoldDuration end pp.HoldDuration=0 end end
local function disableInstantOpen()
    if promptAddedConn then promptAddedConn:Disconnect(); promptAddedConn=nil end
    if promptRemovedConn then promptRemovedConn:Disconnect(); promptRemovedConn=nil end
    for pp,orig in pairs(promptRestore) do if pp and pp:IsA("ProximityPrompt") then pp.HoldDuration=orig end end
    promptRestore={}
end
local function enableInstantOpen()
    for _,o in ipairs(workspace:GetDescendants()) do if o:IsA("ProximityPrompt") then applyInstantOpenToPrompt(o) end end
    promptAddedConn=workspace.DescendantAdded:Connect(function(o) if instantOpenEnabled and o:IsA("ProximityPrompt") then applyInstantOpenToPrompt(o) end end)
    promptRemovedConn=workspace.DescendantRemoving:Connect(function(o) if o:IsA("ProximityPrompt") then promptRestore[o]=nil end end)
end
Tabs.Player:Toggle({ Title="Instant Open (Prompts)", Value=false, Callback=function(s)
    instantOpenEnabled=s; if s then enableInstantOpen() else disableInstantOpen() end
end })

-- =====================
-- ESP UI
-- =====================
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

Tabs.Esp:Section({ Title="Esp Items", Icon="package" })
Tabs.Esp:Dropdown({
    Title="Esp Items", Values=ie, Value={}, Multi=true, AllowNone=true,
    Callback=function(options)
        selectedItems = options
        if espItemsEnabled then for _, name in ipairs(ie) do if table.find(selectedItems, name) then Aesp(name,"item") else Desp(name,"item") end end
        else for _, name in ipairs(ie) do Desp(name,"item") end end
    end
})
Tabs.Esp:Toggle({
    Title="Enable Esp", Value=false, Callback=function(state)
        espItemsEnabled = state
        for _, name in ipairs(ie) do if state and table.find(selectedItems, name) then Aesp(name,"item") else Desp(name,"item") end end
        if state and not espConnections.Items then
            local container = workspace:FindFirstChild("Items")
            if container then
                espConnections.Items = container.ChildAdded:Connect(function(obj)
                    if table.find(selectedItems, obj.Name) then
                        local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                        if part then createESPText(part, obj.Name, Color3.fromRGB(0,255,0)) end
                    end
                end)
            end
        elseif not state and espConnections.Items then espConnections.Items:Disconnect(); espConnections.Items=nil end
    end
})

Tabs.Esp:Section({ Title="Esp Entity", Icon="user" })
Tabs.Esp:Dropdown({
    Title="Esp Entity", Values=me, Value={}, Multi=true, AllowNone=true,
    Callback=function(options)
        selectedMobs = options
        if espMobsEnabled then for _, name in ipairs(me) do if table.find(selectedMobs, name) then Aesp(name,"mob") else Desp(name,"mob") end end
        else for _, name in ipairs(me) do Desp(name,"mob") end end
    end
})
Tabs.Esp:Toggle({
    Title="Enable Esp", Value=false, Callback=function(state)
        espMobsEnabled = state
        for _, name in ipairs(me) do if state and table.find(selectedMobs, name) then Aesp(name,"mob") else Desp(name,"mob") end end
        if state and not espConnections.Mobs then
            local container = workspace:FindFirstChild("Characters")
            if container then
                espConnections.Mobs = container.ChildAdded:Connect(function(obj)
                    if table.find(selectedMobs, obj.Name) then
                        local part = obj:IsA("BasePart") and obj or obj:FindFirstChildWhichIsA("BasePart")
                        if part then createESPText(part, obj.Name, Color3.fromRGB(255,255,0)) end
                    end
                end)
            end
        elseif not state and espConnections.Mobs then espConnections.Mobs:Disconnect(); espConnections.Mobs=nil end
    end
})

-- =====================
-- ENVIRONMENT (Lighting)
-- =====================
Tabs.Environment:Section({ Title="Vision", Icon="eye" })
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

Tabs.Environment:Toggle({
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

Tabs.Environment:Toggle({
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
Tabs.Environment:Toggle({
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
