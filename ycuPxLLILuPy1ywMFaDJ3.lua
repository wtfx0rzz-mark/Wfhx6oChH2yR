--[[
    99 Nights in the Forest | WindUI (Full Integration + Reliability Bundle)
    Includes your original features plus:
      • Reliability bundle (master ON/OFF) gating: index+lazy revalidate, token guard, sticky targeting
      • LOS gate, Chainsaw priority/lock + equip cooldowns, global RPC concurrency cap
      • Near/Mid/Far ring scheduling and per-wave caps (Near matches Axe cooldown = 0.55s)
      • Tap-only Auto Collect Gold for Workspace.Items["Coin Stack"] (no Bring fallback)
      • WindUI Debug tab to toggle reliability controls + edit Max Tokens live
      • Debug HUD (compact on-screen stats: RPC tokens, tree count, ring sizes)
]]

repeat task.wait() until game:IsLoaded()

-- =====================
-- Tunables (ORIGINAL)
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

-- =====================
-- New Reliability / Debug Tunables (ON/OFF & TIMING ONLY)
-- =====================
-- Master bundle switch (gates index+revalidate, token guard, sticky, equip locks, concurrency, LOS)
local RELIABILITY_BUNDLE_ENABLED_DEFAULT = true       -- turn entire reliability stack ON/OFF

-- Debug menu visibility (WindUI Debug side tab)
local DEBUG_MENU_ENABLED = false                        -- show Debug tab

-- Debug HUD compact line
local DEBUG_HUD_ENABLED_DEFAULT = false                 -- show small per-wave HUD counters

-- Line-of-sight gate (raycast from player → trunk before sending a hit)
local LOS_ENABLED_DEFAULT = false                       -- require LOS at hit time

-- Workspace tree index (event-driven) used for mid/far; near can scan live
local INDEX_ENABLED_DEFAULT = true                     -- maintain workspace tree index

-- Token guard (prevents over-stacking N_0000000000-like children on a tree)
local TOKEN_GUARD_ENABLED_DEFAULT = false               -- enable token guard for trees
local TOKEN_MAX_PER_BURST_DEFAULT = 3                  -- max tokens allowed before skipping this wave
local TOKEN_COOLDOWN_MS_DEFAULT   = 450                -- ms since newest token before we hit again
local TOKEN_FAIL_BACKOFF_MS_DEFAULT = 600              -- ms cooldown on server refusal/invalid state
local TOKEN_CACHE_TTL_MS_DEFAULT  = 700                -- ms to trust cached token count before re-read
local TOKEN_MAX_DEPTH_DEFAULT     = 2                  -- 1=children only, 2=shallow descendants

-- Sticky targeting (stay on the same tree until done)
local STICKY_ENABLED_DEFAULT      = false               -- keep hitting same target while valid
local STICKY_TTL_MS_DEFAULT       = 2000               -- ms to try staying on same tree
local STICKY_MAX_SKIPS_DEFAULT    = 2                  -- consecutive token/LOS skips before drop
local STICKY_CONSEC_FAILS_DEFAULT = 2                  -- consecutive server refuses/LOS fails before drop
local STICKY_RING_GRACE_MS_DEFAULT= 600                -- ms grace when target crosses ring boundary

-- Equip arbitration (Chainsaw priority, swap-lock, and cooldowns)
local CHAINSAW_PRIORITY_DEFAULT   = false               -- if Chainsaw exists, always use it for trees
local LOCK_TO_CHOP_ENABLED_DEFAULT= false              -- resist switching away from Chop during lock window
local SWAP_LOCK_MS_DEFAULT        = 1200               -- ms to resist switching away from Chop after equip
local EQUIP_COOLDOWN_MS_DEFAULT   = 600                -- ms cooldown after successful equip
local EQUIP_FAIL_COOLDOWN_MS_DEFAULT = 250             -- ms cooldown after failed equip
local CHAINSAW_USABLE_TTL_MS_DEFAULT = 7000            -- ms to suppress Chainsaw attempts after refusal (fuel)

-- Global RPC concurrency cap (token bucket)
local CONCURRENCY_CAP_ENABLED_DEFAULT = false           -- enable RPC token limiting
local RPC_MAX_TOKENS_DEFAULT          = 12             -- max concurrent RPC tokens
local RPC_TOKEN_WAIT_MS_DEFAULT       = 150            -- ms willing to wait for a token before skipping

-- Ring scheduling (Near/Mid/Far intervals & caps)
local RING_NEAR_DELAY_MS_DEFAULT     = 550             -- ms between Near waves (match Axe cooldown)
local RING_MID_DELAY_MS_DEFAULT      = 1000            -- ms between Mid waves
local RING_FAR_DELAY_MS_DEFAULT      = 1800            -- ms between Far waves
local RING_JITTER_MS_DEFAULT         = 100             -- ±ms jitter added to each ring delay
local RING_CAP_NEAR_DEFAULT          = 8               -- max hits per Near wave
local RING_CAP_MID_DEFAULT           = 4               -- max hits per Mid wave
local RING_CAP_FAR_DEFAULT           = 2               -- max hits per Far wave

-- Aura radius & multipliers (ring bounds)
local AURA_RADIUS_DEFAULT            = 50              -- studs; Near radius R (kept consistent with your UI)
local RING_MID_MULTIPLIER            = 2.0             -- Mid ring upper bound = R * 2.0
local RING_FAR_MULTIPLIER            = 3.0             -- Far ring upper bound = R * 3.0

-- Tap-only gold collection (Workspace.Items["Coin Stack"])
local GOLD_COLLECT_ENABLED_DEFAULT   = true            -- enable gold collector
local GOLD_COLLECT_PULSE_MS_DEFAULT  = 300             -- ms frequency to scan & tap coin stacks
local GOLD_COLLECT_RADIUS_DEFAULT    = 1000              -- studs; tap only within this distance

-- =====================
-- Services & UI
-- =====================
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
-- Runtime (Reliability cfg)
-- =====================
local function nowMs() return math.floor(os.clock()*1000) end
local cfg = {
    RELIABILITY = RELIABILITY_BUNDLE_ENABLED_DEFAULT,
    DEBUG_HUD   = DEBUG_HUD_ENABLED_DEFAULT,

    LOS         = LOS_ENABLED_DEFAULT,
    INDEX       = INDEX_ENABLED_DEFAULT,

    TOKEN_GUARD = TOKEN_GUARD_ENABLED_DEFAULT,
    TOKEN_MAX   = TOKEN_MAX_PER_BURST_DEFAULT,
    TOKEN_COOL  = TOKEN_COOLDOWN_MS_DEFAULT,
    TOKEN_BACK  = TOKEN_FAIL_BACKOFF_MS_DEFAULT,
    TOKEN_TTL   = TOKEN_CACHE_TTL_MS_DEFAULT,
    TOKEN_DEPTH = TOKEN_MAX_DEPTH_DEFAULT,

    STICKY      = STICKY_ENABLED_DEFAULT,
    STICKY_TTL  = STICKY_TTL_MS_DEFAULT,
    STICKY_SKIPS= STICKY_MAX_SKIPS_DEFAULT,
    STICKY_FAILS= STICKY_CONSEC_FAILS_DEFAULT,
    STICKY_GRACE= STICKY_RING_GRACE_MS_DEFAULT,

    CHAINSAW_PRIORITY = CHAINSAW_PRIORITY_DEFAULT,
    LOCK_TO_CHOP      = LOCK_TO_CHOP_ENABLED_DEFAULT,
    SWAP_LOCK_MS      = SWAP_LOCK_MS_DEFAULT,
    EQUIP_CD_MS       = EQUIP_COOLDOWN_MS_DEFAULT,
    EQUIP_FAIL_MS     = EQUIP_FAIL_COOLDOWN_MS_DEFAULT,
    CHAINSAW_TTL_MS   = CHAINSAW_USABLE_TTL_MS_DEFAULT,

    CONCURRENCY       = CONCURRENCY_CAP_ENABLED_DEFAULT,
    RPC_MAX_TOKENS    = RPC_MAX_TOKENS_DEFAULT,
    RPC_WAIT_MS       = RPC_TOKEN_WAIT_MS_DEFAULT,

    NEAR_MS   = RING_NEAR_DELAY_MS_DEFAULT,
    MID_MS    = RING_MID_DELAY_MS_DEFAULT,
    FAR_MS    = RING_FAR_DELAY_MS_DEFAULT,
    JITTER_MS = RING_JITTER_MS_DEFAULT,
    CAP_NEAR  = RING_CAP_NEAR_DEFAULT,
    CAP_MID   = RING_CAP_MID_DEFAULT,
    CAP_FAR   = RING_CAP_FAR_DEFAULT,

    RADIUS    = AURA_RADIUS_DEFAULT,
    MID_MULT  = RING_MID_MULTIPLIER,
    FAR_MULT  = RING_FAR_MULTIPLIER,

    GOLD      = GOLD_COLLECT_ENABLED_DEFAULT,
    GOLD_MS   = GOLD_COLLECT_PULSE_MS_DEFAULT,
    GOLD_R    = GOLD_COLLECT_RADIUS_DEFAULT,
}

-- =====================
-- Debug HUD
-- =====================
local DebugHudGui = nil
local function toggleDebugHud(state)
    if state then
        if not DebugHudGui then
            DebugHudGui = Instance.new("ScreenGui")
            DebugHudGui.Name = "DebugHud"
            DebugHudGui.Parent = game.CoreGui
            local frame = Instance.new("Frame", DebugHudGui)
            frame.Size = UDim2.new(0, 300, 0, 20)
            frame.Position = UDim2.new(0.5, -150, 0, 0)
            frame.BackgroundTransparency = 0.5
            frame.BackgroundColor3 = Color3.new(0, 0, 0)
            local label = Instance.new("TextLabel", frame)
            label.Size = UDim2.new(1, 0, 1, 0)
            label.TextColor3 = Color3.new(1, 1, 1)
            label.BackgroundTransparency = 1
            label.Text = "Debug: initializing..."
            label.TextSize = 14
            label.Font = Enum.Font.Code
        end
        task.spawn(function()
            while cfg.DEBUG_HUD and DebugHudGui do
                local nearCount = #selectByRing("NEAR")
                local midCount = #selectByRing("MID")
                local farCount = #selectByRing("FAR")
                local totalTrees = 0
                for _ in pairs(TreeIndex) do totalTrees = totalTrees + 1 end
                DebugHudGui.Frame.TextLabel.Text = string.format("RPC: %d/%d | Trees: %d | Near: %d | Mid: %d | Far: %d", rpcTokens.used, rpcTokens.max, totalTrees, nearCount, midCount, farCount)
                task.wait(0.5)
            end
        end)
    else
        if DebugHudGui then DebugHudGui:Destroy() DebugHudGui = nil end
    end
end

-- =====================
-- Combat state
-- =====================
local killAuraToggle = false
local chopAuraToggle = false
local bigTreeAuraToggle = false
local auraRadius = cfg.RADIUS

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
-- Reliability helpers (equip locks / concurrency / LOS / tokens / index / sticky)
-- =====================
local rpcTokens = { used=0, max=cfg.RPC_MAX_TOKENS }
local lastEquipAt, lastEquipFailAt, swapLockUntil, chainsawSuppressedUntil = 0,0,0,0

local function takeToken()
    if not (cfg.RELIABILITY and cfg.CONCURRENCY) then return true end
    if rpcTokens.used < rpcTokens.max then rpcTokens.used += 1; return true end
    return false
end
local function releaseToken()
    if not (cfg.RELIABILITY and cfg.CONCURRENCY) then return end
    rpcTokens.used = math.max(0, rpcTokens.used - 1)
end
local function waitForToken(timeoutMs)
    if not (cfg.RELIABILITY and cfg.CONCURRENCY) then return true end
    local deadline = nowMs() + (timeoutMs or 0)
    while rpcTokens.used >= rpcTokens.max and nowMs() < deadline do
        RunService.Heartbeat:Wait()
    end
    return takeToken()
end

local function chainsawTool() return findInInventory("Chainsaw") end
local function bestAxe()
    local order = {"Old Axe","Good Axe","Strong Axe"}
    for i=#order,1,-1 do
        local t = findInInventory(order[i])
        if t then return t, order[i] end
    end
end
local function toolEquipped(name)
    local tool = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Tool")
    return tool and tool.Name == name
end
local function ensureChopToolReliably()
    local now = nowMs()
    if cfg.RELIABILITY and cfg.LOCK_TO_CHOP and now < swapLockUntil then
        return true
    end
    if cfg.RELIABILITY and (now - lastEquipAt) < cfg.EQUIP_CD_MS then
        return toolEquipped("Chainsaw") or toolEquipped("Strong Axe") or toolEquipped("Good Axe") or toolEquipped("Old Axe")
    end
    if cfg.RELIABILITY and (now - lastEquipFailAt) < cfg.EQUIP_FAIL_MS then
        return toolEquipped("Chainsaw") or toolEquipped("Strong Axe") or toolEquipped("Good Axe") or toolEquipped("Old Axe")
    end
    local targetName, toolInst
    if cfg.CHAINSAW_PRIORITY and now >= chainsawSuppressedUntil then
        toolInst = chainsawTool()
        targetName = toolInst and "Chainsaw" or nil
    end
    if not toolInst then
        toolInst, targetName = bestAxe()
    end
    if not targetName then
        lastEquipFailAt = nowMs()
        return false
    end
    local okTool = ensureEquipped(targetName)
    if not okTool then
        lastEquipFailAt = nowMs()
        return false
    end
    lastEquipAt = nowMs()
    if cfg.RELIABILITY and cfg.LOCK_TO_CHOP then swapLockUntil = lastEquipAt + cfg.SWAP_LOCK_MS end
    return true
end
local function demoteChainsawTTL() chainsawSuppressedUntil = nowMs() + cfg.CHAINSAW_TTL_MS end

-- LOS
local function losPass(origin, targetPart)
    if not (cfg.RELIABILITY and cfg.LOS) then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { LocalPlayer.Character }
    local dir = (targetPart.Position - origin)
    local result = Workspace:Raycast(origin, dir, params)
    if not result then return true end
    return result.Instance:IsDescendantOf(targetPart.Parent)
end

-- Tree index & token guard
local TreeIndex = {} -- [Model] = { model=Model, trunk=BasePart, lastSeen=ms, cooldownUntil=ms, token={when, count, newest} }
local function isSmallOrBigTree(m)
    return (m and m:IsA("Model") and (m.Name == TREE_NAME or BIG_TREE_NAMES[m.Name] == true))
end
local function treeTrunk(m)
    if not m or not m:IsA("Model") then return nil end
    if m:FindFirstChild("Trunk") and m.Trunk:IsA("BasePart") then return m.Trunk end
    if m.PrimaryPart then return m.PrimaryPart end
    return m:FindFirstChildWhichIsA("BasePart")
end
local function upsertTree(m)
    if not isSmallOrBigTree(m) then return end
    local tr = treeTrunk(m); if not tr then return end
    local rec = TreeIndex[m]
    if not rec then
        TreeIndex[m] = { model=m, trunk=tr, lastSeen=nowMs(), cooldownUntil=0, token={when=0,count=0,newest=0} }
    else
        rec.trunk = tr; rec.lastSeen=nowMs()
    end
end
local function evictTree(m) TreeIndex[m] = nil end
local function buildInitialIndex()
    if not (cfg.RELIABILITY and cfg.INDEX) then return end
    for _,d in ipairs(Workspace:GetDescendants()) do if isSmallOrBigTree(d) then upsertTree(d) end end
end
local function hookIndexSignals()
    if not (cfg.RELIABILITY and cfg.INDEX) then return end
    Workspace.DescendantAdded:Connect(function(inst) if isSmallOrBigTree(inst) then upsertTree(inst) end end)
    Workspace.DescendantRemoving:Connect(function(inst) if TreeIndex[inst] then evictTree(inst) end end)
end
local TOKEN_PATTERN = "^(%d+)_(%d%d%d%d%d%d%d%d%d%d)$"
local function readTokens(model, maxDepth, earlyStop)
    local count, newest = 0, 0
    local function check(inst)
        if count >= earlyStop then return true end
        local a,b = string.match(inst.Name, TOKEN_PATTERN)
        if a and b then
            count += 1
            local ts = tonumber(b) or 0
            if ts > newest then newest = ts end
            if count >= earlyStop then return true end
        end
        return false
    end
    for _,c in ipairs(model:GetChildren()) do if check(c) then return count, newest end end
    if maxDepth >= 2 then
        for _,d in ipairs(model:GetDescendants()) do if check(d) then return count, newest end end
    end
    return count, newest
end
local function tokenGuardPass(rec)
    if not (cfg.RELIABILITY and cfg.TOKEN_GUARD) then return true end
    local now = nowMs()
    if rec.cooldownUntil > now then return false end
    if (now - rec.token.when) > cfg.TOKEN_TTL then
        local c, newest = readTokens(rec.model, cfg.TOKEN_DEPTH, cfg.TOKEN_MAX)
        rec.token.when, rec.token.count, rec.token.newest = now, c, newest
    end
    if rec.token.count >= cfg.TOKEN_MAX then rec.cooldownUntil = now + cfg.TOKEN_COOL; return false end
    if rec.token.newest > 0 and (now - rec.token.newest) < cfg.TOKEN_COOL then rec.cooldownUntil = now + cfg.TOKEN_COOL; return false end
    return true
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
-- Reliability-aware Hit Sender
-- =====================
local function sendTreeHit(treeModel, toolName)
    if not ToolDamageObject then return false, "no_remote" end
    local trunk = bestTreeHitPart(treeModel) or treeModel.PrimaryPart
    if not trunk then return false, "no_trunk" end

    if not losPass((LocalPlayer.Character and LocalPlayer.Character:WaitForChild("HumanoidRootPart").Position) or trunk.Position, trunk) then
        return false, "los"
    end

    if not ensureChopToolReliably() then return false, "equip" end

    if cfg.CONCURRENCY and not waitForToken(cfg.RPC_WAIT_MS) then return false, "tokens" end
    local ok, err = pcall(function()
        local tool = findInInventory(toolName or (equippedToolName() or ""))
        local hitId = nextHitId()
        local impactCF = computeImpactCFrame(treeModel, trunk)
        ToolDamageObject:InvokeServer(treeModel, tool, hitId, impactCF)
    end)
    if cfg.CONCURRENCY then releaseToken() end
    if not ok then
        if err and tostring(err):lower():find("fuel") then demoteChainsawTTL() end
        return false, tostring(err or "invoke_failed")
    end
    return true
end

-- =====================
-- Aura loops (Kill unchanged; Chop/BigTree now use ring scheduling + index/guards)
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

-- Ring helpers
local function ringBounds()
    local R = auraRadius
    return R, R*cfg.MID_MULT, R*cfg.FAR_MULT
end
local function d2(a,b) return (a-b).Magnitude^2 end
local function jitter(ms)
    local j = cfg.JITTER_MS
    if j <= 0 then return ms end
    local r = (math.random()*2 - 1) * j
    return math.max(10, ms + r)
end

local STICKY = { NEAR={t=nil,since=0,skips=0,fails=0}, MID={t=nil,since=0,skips=0,fails=0}, FAR={t=nil,since=0,skips=0,fails=0} }
local function stickyDrop(name) STICKY[name].t=nil; STICKY[name].since=0; STICKY[name].skips=0; STICKY[name].fails=0 end

local function tokenPass(rec)
    if not (cfg.RELIABILITY and cfg.TOKEN_GUARD) then return true end
    return tokenGuardPass(rec)
end

local function selectByRing(ring)
    local result = {}
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character:WaitForChild("HumanoidRootPart")
    local pos = hrp.Position
    local R,M,F = ringBounds(); local R2,R4,R9 = R*R, (R*cfg.MID_MULT)^2, (R*cfg.FAR_MULT)^2

    for m,rec in pairs(TreeIndex) do
        if m and m.Parent and rec.trunk and rec.trunk.Parent then
            local dist2 = d2(pos, rec.trunk.Position)
            if ring=="NEAR" and dist2 <= R2 then
                if (not bigTreeAuraToggle and m.Name==TREE_NAME) or (bigTreeAuraToggle and BIG_TREE_NAMES[m.Name]) or (chopAuraToggle and m.Name==TREE_NAME) then
                    table.insert(result, rec)
                end
            elseif ring=="MID" and dist2 > R2 and dist2 <= R4 then
                if (not bigTreeAuraToggle and m.Name==TREE_NAME) or (bigTreeAuraToggle and BIG_TREE_NAMES[m.Name]) or (chopAuraToggle and m.Name==TREE_NAME) then
                    table.insert(result, rec)
                end
            elseif ring=="FAR" and dist2 > R4 and dist2 <= R9 then
                if (not bigTreeAuraToggle and m.Name==TREE_NAME) or (bigTreeAuraToggle and BIG_TREE_NAMES[m.Name]) or (chopAuraToggle and m.Name==TREE_NAME) then
                    table.insert(result, rec)
                end
            end
        end
    end
    table.sort(result, function(a,b)
        return (a.trunk.Position - pos).Magnitude < (b.trunk.Position - pos).Magnitude
    end)
    return result
end

local function withinRing(rec, ring)
    local pos = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.CharacterAdded:Wait():WaitForChild("HumanoidRootPart")).Position
    local R,M,F = ringBounds()
    local d = (rec.trunk.Position - pos).Magnitude
    if ring=="NEAR" then return d <= R end
    if ring=="MID"  then return d > R and d <= M end
    if ring=="FAR"  then return d > M and d <= F end
    return false
end

local function tryHit(rec, ring)
    if not tokenPass(rec) then
        local s=STICKY[ring]; if s.t==rec then s.skips += 1 end
        return false
    end
    local ok, err = sendTreeHit(rec.model, equippedToolName())
    if ok then
        rec.token.when = 0
        return true
    else
        if err=="los" or err=="equip" then
            local s=STICKY[ring]; if s.t==rec then s.fails += 1 end
        else
            rec.cooldownUntil = nowMs() + cfg.TOKEN_BACK
            local s=STICKY[ring]; if s.t==rec then s.fails += 1 end
        end
        return false
    end
end

local function updateSticky(ring, candidates)
    local s = STICKY[ring]
    local now = nowMs()
    if s.t and (not s.t.model or not s.t.model.Parent) then stickyDrop(ring) end
    if s.t then
        if not withinRing(s.t, ring) and (now - s.since) > cfg.STICKY_GRACE then stickyDrop(ring) end
        if cfg.STICKY and (now - s.since) > cfg.STICKY_TTL then stickyDrop(ring) end
        if s.skips >= cfg.STICKY_SKIPS or s.fails >= cfg.STICKY_FAILS then stickyDrop(ring) end
    end
    if not s.t and #candidates>0 then s.t = candidates[1]; s.since=now; s.skips=0; s.fails=0 end
end

local function ringWave(ringName, cap)
    local list = selectByRing(ringName)
    updateSticky(ringName, list)

    local sent = 0
    local s = STICKY[ringName]
    if s.t then if tryHit(s.t, ringName) then sent+=1 end end
    for _,rec in ipairs(list) do
        if sent >= cap then break end
        if s.t ~= rec then if tryHit(rec, ringName) then sent += 1 end end
    end
end

local function chopScheduler()
    -- Build & hook index once
    if cfg.RELIABILITY and cfg.INDEX then buildInitialIndex(); hookIndexSignals()
    else -- near-only scan bootstrap when index is disabled
        for _,d in ipairs(Workspace:GetDescendants()) do if isSmallOrBigTree(d) then upsertTree(d) end end
    end

    while chopAuraToggle or bigTreeAuraToggle do
        -- Near wave
        task.wait(jitter(cfg.NEAR_MS)/1000)
        if chopAuraToggle or bigTreeAuraToggle then ringWave("NEAR", cfg.CAP_NEAR) end
        -- Mid
        task.wait(jitter(cfg.MID_MS)/1000)
        if chopAuraToggle or bigTreeAuraToggle then ringWave("MID", cfg.CAP_MID) end
        -- Far
        task.wait(jitter(cfg.FAR_MS)/1000)
        if chopAuraToggle or bigTreeAuraToggle then ringWave("FAR", cfg.CAP_FAR) end
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
Tabs.Debug  = Window:Tab({ Title="Debug",  Icon="settings",   Desc="Reliability controls" })
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
        if state then task.spawn(chopScheduler) end
    end
})
Tabs.Combat:Toggle({
    Title = "Big Trees",
    Value = false,
    Callback = function(state)
        bigTreeAuraToggle = state
        if state then task.spawn(chopScheduler) end
    end
})
Tabs.Combat:Section({ Title="Settings", Icon="settings" })
Tabs.Combat:Slider({
    Title = "Aura Radius",
    Value = { Min=50, Max=2000, Default=50 },
    Callback = function(value) auraRadius = math.clamp(value, 10, 2000); cfg.RADIUS = auraRadius end
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
Tabs.Main:Toggle({
    Title = "Auto Collect Gold",
    Value = false,
    Callback = function(state)
        autoGold = state
        if state then
            task.spawn(function()
                local itemsFolder = Workspace:FindFirstChild("Items")
                while autoGold do
                    task.wait(cfg.GOLD and (cfg.GOLD_MS/1000) or 0.3)
                    itemsFolder = itemsFolder or Workspace:FindFirstChild("Items")
                    if not itemsFolder then continue end
                    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if not hrp then continue end
                    for _,child in ipairs(itemsFolder:GetChildren()) do
                        if child.Name == "Coin Stack" then
                            local p = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart")
                            if p and (p.Position - hrp.Position).Magnitude <= cfg.GOLD_R then
                                local cd = child:FindFirstChildOfClass("ClickDetector")
                                if cd then pcall(function() fireclickdetector(cd) end) end
                            end
                        end
                    end
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

local ie = {"Bandage","Bolt","Broken Fan","Broken Microwave","Cake","Carrot","Chair","Coal","Coin Stack",
    "Cooked Morsel","Cooked Steak","Fuel Canister","Iron Body","Leather Armor","Log","MadKit","Metal Chair",
    "MedKit","Old Car Engine","Old Flashlight","Old Radio","Revolver","Revolver Ammo","Rifle","Rifle Ammo",
    "Morsel","Sheet Metal","Steak","Tyre","Washing Machine"}
local me = {"Bunny","Wolf","Alpha Wolf","Bear","Cultist","Crossbow Cultist","Alien"}

local selectedItems, selectedMobs = {}, {}
local espItemsEnabled, espMobsEnabled = false, false
local espConnections = {}

Tabs.esp:Section({ Title="Esp Items", Icon="package" })
Tabs.esp:Dropdown({
    Title = "Esp Items", Values=ie, Value={}, Multi=true, AllowNone=true,
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

-- =====================
-- Debug Tab UI
-- =====================
Tabs.Debug:Section({ Title="Master", Icon="settings" })
Tabs.Debug:Toggle({
    Title = "Reliability Bundle",
    Value = cfg.RELIABILITY,
    Callback = function(v) cfg.RELIABILITY = v end
})
Tabs.Debug:Toggle({
    Title = "Debug HUD",
    Value = cfg.DEBUG_HUD,
    Callback = function(v) cfg.DEBUG_HUD = v; toggleDebugHud(v) end
})

Tabs.Debug:Section({ Title="Guards", Icon="shield" })
Tabs.Debug:Toggle({
    Title = "LOS Gate",
    Value = cfg.LOS,
    Callback = function(v) cfg.LOS = v end
})
Tabs.Debug:Toggle({
    Title = "Tree Index",
    Value = cfg.INDEX,
    Callback = function(v) cfg.INDEX = v end
})
Tabs.Debug:Toggle({
    Title = "Token Guard",
    Value = cfg.TOKEN_GUARD,
    Callback = function(v) cfg.TOKEN_GUARD = v end
})
Tabs.Debug:Slider({
    Title = "Max Tokens/Burst",
    Value = { Min=1, Max=10, Default=cfg.TOKEN_MAX },
    Callback = function(v) cfg.TOKEN_MAX = v end
})
Tabs.Debug:Slider({
    Title = "Token Cooldown (ms)",
    Value = { Min=100, Max=1000, Default=cfg.TOKEN_COOL },
    Callback = function(v) cfg.TOKEN_COOL = v end
})
Tabs.Debug:Slider({
    Title = "Fail Backoff (ms)",
    Value = { Min=200, Max=2000, Default=cfg.TOKEN_BACK },
    Callback = function(v) cfg.TOKEN_BACK = v end
})
Tabs.Debug:Slider({
    Title = "Token Cache TTL (ms)",
    Value = { Min=200, Max=2000, Default=cfg.TOKEN_TTL },
    Callback = function(v) cfg.TOKEN_TTL = v end
})
Tabs.Debug:Slider({
    Title = "Token Depth",
    Value = { Min=1, Max=3, Default=cfg.TOKEN_DEPTH },
    Callback = function(v) cfg.TOKEN_DEPTH = v end
})

Tabs.Debug:Section({ Title="Sticky", Icon="link" })
Tabs.Debug:Toggle({
    Title = "Sticky Targeting",
    Value = cfg.STICKY,
    Callback = function(v) cfg.STICKY = v end
})
Tabs.Debug:Slider({
    Title = "Sticky TTL (ms)",
    Value = { Min=500, Max=5000, Default=cfg.STICKY_TTL },
    Callback = function(v) cfg.STICKY_TTL = v end
})
Tabs.Debug:Slider({
    Title = "Max Skips",
    Value = { Min=1, Max=5, Default=cfg.STICKY_SKIPS },
    Callback = function(v) cfg.STICKY_SKIPS = v end
})
Tabs.Debug:Slider({
    Title = "Consec Fails",
    Value = { Min=1, Max=5, Default=cfg.STICKY_FAILS },
    Callback = function(v) cfg.STICKY_FAILS = v end
})
Tabs.Debug:Slider({
    Title = "Ring Grace (ms)",
    Value = { Min=200, Max=2000, Default=cfg.STICKY_GRACE },
    Callback = function(v) cfg.STICKY_GRACE = v end
})

Tabs.Debug:Section({ Title="Equip", Icon="tool" })
Tabs.Debug:Toggle({
    Title = "Chainsaw Priority",
    Value = cfg.CHAINSAW_PRIORITY,
    Callback = function(v) cfg.CHAINSAW_PRIORITY = v end
})
Tabs.Debug:Toggle({
    Title = "Lock to Chop",
    Value = cfg.LOCK_TO_CHOP,
    Callback = function(v) cfg.LOCK_TO_CHOP = v end
})
Tabs.Debug:Slider({
    Title = "Swap Lock (ms)",
    Value = { Min=500, Max=3000, Default=cfg.SWAP_LOCK_MS },
    Callback = function(v) cfg.SWAP_LOCK_MS = v end
})
Tabs.Debug:Slider({
    Title = "Equip CD (ms)",
    Value = { Min=200, Max=2000, Default=cfg.EQUIP_CD_MS },
    Callback = function(v) cfg.EQUIP_CD_MS = v end
})
Tabs.Debug:Slider({
    Title = "Equip Fail CD (ms)",
    Value = { Min=100, Max=1000, Default=cfg.EQUIP_FAIL_MS },
    Callback = function(v) cfg.EQUIP_FAIL_MS = v end
})
Tabs.Debug:Slider({
    Title = "Chainsaw TTL (ms)",
    Value = { Min=2000, Max=10000, Default=cfg.CHAINSAW_TTL_MS },
    Callback = function(v) cfg.CHAINSAW_TTL_MS = v end
})

Tabs.Debug:Section({ Title="Concurrency", Icon="activity" })
Tabs.Debug:Toggle({
    Title = "RPC Cap",
    Value = cfg.CONCURRENCY,
    Callback = function(v) cfg.CONCURRENCY = v end
})
Tabs.Debug:Slider({
    Title = "Max Tokens",
    Value = { Min=5, Max=20, Default=cfg.RPC_MAX_TOKENS },
    Callback = function(v) cfg.RPC_MAX_TOKENS = v; rpcTokens.max = v end
})
Tabs.Debug:Slider({
    Title = "Wait MS",
    Value = { Min=50, Max=500, Default=cfg.RPC_WAIT_MS },
    Callback = function(v) cfg.RPC_WAIT_MS = v end
})

Tabs.Debug:Section({ Title="Rings", Icon="circle" })
Tabs.Debug:Slider({
    Title = "Near Delay (ms)",
    Value = { Min=200, Max=1000, Default=cfg.NEAR_MS },
    Callback = function(v) cfg.NEAR_MS = v end
})
Tabs.Debug:Slider({
    Title = "Mid Delay (ms)",
    Value = { Min=500, Max=2000, Default=cfg.MID_MS },
    Callback = function(v) cfg.MID_MS = v end
})
Tabs.Debug:Slider({
    Title = "Far Delay (ms)",
    Value = { Min=1000, Max=3000, Default=cfg.FAR_MS },
    Callback = function(v) cfg.FAR_MS = v end
})
Tabs.Debug:Slider({
    Title = "Jitter ±ms",
    Value = { Min=0, Max=200, Default=cfg.JITTER_MS },
    Callback = function(v) cfg.JITTER_MS = v end
})
Tabs.Debug:Slider({
    Title = "Near Cap",
    Value = { Min=2, Max=20, Default=cfg.CAP_NEAR },
    Callback = function(v) cfg.CAP_NEAR = v end
})
Tabs.Debug:Slider({
    Title = "Mid Cap",
    Value = { Min=1, Max=10, Default=cfg.CAP_MID },
    Callback = function(v) cfg.CAP_MID = v end
})
Tabs.Debug:Slider({
    Title = "Far Cap",
    Value = { Min=1, Max=5, Default=cfg.CAP_FAR },
    Callback = function(v) cfg.CAP_FAR = v end
})
Tabs.Debug:Slider({
    Title = "Mid Mult",
    Value = { Min=1.5, Max=3, Default=cfg.MID_MULT, Increment=0.1 },
    Callback = function(v) cfg.MID_MULT = v end
})
Tabs.Debug:Slider({
    Title = "Far Mult",
    Value = { Min=2.5, Max=5, Default=cfg.FAR_MULT, Increment=0.1 },
    Callback = function(v) cfg.FAR_MULT = v end
})

Tabs.Debug:Section({ Title="Gold", Icon="dollar-sign" })
Tabs.Debug:Toggle({
    Title = "Gold Collect",
    Value = cfg.GOLD,
    Callback = function(v) cfg.GOLD = v end
})
Tabs.Debug:Slider({
    Title = "Pulse MS",
    Value = { Min=100, Max=1000, Default=cfg.GOLD_MS },
    Callback = function(v) cfg.GOLD_MS = v end
})
Tabs.Debug:Slider({
    Title = "Radius",
    Value = { Min=10, Max=100, Default=cfg.GOLD_R },
    Callback = function(v) cfg.GOLD_R = v end
})

-- Initialize Debug HUD if default enabled
if cfg.DEBUG_HUD then toggleDebugHud(true) end
