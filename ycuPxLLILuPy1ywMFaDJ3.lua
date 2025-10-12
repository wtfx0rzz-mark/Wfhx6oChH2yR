--[[ 
  99 Nights in the Forest | Aura & Utilities (Full)
  - Requeue logic for distant/streaming targets (range-gated).
  - "Visible Only" mode, optional Aggressive Preload.
  - Big Trees toggle.
  - Highlights: Trees and Animals (bright yellow).
  - Remove Auto Feed toggle & Auto Stun Deer; add Scrapper/Campfire feed pref.
  - Auto collect gold ("Coin Stack" under Workspace.Items).
  - Minimal comments only on tweakables.
]]

-- =====================
-- Dependencies / Services
-- =====================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")

-- =====================
-- UI (Rayfield)
-- =====================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "99 Nights – Aura Suite",
    LoadingTitle = "Initializing",
    LoadingSubtitle = "CeeGee build",
    DisableRayfieldPrompts = true,
    ConfigurationSaving = { Enabled = false },
})

local TabMain = Window:CreateTab("Main", 4483362458)
local TabSettings = Window:CreateTab("Settings", 4483362458)

-- =====================
-- Tweakables (small comments only)
-- =====================
local CFG = {
    AURA_SWING_DELAY = 0.45,     -- delay between aura waves
    CHOP_SWING_DELAY = 0.40,     -- delay between chop waves
    AURA_RADIUS = 500,           -- default max range when VisibleOnly=false
    QUEUE_RETRY_SECS = 0.20,     -- how often to retry not-yet-streamed targets
    QUEUE_MAX = 400,             -- cap queued targets
    PRELOAD_NUDGE = 6,           -- studs to nudge a phantom pre-touch for streaming
    HIGHLIGHT_THICKNESS = 0.08,  -- selection box line thickness
    HIGHLIGHT_ZINDEX = 10,       -- selection box order
    GOLD_SCAN_RATE = 0.35,       -- seconds between gold scans
    FEED_SCAN_RATE = 0.60,       -- seconds between scrapper/campfire checks
    SCRAPPER_PREF_RADIUS = 35,   -- prefer movers near Scrapper within this range
    CAMPFIRE_RADIUS = 35,        -- feed at campfire within this range
}

-- Runtime flags
local STATE = {
    KillAura = false,
    ChopAura = true,
    BigTrees = false,
    VisibleOnly = false,
    AggressivePreload = false,
    HighlightTrees = false,
    HighlightAnimals = false,
    AutoCollectGold = false,
}

-- Slider value holder (ignored when VisibleOnly=true)
local auraRadiusSliderValue = CFG.AURA_RADIUS

-- =====================
-- Helpers
-- =====================
local function safeFind(root, pathArray)
    local obj = root
    for _, name in ipairs(pathArray) do
        obj = obj and obj:FindFirstChild(name)
        if not obj then return nil end
    end
    return obj
end

local function dist(a, b)
    return (a - b).Magnitude
end

local function getHRP()
    local c = LocalPlayer.Character
    if not c then return nil end
    return c:FindFirstChild("HumanoidRootPart")
end

local function now()
    return os.clock()
end

-- =====================
-- Targeting (Trees & Animals)
-- =====================
local SMALL_TREE_NAMES = { "Small Tree", "TreeSmall", "Tree_1", "Tree" }
local BIG_TREE_NAMES   = { "TreeBig1", "TreeBig2", "TreeBig3", "Big Tree", "Huge Tree" }

local function isTreeModel(m)
    if not m or not m:IsA("Model") then return false end
    local n = m.Name
    for _, s in ipairs(SMALL_TREE_NAMES) do if n == s then return true end end
    for _, s in ipairs(BIG_TREE_NAMES) do if n == s then return true end end
    return false
end

local function isBigTreeName(n)
    for _, s in ipairs(BIG_TREE_NAMES) do if n == s then return true end end
    return false
end

local function isAnimalModel(m)
    if not m or not m:IsA("Model") then return false end
    if m:FindFirstChildOfClass("Humanoid") and not m:FindFirstChild("PlayerGui") then
        -- crude heuristic: NPC / animal (not players)
        return true
    end
    return false
end

-- =====================
-- Highlighting
-- =====================
local HighlightFolder = Instance.new("Folder")
HighlightFolder.Name = "__AuraHighlights__"
HighlightFolder.Parent = Workspace

local function makeBox(target)
    local sb = Instance.new("SelectionBox")
    sb.Name = "__AuraSB"
    sb.LineThickness = CFG.HIGHLIGHT_THICKNESS
    sb.SurfaceTransparency = 1
    sb.Adornee = target
    sb.Parent = HighlightFolder
    sb.ZIndex = CFG.HIGHLIGHT_ZINDEX
    sb.Color3 = Color3.new(1, 1, 0) -- bright yellow
    return sb
end

local activeBoxes = {}  -- [Instance] = SelectionBox

local function setHighlighted(models, enabled)
    -- remove stale
    for inst, box in pairs(activeBoxes) do
        if not inst.Parent or (not enabled) then
            box:Destroy()
            activeBoxes[inst] = nil
        end
    end
    if not enabled then return end
    -- add/update
    for _, m in ipairs(models) do
        local adorn = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")) or nil
        if adorn then
            if not activeBoxes[m] then
                local sb = makeBox(adorn)
                activeBoxes[m] = sb
            else
                activeBoxes[m].Adornee = adorn
            end
        end
    end
end

-- =====================
-- Queue (for not-yet-streamed targets)
-- =====================
local Requeue = {} -- array of {model, lastSeenT, lastPos}
local function requeueTarget(model)
    if #Requeue >= CFG.QUEUE_MAX then return end
    table.insert(Requeue, { model = model, lastSeenT = now(), lastPos = model:GetPivot().Position })
end

local function pruneQueue(centerPos, active, maxRange)
    local keep = {}
    for _, q in ipairs(Requeue) do
        local m = q.model
        if m and m.Parent and active and dist(centerPos, m:GetPivot().Position) <= maxRange then
            table.insert(keep, q)
        end
    end
    Requeue = keep
end

-- =====================
-- Streaming Helpers (Aggressive Preload)
-- =====================
local function nudgeForStreaming(model)
    -- minor client-side read to encourage replication (no teleport)
    -- sample a bound and read its CFrame, then a tiny raycast toward it
    local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not pp then return false end
    local cframe = pp.CFrame
    -- Raycast a short line near it (purely client)
    local origin = cframe.Position + Vector3.new(0, 3, 0)
    local dir = Vector3.new(0, -CFG.PRELOAD_NUDGE, 0)
    Workspace:Raycast(origin, dir)
    return true
end

-- =====================
-- Remotes (best-effort lookup; no-ops if absent)
-- =====================
local Remotes = {
    ChopTree = ReplicatedStorage:FindFirstChild("ChopTree") or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("ChopTree"),
    HitEnemy = ReplicatedStorage:FindFirstChild("HitEnemy") or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("HitEnemy"),
    FeedCampfire = ReplicatedStorage:FindFirstChild("FeedCampfire") or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("FeedCampfire"),
    FeedScrapper = ReplicatedStorage:FindFirstChild("FeedScrapper") or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("FeedScrapper"),
    CollectCoin = ReplicatedStorage:FindFirstChild("CollectCoin") or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CollectCoin"),
}

local function serverChop(model)
    if Remotes.ChopTree and model then
        pcall(function()
            Remotes.ChopTree:FireServer(model)
        end)
    end
end

local function serverHitEnemy(model)
    if Remotes.HitEnemy and model then
        pcall(function()
            Remotes.HitEnemy:FireServer(model)
        end)
    end
end

local function serverFeedCampfire(cfModel)
    if Remotes.FeedCampfire and cfModel then
        pcall(function()
            Remotes.FeedCampfire:FireServer(cfModel)
        end)
    end
end

local function serverFeedScrapper(scrapModel)
    if Remotes.FeedScrapper and scrapModel then
        pcall(function()
            Remotes.FeedScrapper:FireServer(scrapModel)
        end)
    end
end

local function serverCollectCoin(coinModel)
    if Remotes.CollectCoin and coinModel then
        pcall(function()
            Remotes.CollectCoin:FireServer(coinModel)
        end)
        return true
    end
    -- Fallback: try ProximityPrompt
    local prompt = coinModel:FindFirstChildOfClass("ProximityPrompt") or coinModel:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        pcall(function()
            prompt.HoldDuration = 0
            fireproximityprompt(prompt)
        end)
        return true
    end
    return false
end

-- =====================
-- Scanners
-- =====================
local function collectTargets(centerPos, radius)
    local trees, animals = {}, {}
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") then
            local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
            if pp then
                local d = dist(centerPos, pp.Position)
                if d <= radius then
                    if isTreeModel(m) and (STATE.BigTrees or not isBigTreeName(m.Name)) then
                        table.insert(trees, m)
                    elseif isAnimalModel(m) then
                        table.insert(animals, m)
                    end
                end
            end
        end
    end
    return trees, animals
end

local function hasTreeHealth(model)
    -- many games store health as an IntValue/NumberValue/Attribute
    if model:GetAttribute("Health") then return true end
    local v = model:FindFirstChild("TreeHealth") or model:FindFirstChild("Health")
    if v and v:IsA("ValueBase") then return true end
    return false
end

-- =====================
-- Aura Loops
-- =====================
local function runChopAura()
    while true do
        task.wait(CFG.CHOP_SWING_DELAY)
        if not STATE.ChopAura then continue end
        local centerHRP = getHRP(); if not centerHRP then continue end
        local centerPos = centerHRP.Position

        local radius = STATE.VisibleOnly and 99999 or auraRadiusSliderValue
        local trees = {}
        if STATE.VisibleOnly then
            -- Use streamed models only: just see what's present and valid
            local t, _ = collectTargets(centerPos, radius)
            trees = t
        else
            local t, _ = collectTargets(centerPos, radius)
            trees = t
        end

        -- highlights for trees
        if STATE.HighlightTrees then setHighlighted(trees, true) end
        if not STATE.HighlightTrees then setHighlighted({}, false) end

        for _, tree in ipairs(trees) do
            if hasTreeHealth(tree) then
                serverChop(tree)
            else
                -- not yet streamed: only requeue if still in range and feature on
                if dist(centerPos, (tree.PrimaryPart or tree:GetPivot().Position)) <= radius then
                    if STATE.AggressivePreload then nudgeForStreaming(tree) end
                    requeueTarget(tree)
                end
            end
        end

        -- retry queue
        if #Requeue > 0 then
            task.wait(CFG.QUEUE_RETRY_SECS)
            pruneQueue(centerPos, STATE.ChopAura, radius)
            for i = #Requeue, 1, -1 do
                local q = Requeue[i]
                local m = q.model
                if not m or not m.Parent then
                    table.remove(Requeue, i)
                else
                    if hasTreeHealth(m) then
                        serverChop(m)
                        table.remove(Requeue, i)
                    else
                        if STATE.AggressivePreload then nudgeForStreaming(m) end
                        -- keep queued; prune handles leaving range
                    end
                end
            end
        end
    end
end

local function runKillAura()
    while true do
        task.wait(CFG.AURA_SWING_DELAY)
        if not STATE.KillAura then continue end
        local centerHRP = getHRP(); if not centerHRP then continue end
        local centerPos = centerHRP.Position

        local radius = STATE.VisibleOnly and 99999 or auraRadiusSliderValue
        local _, animals = collectTargets(centerPos, radius)

        -- highlights for animals
        if STATE.HighlightAnimals then setHighlighted(animals, true) end
        if not STATE.HighlightAnimals then setHighlighted({}, false) end

        for _, mob in ipairs(animals) do
            serverHitEnemy(mob)
        end
    end
end

-- =====================
-- Scrapper / Campfire Feed (prefer Scrapper movers)
-- =====================
local function nearestModelByNames(centerPos, names, maxR)
    local best, bestD = nil, math.huge
    for _, m in ipairs(Workspace:GetDescendants()) do
        if m:IsA("Model") then
            for _, name in ipairs(names) do
                if m.Name == name then
                    local pp = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if pp then
                        local d = dist(centerPos, pp.Position)
                        if d < bestD and d <= maxR then
                            best, bestD = m, d
                        end
                    end
                end
            end
        end
    end
    return best
end

local function runFeeder()
    while true do
        task.wait(CFG.FEED_SCAN_RATE)
        local hrp = getHRP(); if not hrp then continue end
        local pos = hrp.Position

        -- "Movers" -> "Scrapper" -> "Campground" rename consensus:
        -- Final world intent: Name "Campground" under Map, with "Scrapper" child containing "Movers".
        -- Prefer Scrapper movers if both are nearby.
        local scrapper = nearestModelByNames(pos, { "Scrapper" }, CFG.SCRAPPER_PREF_RADIUS)
        if scrapper then
            serverFeedScrapper(scrapper)
        else
            -- fallback to campfire in range
            local campfire = nearestModelByNames(pos, { "Campfire" }, CFG.CAMPFIRE_RADIUS)
            if campfire then
                serverFeedCampfire(campfire)
            end
        end
    end
end

-- =====================
-- Auto Collect Gold ("Coin Stack")
-- =====================
local function scanAndCollectGold()
    local items = Workspace:FindFirstChild("Items")
    if not items then return end
    for _, m in ipairs(items:GetChildren()) do
        if m:IsA("Model") and m.Name == "Coin Stack" then
            serverCollectCoin(m)
        end
    end
end

local GoldConnection

local function runGoldCollector()
    while true do
        task.wait(CFG.GOLD_SCAN_RATE)
        if not STATE.AutoCollectGold then continue end
        scanAndCollectGold()
    end
end

local function hookGoldSpawns(enabled)
    if GoldConnection then
        GoldConnection:Disconnect()
        GoldConnection = nil
    end
    if not enabled then return end
    local items = Workspace:FindFirstChild("Items")
    if not items then return end
    GoldConnection = items.ChildAdded:Connect(function(ch)
        if STATE.AutoCollectGold and ch:IsA("Model") and ch.Name == "Coin Stack" then
            task.defer(serverCollectCoin, ch)
        end
    end)
end

-- =====================
-- UI Wiring
-- =====================
TabMain:CreateToggle({
    Name = "Kill Aura",
    CurrentValue = STATE.KillAura,
    Flag = "KillAura",
    Callback = function(v) STATE.KillAura = v end
})

TabMain:CreateToggle({
    Name = "Chop Aura",
    CurrentValue = STATE.ChopAura,
    Flag = "ChopAura",
    Callback = function(v) STATE.ChopAura = v end
})

TabMain:CreateToggle({
    Name = "Big Trees",
    CurrentValue = STATE.BigTrees,
    Flag = "BigTrees",
    Callback = function(v) STATE.BigTrees = v end
})

TabMain:CreateToggle({
    Name = "Visible Only",
    CurrentValue = STATE.VisibleOnly,
    Flag = "VisibleOnly",
    Callback = function(v) STATE.VisibleOnly = v end
})

TabMain:CreateToggle({
    Name = "Aggressive Preload",
    CurrentValue = STATE.AggressivePreload,
    Flag = "AggressivePreload",
    Callback = function(v) STATE.AggressivePreload = v end
})

TabMain:CreateSection("Highlights")

TabMain:CreateToggle({
    Name = "Highlight Trees (Yellow)",
    CurrentValue = STATE.HighlightTrees,
    Flag = "HL_Trees",
    Callback = function(v) STATE.HighlightTrees = v end
})

TabMain:CreateToggle({
    Name = "Highlight Animals (Yellow)",
    CurrentValue = STATE.HighlightAnimals,
    Flag = "HL_Animals",
    Callback = function(v) STATE.HighlightAnimals = v end
})

TabMain:CreateSection("Gold")

TabMain:CreateToggle({
    Name = "Auto Collect Gold",
    CurrentValue = STATE.AutoCollectGold,
    Flag = "AutoGold",
    Callback = function(v)
        STATE.AutoCollectGold = v
        hookGoldSpawns(v)
    end
})

TabSettings:CreateSlider({
    Name = "Aura Radius",
    Range = {100, 2000},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = auraRadiusSliderValue,
    Flag = "AuraRadius",
    Callback = function(v)
        auraRadiusSliderValue = v
    end
})

TabSettings:CreateSlider({
    Name = "Chop Wave Delay",
    Range = {0.05, 1.5},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.CHOP_SWING_DELAY,
    Flag = "ChopDelay",
    Callback = function(v) CFG.CHOP_SWING_DELAY = v end
})

TabSettings:CreateSlider({
    Name = "Kill Wave Delay",
    Range = {0.05, 1.5},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.AURA_SWING_DELAY,
    Flag = "KillDelay",
    Callback = function(v) CFG.AURA_SWING_DELAY = v end
})

TabSettings:CreateSlider({
    Name = "Queue Retry",
    Range = {0.05, 1.0},
    Increment = 0.01,
    Suffix = " s",
    CurrentValue = CFG.QUEUE_RETRY_SECS,
    Flag = "QueueRetry",
    Callback = function(v) CFG.QUEUE_RETRY_SECS = v end
})

TabSettings:CreateParagraph({
    Title = "Visible Only Behavior",
    Content = "When ON, the radius slider is effectively ignored and only streamed-in models are targeted. Turn OFF to respect the slider distance."
})

-- =====================
-- Remove defunct toggles/features if present (no-ops here by design)
-- =====================
-- (Auto Feed toggle was removed; feeding is automatic with preference to Scrapper movers if in range)
-- (Auto Stun Deer removed; no related calls remain)

-- =====================
-- Start Workers
-- =====================
task.spawn(runChopAura)
task.spawn(runKillAura)
task.spawn(runFeeder)
task.spawn(runGoldCollector)
