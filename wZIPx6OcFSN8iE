--[[

Full script with:
- Your original UI tabs: "Scripts", "Humanoid", "Fix", plus a new "99" tab
- Fly / Noclip / Speed / Jump / Phase / Teleport (your baseline)
- Hitbox visuals manager (unchanged)
- Final baseline TREE chop (parallel wave, attribute-based) — unchanged logic
- Final baseline CHARACTER/ANIMAL kill (parallel wave) — unchanged logic
- 99 Tab:
   • "Damage Trees" [toggle] + "Tree Range" [slider]
   • "Damage Characters" [toggle] + "Character Range" [slider]

Notes:
- Uses Rayfield (CreateTab id 4483362458 as before)
- Keeps logic/steps identical to your working baseline (equip, computeImpactCF, nextHitId, InvokeServer)
- Parallel dispatch: all in-range trees characters are hit at once each wave, with a single global SWING_DELAY

]]--

--==================================================
-- Rayfield UI
--==================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

--==================================================
-- Services / locals
--==================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local playerGui   = LocalPlayer:WaitForChild("PlayerGui")

--==== Remotes used by the final working baseline ====
local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents")

-- These names are from your working baseline
local EquipItemHandle       = Remotes:WaitForChild("EquipItemHandle")
local PlayEnemyHitSound     = Remotes:WaitForChild("PlayEnemyHitSound")
local ToolDamageObject      = Remotes:WaitForChild("ToolDamageObject")
local RequestReplicateSound = Remotes:FindFirstChild("RequestReplicateSound") -- optional

--==================================================
-- Window
--==================================================
local Window = Rayfield:CreateWindow({
    Name = "Mark's SuperHuman OP Script",
    LoadingTitle = "Universal Edition",
    LoadingSubtitle = "by Mark!1!!",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = nil,
        FileName = "MarkUniversalSettings"
    },
    Discord = { Enabled = false, Invite = "", RememberJoins = false },
    KeySystem = false
})

--==================================================
-- Core state / movement (your baseline)
--==================================================
local hum, hrp

local DESIRED_SPEED = 75
local DESIRED_JUMP  = 70
local PHASE_DIST    = 10
local markedCF      = nil

-- Fly
local FLY_SPEED = 80
local FLY_VERT_SPEED = 80
local PITCH_DEADZONE = 0.22
local flying = false
local flyConn = nil
local desiredPos = nil
local savedAutoRotate = nil
local lastFaceDir = nil
local flyEnabledDesired = false

-- Noclip
local noclipEnabled = false
local noclipWhileFlying = false
local savedCollide = {}

-- Humanoid reset / baseline
local baselineCaptured = false
local baseline = {
    Health=nil, MaxHealth=nil, HipHeight=nil, DisplayName=nil, BreakJointsOnDeath=nil
}

-- Humanoid tab widgets
local HumanoidTab
local HealthInput, MaxHealthInput, HipHeightInput, DisplayNameInput
local BJD_Toggle, HReset_Toggle
local healthResetEnabled = false
local healthConn
local isRestoringHealth = false

-- UI toggle refs we need to update from Fix tab
local FlyToggle, NoclipToggle

--==================================================
-- Hitbox Visuals Manager (unchanged)
--==================================================
local hitboxFolder = Instance.new("Folder")
hitboxFolder.Name = "HitboxVisuals"
hitboxFolder.Parent = workspace

-- mode: "off" | "invisible" | "outline" | "hologram"
local hitboxMode = "off"
local charAddedConns = {}
local playerAddedConn = nil
local playerRemovingConn = nil
local invisScanConn = nil

local OUTLINE_COLOR = Color3.fromRGB(255, 170, 0)
local BOX_COLOR     = Color3.fromRGB(180, 255, 255)
local BOX_TRANS     = 0.60

local function ensureHighlight(model: Model)
    local hl = model:FindFirstChildOfClass("Highlight")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Parent = model
    end
    hl.OutlineColor        = OUTLINE_COLOR
    hl.OutlineTransparency = 0
    hl.FillColor           = OUTLINE_COLOR
    hl.FillTransparency    = 0.92
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    return hl
end

local function ensureBox(part: BasePart)
    local tagName = "HB_" .. part:GetDebugId()
    local adorn = hitboxFolder:FindFirstChild(tagName)
    if not adorn then
        adorn = Instance.new("BoxHandleAdornment")
        adorn.Name = tagName
        adorn.Adornee = part
        adorn.AlwaysOnTop = true
        adorn.Color3 = BOX_COLOR
        adorn.Transparency = BOX_TRANS
        adorn.Size = part.Size
        adorn.ZIndex = 0
        adorn.Parent = hitboxFolder
    else
        adorn.Adornee = part
        adorn.Size = part.Size
        adorn.AlwaysOnTop = true
    end
    adorn.Visible = true
    return adorn
end

local function removeVisualsForCharacter(char: Model)
    if not char then return end
    local hl = char:FindFirstChildOfClass("Highlight")
    if hl then hl:Destroy() end
    for _,d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            local tag = "HB_" .. d:GetDebugId()
            local adorn = hitboxFolder:FindFirstChild(tag)
            if adorn then adorn:Destroy() end
        end
    end
end

local function clearAllHitboxVisuals()
    for plr,conn in pairs(charAddedConns) do
        if conn then conn:Disconnect() end
        charAddedConns[plr] = nil
    end
    if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn = nil end
    if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn = nil end
    if invisScanConn then invisScanConn:Disconnect(); invisScanConn = nil end
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            removeVisualsForCharacter(plr.Character)
        end
    end
    for _,obj in ipairs(hitboxFolder:GetChildren()) do
        obj:Destroy()
    end
end

local function characterIsInvisible(char: Model): boolean
    local parts, invisible = 0, 0
    for _,d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            parts += 1
            local t = d.Transparency or 0
            local ltm = 0
            local ok, val = pcall(function() return d.LocalTransparencyModifier end)
            if ok and type(val) == "number" then ltm = val end
            if (t >= 0.95) or (ltm >= 0.95) then
                invisible += 1
            end
        end
    end
    if parts == 0 then return false end
    return (invisible / parts) >= 0.6
end

local function applyOutlineModeTo(char: Model)
    ensureHighlight(char)
end

local function applyHologramModeTo(char: Model)
    ensureHighlight(char)
    for _,d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            ensureBox(d)
        end
    end
end

local function applyInvisibleOnlyTo(char: Model)
    if characterIsInvisible(char) then
        ensureHighlight(char)
        local hrp2 = char:FindFirstChild("HumanoidRootPart")
        if hrp2 and hrp2:IsA("BasePart") then
            ensureBox(hrp2)
        end
    else
        removeVisualsForCharacter(char)
    end
end

local function attachPlayerLifecycle(applier)
    if playerAddedConn then playerAddedConn:Disconnect(); playerAddedConn = nil end
    if playerRemovingConn then playerRemovingConn:Disconnect(); playerRemovingConn = nil end

    playerAddedConn = Players.PlayerAdded:Connect(function(plr)
        if plr == LocalPlayer then return end
        if plr.Character then applier(plr.Character) end
        if charAddedConns[plr] then charAddedConns[plr]:Disconnect() end
        charAddedConns[plr] = plr.CharacterAdded:Connect(function(newChar)
            applier(newChar)
        end)
    end)

    playerRemovingConn = Players.PlayerRemoving:Connect(function(plr)
        if charAddedConns[plr] then charAddedConns[plr]:Disconnect(); charAddedConns[plr] = nil end
        if plr.Character then removeVisualsForCharacter(plr.Character) end
    end)
end

local function setHitboxMode(mode: string)
    if mode == hitboxMode then return end
    clearAllHitboxVisuals()
    hitboxMode = mode

    if mode == "off" then return end

    local applier
    if mode == "outline" then
        applier = applyOutlineModeTo
    elseif mode == "hologram" then
        applier = applyHologramModeTo
    elseif mode == "invisible" then
        applier = applyInvisibleOnlyTo
    end

    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            applier(plr.Character)
        end
        if plr ~= LocalPlayer then
            if charAddedConns[plr] then charAddedConns[plr]:Disconnect() end
            charAddedConns[plr] = plr.CharacterAdded:Connect(function(newChar)
                applier(newChar)
            end)
        end
    end

    attachPlayerLifecycle(applier)

    if mode == "invisible" then
        local acc = 0
        invisScanConn = RunService.Heartbeat:Connect(function(dt)
            acc += dt
            if acc >= 0.5 then
                acc = 0
                for _,plr in ipairs(Players:GetPlayers()) do
                    if plr ~= LocalPlayer and plr.Character then
                        applyInvisibleOnlyTo(plr.Character)
                    end
                end
            end
        end)
    end
end

--==================================================
-- Character bind / baseline movement
--==================================================
local function applyStats()
    if not hum then return end
    hum.UseJumpPower = true
    hum.WalkSpeed = DESIRED_SPEED
    hum.JumpPower  = DESIRED_JUMP
end

local function cacheCollideStates()
    table.clear(savedCollide)
    if not LocalPlayer.Character then return end
    for _,d in ipairs(LocalPlayer.Character:GetDescendants()) do
        if d:IsA("BasePart") then
            savedCollide[d] = d.CanCollide
        end
    end
end

local function setCharacterCollide(on)
    if not LocalPlayer.Character then return end
    for part,orig in pairs(savedCollide) do
        if part and part.Parent then
            part.CanCollide = on and orig or false
        end
    end
end

local function refreshHumanoidUI()
    if not hum then return end
    if HealthInput then HealthInput:Set(tostring(math.floor(hum.Health))) end
    if MaxHealthInput then MaxHealthInput:Set(tostring(math.floor(hum.MaxHealth))) end
    if HipHeightInput then HipHeightInput:Set(tostring(hum.HipHeight)) end
    if DisplayNameInput then DisplayNameInput:Set(tostring(hum.DisplayName or "")) end
    if BJD_Toggle and BJD_Toggle.Set then BJD_Toggle:Set(hum.BreakJointsOnDeath == true) end
end

local function attachHealthReset()
    if healthConn then healthConn:Disconnect(); healthConn = nil end
    if not hum then return end
    if not healthResetEnabled then return end
    healthConn = hum.HealthChanged:Connect(function()
        if not healthResetEnabled or isRestoringHealth then return end
        if hum and hum.MaxHealth then
            isRestoringHealth = true
            hum.Health = hum.MaxHealth
            isRestoringHealth = false
        end
    end)
end

-- Fly
local function flyStop()
    if not flying then return end
    flying = false
    flyEnabledDesired = false
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if hum then
        if savedAutoRotate ~= nil then hum.AutoRotate = savedAutoRotate end
        hum:Move(Vector3.zero, false)
    end
    if hrp then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    desiredPos = nil
    lastFaceDir = nil
    if noclipEnabled then setCharacterCollide(false) else setCharacterCollide(true) end
end

local function flyStart()
    if flying or not hum or not hrp then return end
    flying = true
    flyEnabledDesired = true
    savedAutoRotate = hum.AutoRotate
    hum.AutoRotate = false
    desiredPos = hrp.Position
    lastFaceDir = hrp.CFrame.LookVector
    setCharacterCollide(not noclipWhileFlying)

    flyConn = RunService.RenderStepped:Connect(function(dt)
        if not hrp or not hum then return end
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local move = hum.MoveDirection
        local planar = Vector3.new(move.X,0,move.Z)
        local planarMag = planar.Magnitude
        if planarMag > 1e-3 then planar = planar/planarMag else planar = Vector3.zero end
        local lookY = cam.CFrame.LookVector.Y
        local vert = 0
        if planarMag > 1e-3 then
            local a = math.abs(lookY)
            if a > PITCH_DEADZONE then
                local t = (a - PITCH_DEADZONE)/(1-PITCH_DEADZONE)
                vert = (lookY > 0 and 1 or -1) * t * FLY_VERT_SPEED
            end
        end
        local delta = Vector3.zero
        if planarMag > 1e-3 then delta += planar*(FLY_SPEED*dt) end
        if vert ~= 0 then delta += Vector3.new(0, vert*dt, 0) end
        desiredPos = (desiredPos or hrp.Position) + delta
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        if planarMag > 1e-3 then lastFaceDir = planar end
        local face = lastFaceDir or hrp.CFrame.LookVector
        local faceAt = desiredPos + Vector3.new(face.X,0,face.Z)
        hrp.CFrame = CFrame.new(desiredPos, Vector3.new(faceAt.X, desiredPos.Y, faceAt.Z))
        hum:Move(Vector3.zero, false)
    end)
end

local function bindCharacter(char)
    hum = char:WaitForChild("Humanoid")
    hrp = char:WaitForChild("HumanoidRootPart")
    applyStats()
    cacheCollideStates()

    if not baselineCaptured then
        baseline.Health = hum.Health
        baseline.MaxHealth = hum.MaxHealth
        baseline.HipHeight = hum.HipHeight
        baseline.DisplayName = hum.DisplayName
        baseline.BreakJointsOnDeath = hum.BreakJointsOnDeath
        baselineCaptured = true
    end

    refreshHumanoidUI()
    attachHealthReset()

    if flyEnabledDesired then
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        flying = false
        task.defer(function()
            if hum and hrp then
                savedAutoRotate = hum.AutoRotate
                hum.AutoRotate = false
                desiredPos = hrp.Position
                lastFaceDir = hrp.CFrame.LookVector
                setCharacterCollide(not noclipWhileFlying)
                flying = true
                flyConn = RunService.RenderStepped:Connect(function(dt)
                    local cam = Workspace.CurrentCamera
                    if not cam or not hum or not hrp then return end
                    local move = hum.MoveDirection
                    local planar = Vector3.new(move.X,0,move.Z)
                    local planarMag = planar.Magnitude
                    if planarMag > 1e-3 then planar = planar/planarMag else planar = Vector3.zero end
                    local lookY = cam.CFrame.LookVector.Y
                    local vert = 0
                    if planarMag > 1e-3 then
                        local a = math.abs(lookY)
                        if a > PITCH_DEADZONE then
                            local t = (a - PITCH_DEADZONE)/(1-PITCH_DEADZONE)
                            vert = (lookY>0 and 1 or -1)*t*FLY_VERT_SPEED
                        end
                    end
                    local delta = Vector3.zero
                    if planarMag > 1e-3 then delta += planar*(FLY_SPEED*dt) end
                    if vert ~= 0 then delta += Vector3.new(0, vert*dt, 0) end
                    desiredPos = (desiredPos or hrp.Position) + delta
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                    if planarMag > 1e-3 then lastFaceDir = planar end
                    local face = lastFaceDir or hrp.CFrame.LookVector
                    local faceAt = desiredPos + Vector3.new(face.X,0,face.Z)
                    hrp.CFrame = CFrame.new(desiredPos, Vector3.new(faceAt.X, desiredPos.Y, faceAt.Z))
                    hum:Move(Vector3.zero, false)
                end)
            end
        end)
    else
        if noclipEnabled then setCharacterCollide(false) end
    end

    if hitboxMode ~= "off" then
        task.defer(function()
            for _,plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    if hitboxMode == "outline" then
                        applyOutlineModeTo(plr.Character)
                    elseif hitboxMode == "hologram" then
                        applyHologramModeTo(plr.Character)
                    elseif hitboxMode == "invisible" then
                        applyInvisibleOnlyTo(plr.Character)
                    end
                end
            end
        end)
    end
end

if LocalPlayer.Character then bindCharacter(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(bindCharacter)

--==================================================
-- UI: Scripts tab (your baseline)
--==================================================
local HomeTab = Window:CreateTab("Scripts", 4483362458)

HomeTab:CreateSection("Speed")
local pendingSpeed = DESIRED_SPEED
local SpeedInput = HomeTab:CreateInput({
    Name = "Speed Value",
    PlaceholderText = tostring(DESIRED_SPEED),
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        local n = tonumber(text)
        if n then
            pendingSpeed = math.clamp(math.floor(n), 0, 300)
            DESIRED_SPEED = pendingSpeed
            applyStats()
        end
    end
})
HomeTab:CreateButton({
    Name = "Apply Speed",
    Callback = function()
        local n = tonumber(SpeedInput.CurrentValue or tostring(pendingSpeed))
        if n then
            pendingSpeed = math.clamp(math.floor(n), 0, 300)
            DESIRED_SPEED = pendingSpeed
            SpeedInput:Set(tostring(pendingSpeed))
            applyStats()
        end
    end
})

HomeTab:CreateSection("Jump")
local pendingJump = DESIRED_JUMP
local JumpInput = HomeTab:CreateInput({
    Name = "Jump Value",
    PlaceholderText = tostring(DESIRED_JUMP),
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        local n = tonumber(text)
        if n then
            pendingJump = math.clamp(math.floor(n), 0, 300)
            DESIRED_JUMP = pendingJump
            applyStats()
        end
    end
})
HomeTab:CreateButton({
    Name = "Apply Jump",
    Callback = function()
        local n = tonumber(JumpInput.CurrentValue or tostring(pendingJump))
        if n then
            pendingJump = math.clamp(math.floor(n), 0, 300)
            DESIRED_JUMP = pendingJump
            JumpInput:Set(tostring(pendingJump))
            applyStats()
        end
    end
})

HomeTab:CreateSection("Moves")
local edgeGui = Instance.new("ScreenGui")
edgeGui.Name = "EdgeButtons"
edgeGui.ResetOnSpawn = false
edgeGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
edgeGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local function makeEdgeBtn(name, row, label)
    local b = Instance.new("TextButton")
    b.Name = name
    b.AnchorPoint = Vector2.new(1,0)
    b.Position = UDim2.new(1, -6, 0, 6 + (row-1)*36)
    b.Size = UDim2.new(0, 120, 0, 30)
    b.Text = label
    b.TextSize = 12
    b.Font = Enum.Font.GothamBold
    b.BackgroundColor3 = Color3.fromRGB(30,30,35)
    b.TextColor3 = Color3.new(1,1,1)
    b.BorderSizePixel = 0
    b.Visible = false
    b.Parent = edgeGui
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,8)
    return b
end

local phaseEdgeBtn = makeEdgeBtn("Phase10Edge", 1, "Phase 10")
local tpEdgeBtn    = makeEdgeBtn("TpEdge",      2, "Teleport")

phaseEdgeBtn.MouseButton1Click:Connect(function()
    if not hrp then return end
    local dest = hrp.Position + hrp.CFrame.LookVector * PHASE_DIST
    hrp.CFrame = CFrame.new(dest, dest + hrp.CFrame.LookVector)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    if flying then desiredPos = dest end
end)

local HOLD_THRESHOLD = 0.5
local downAt = 0
local suppressClick = false

tpEdgeBtn.MouseButton1Down:Connect(function()
    downAt = os.clock()
    suppressClick = false
end)

tpEdgeBtn.MouseButton1Up:Connect(function()
    local held = os.clock() - (downAt or 0)
    if held >= HOLD_THRESHOLD then
        if hrp then
            markedCF = hrp.CFrame
            suppressClick = true
            local old = tpEdgeBtn.Text
            tpEdgeBtn.Text = "Marked!"
            task.delay(0.6, function()
                if tpEdgeBtn then tpEdgeBtn.Text = old end
            end)
        end
    end
end)

tpEdgeBtn.MouseButton1Click:Connect(function()
    if suppressClick then suppressClick = false return end
    if not hrp or not markedCF then
        Rayfield:Notify({ Title = "Teleport", Content = "No mark set", Duration = 2 })
        return
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    hrp.CFrame = markedCF
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    if flying then
        desiredPos = markedCF.Position
        local face = markedCF.LookVector
        local planar = Vector3.new(face.X,0,face.Z)
        if planar.Magnitude > 1e-3 then
            lastFaceDir = planar.Unit
        end
    end
end)

HomeTab:CreateToggle({
    Name = "Show Phase 10 button",
    CurrentValue = false,
    Callback = function(v) phaseEdgeBtn.Visible = v end
})
HomeTab:CreateToggle({
    Name = "Show Teleport button",
    CurrentValue = false,
    Callback = function(v) tpEdgeBtn.Visible = v end
})

HomeTab:CreateSection("Fly")
local function flyToggleUISet(state)
    if FlyToggle and FlyToggle.Set then FlyToggle:Set(state) end
end
local function noclipToggleUISet(state)
    if NoclipToggle and NoclipToggle.Set then NoclipToggle:Set(state) end
end

FlyToggle = HomeTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Callback = function(v) if v then flyStart() else flyStop() end end
})

local pendingFlySpeed = FLY_SPEED
local FlySpeedInput = HomeTab:CreateInput({
    Name = "Fly Speed",
    PlaceholderText = tostring(FLY_SPEED),
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        local n = tonumber(text)
        if n then
            pendingFlySpeed = math.clamp(math.floor(n), 0, 500)
            FLY_SPEED = pendingFlySpeed
            FLY_VERT_SPEED = pendingFlySpeed
        end
    end
})
HomeTab:CreateButton({
    Name = "Apply Fly Speed",
    Callback = function()
        local n = tonumber(FlySpeedInput.CurrentValue or tostring(pendingFlySpeed))
        if n then
            pendingFlySpeed = math.clamp(math.floor(n), 0, 500)
            FLY_SPEED = pendingFlySpeed
            FLY_VERT_SPEED = pendingFlySpeed
            FlySpeedInput:Set(tostring(pendingFlySpeed))
        end
    end
})

HomeTab:CreateSection("Collision")
NoclipToggle = HomeTab:CreateToggle({
    Name = "Noclip (walking)",
    CurrentValue = false,
    Callback = function(v)
        noclipEnabled = v
        cacheCollideStates()
        if flying then
            setCharacterCollide(not noclipWhileFlying)
        else
            setCharacterCollide(not v)
        end
    end
})
HomeTab:CreateToggle({
    Name = "Noclip (flying)",
    CurrentValue = false,
    Callback = function(v)
        noclipWhileFlying = v
        if flying then
            setCharacterCollide(not noclipWhileFlying)
        end
    end
})

HomeTab:CreateSection("Visuals")
local Toggle_InvisOnly, Toggle_ShowOutline, Toggle_Hologram

Toggle_InvisOnly = HomeTab:CreateToggle({
    Name = "Invisible hitboxes only",
    CurrentValue = false,
    Callback = function(v)
        if v then
            if Toggle_ShowOutline and Toggle_ShowOutline.Set then Toggle_ShowOutline:Set(false) end
            if Toggle_Hologram and Toggle_Hologram.Set then Toggle_Hologram:Set(false) end
            setHitboxMode("invisible")
        else
            if hitboxMode == "invisible" then setHitboxMode("off") end
        end
    end
})

Toggle_ShowOutline = HomeTab:CreateToggle({
    Name = "Show hitboxes",
    CurrentValue = false,
    Callback = function(v)
        if v then
            if Toggle_InvisOnly and Toggle_InvisOnly.Set then Toggle_InvisOnly:Set(false) end
            if Toggle_Hologram and Toggle_Hologram.Set then Toggle_Hologram:Set(false) end
            setHitboxMode("outline")
        else
            if hitboxMode == "outline" then setHitboxMode("off") end
        end
    end
})

Toggle_Hologram = HomeTab:CreateToggle({
    Name = "Hologram Hitboxes",
    CurrentValue = false,
    Callback = function(v)
        if v then
            if Toggle_InvisOnly and Toggle_InvisOnly.Set then Toggle_InvisOnly:Set(false) end
            if Toggle_ShowOutline and Toggle_ShowOutline.Set then Toggle_ShowOutline:Set(false) end
            setHitboxMode("hologram")
        else
            if hitboxMode == "hologram" then setHitboxMode("off") end
        end
    end
})

--==================================================
-- Enforcement (baseline)
--==================================================
RunService.Stepped:Connect(function()
    if noclipEnabled and not flying then
        for part,_ in pairs(savedCollide) do
            if part and part.Parent then
                part.CanCollide = false
            end
        end
    end
end)

local ENFORCE_INTERVAL = 0.20
local acc = 0
RunService.Heartbeat:Connect(function(dt)
    acc += dt
    if acc >= ENFORCE_INTERVAL then
        applyStats()
        if noclipEnabled and not flying then setCharacterCollide(false) end
        acc = 0
    end
end)

--==================================================
-- Humanoid tab (unchanged)
--==================================================
HumanoidTab = Window:CreateTab("Humanoid", 4483362458)

HumanoidTab:CreateSection("Properties")
HealthInput = HumanoidTab:CreateInput({
    Name = "Humanoid.Health",
    PlaceholderText = "0",
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        if not hum then return end
        local n = tonumber(text)
        if n then hum.Health = n end
    end
})
MaxHealthInput = HumanoidTab:CreateInput({
    Name = "Humanoid.MaxHealth",
    PlaceholderText = "0",
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        if not hum then return end
        local n = tonumber(text)
        if n then hum.MaxHealth = n end
    end
})
HipHeightInput = HumanoidTab:CreateInput({
    Name = "Humanoid.HipHeight",
    PlaceholderText = "0",
    NumbersOnly = true,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        if not hum then return end
        local n = tonumber(text)
        if n then hum.HipHeight = n end
    end
})
DisplayNameInput = HumanoidTab:CreateInput({
    Name = "Humanoid.DisplayName",
    PlaceholderText = "",
    NumbersOnly = false,
    RemoveTextAfterFocusLost = false,
    OnEnter = true,
    Callback = function(text)
        if not hum then return end
        hum.DisplayName = text or ""
    end
})

HumanoidTab:CreateSection("Toggles")
BJD_Toggle = HumanoidTab:CreateToggle({
    Name = "Humanoid.BreakJointsOnDeath",
    CurrentValue = false,
    Callback = function(v)
        if hum then hum.BreakJointsOnDeath = v end
    end
})
HReset_Toggle = HumanoidTab:CreateToggle({
    Name = "Humanoid.HealthChanged Reset",
    CurrentValue = false,
    Callback = function(v)
        healthResetEnabled = v
        attachHealthReset()
    end
})

HumanoidTab:CreateSection("Actions")
HumanoidTab:CreateButton({
    Name = "Apply",
    Callback = function()
        if not hum then return end
        local h  = tonumber(HealthInput.CurrentValue or "")
        local mh = tonumber(MaxHealthInput.CurrentValue or "")
        local hh = tonumber(HipHeightInput.CurrentValue or "")
        local dn = tostring(DisplayNameInput.CurrentValue or "")
        if mh then hum.MaxHealth = mh end
        if h  then hum.Health = h end
        if hh then hum.HipHeight = hh end
        if dn ~= nil then hum.DisplayName = dn end
        if BJD_Toggle and BJD_Toggle.CurrentValue ~= nil then
            hum.BreakJointsOnDeath = BJD_Toggle.CurrentValue
        end
        attachHealthReset()
    end
})
HumanoidTab:CreateButton({
    Name = "Reset",
    Callback = function()
        if not hum or not baselineCaptured then return end
        if baseline.MaxHealth ~= nil then hum.MaxHealth = baseline.MaxHealth end
        if baseline.Health    ~= nil then hum.Health    = baseline.Health    end
        if baseline.HipHeight ~= nil then hum.HipHeight = baseline.HipHeight end
        if baseline.DisplayName ~= nil then hum.DisplayName = baseline.DisplayName end
        if baseline.BreakJointsOnDeath ~= nil then hum.BreakJointsOnDeath = baseline.BreakJointsOnDeath end
        refreshHumanoidUI()
        attachHealthReset()
    end
})

--==================================================
-- Fix tab (unchanged)
--==================================================
local FixTab = Window:CreateTab("Fix", 4483362458)
FixTab:CreateSection("Emergency")

FixTab:CreateButton({
    Name = "Force Turn Off Fly",
    Callback = function()
        flyStop()
        flyEnabledDesired = false
        if FlyToggle and FlyToggle.Set then FlyToggle:Set(false) end
        if hum then hum:Move(Vector3.zero, false) end
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        if not noclipEnabled then setCharacterCollide(true) end
        Rayfield:Notify({ Title = "Fly Disabled", Content = "Fly forcibly stopped.", Duration = 3 })
    end
})

FixTab:CreateButton({
    Name = "Force Turn Off Noclip",
    Callback = function()
        noclipEnabled = false
        cacheCollideStates()
        setCharacterCollide(true)
        if NoclipToggle and NoclipToggle.Set then NoclipToggle:Set(false) end
        Rayfield:Notify({ Title = "Noclip Disabled", Content = "Collisions restored.", Duration = 3 })
    end
})

if LocalPlayer.Character then
    refreshHumanoidUI()
end

--==================================================
-- FINAL BASELINE: Auto-chop trees & damage characters (PARALLEL)
--==================================================

-- ---------- Tunables from your working baseline ----------
local TREE_NAME      = "Small Tree"
local SWING_DELAY    = 0.55     -- global wave throttle (unchanged)
local UID_SUFFIX     = "0000000000"

-- Axe order + defaults (as in your working baseline)
local AXE_ORDER = { "Old Axe","Good Axe","Strong Axe","Ice Axe","Chainsaw" }
local DEFAULTS = {
    ["Old Axe"]   = {WeaponDamage = 7,  WeaponResourceDamage = 4},
    ["Good Axe"]  = {WeaponDamage = 9,  WeaponResourceDamage = 5},
    ["Strong Axe"]= {WeaponDamage = 12, WeaponResourceDamage = 6},
    ["Ice Axe"]   = {WeaponDamage = 14, WeaponResourceDamage = 7},
    ["Chainsaw"]  = {WeaponDamage = 30, WeaponResourceDamage = 10},
}

-- Inventory (as before)
local Inventory = LocalPlayer:WaitForChild("Inventory")

local function readNumberAttr(inst, attr, fallback)
    local ok, v = pcall(function() return inst:GetAttribute(attr) end)
    if ok and typeof(v) == "number" then return v end
    return fallback
end

local function pickAxe()
    for _,name in ipairs(AXE_ORDER) do
        local tool = Inventory:FindFirstChild(name)
        if tool then
            local defs = DEFAULTS[name] or {WeaponDamage = 7, WeaponResourceDamage = 4}
            local dmg  = readNumberAttr(tool, "WeaponDamage", defs.WeaponDamage)
            local rDmg = readNumberAttr(tool, "WeaponResourceDamage", defs.WeaponResourceDamage)
            return tool, name, dmg, rDmg
        end
    end
    return nil
end

local function ensureEquipped(tool)
    if not tool then return false end
    -- "Real" equip as baseline (you may not see it in hand; server registers it)
    pcall(function()
        EquipItemHandle:FireServer("FireAllClients", tool)
    end)
    return true
end

-- Root find (robust): try Map/Foliage/Landmarks, else workspace
local Map      = Workspace:FindFirstChild("Map") or Workspace
local TreeRoot = Map:FindFirstChild("Foliage") or Map:FindFirstChild("Landmarks") or Map

-- Tree helpers from baseline
local function bestHitRegister(tree)
    local hr = tree:FindFirstChild("HitRegisters")
    if hr then
        local t = hr:FindFirstChild("Trunk")
        if t and t:IsA("BasePart") then return t end
        for _,c in ipairs(hr:GetChildren()) do
            if c:IsA("BasePart") then return c end
        end
    end
    return tree:FindFirstChild("Trunk")
end

local function countMyHits(inst)
    local hr = inst:FindFirstChild("HitRegisters")
    if not hr then return 0 end
    local cnt = 0
    local attrs = hr:GetAttributes()
    for key,_ in pairs(attrs) do
        local n, uid = string.match(key, "^(%d+)_([%d]+)$")
        if n and uid == UID_SUFFIX then
            cnt += 1
        end
    end
    return cnt
end

local function nextHitId(inst)
    local hr = inst:FindFirstChild("HitRegisters")
    local maxN = 0
    if hr then
        local attrs = hr:GetAttributes()
        for key,_ in pairs(attrs) do
            local n, uid = string.match(key, "^(%d+)_([%d]+)$")
            if n and uid == UID_SUFFIX then
                local num = tonumber(n) or 0
                if num > maxN then maxN = num end
            end
        end
    end
    return tostring(maxN + 1).."_"..UID_SUFFIX
end

-- Baseline impact CFrame: raycast inward from the trunk face
local SYN_OFFSET = 1.0
local SYN_DEPTH  = 4.0
local function computeImpactCFrame(model, hitPart)
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

-- Parallel wave dispatcher (unchanged logic, just concurrent)
local function waveHitTargets(targets, choosePart)
    if #targets == 0 then return end
    local tool = pickAxe()
    if not tool then return end
    ensureEquipped(tool)

    -- Optional: play a local wood chop for feedback (same as baseline)
    if RequestReplicateSound and LocalPlayer.Character then
        local head = LocalPlayer.Character:FindFirstChild("Head")
        if head then
            pcall(function()
                RequestReplicateSound:FireServer("FireAllClients","WoodChop",{Instance=head, Volume=0.45})
            end)
        end
    else
        pcall(function() PlayEnemyHitSound:FireServer("FireAllClients", targets[1], tool) end)
    end

    -- Fire **all** hits concurrently
    for _, inst in ipairs(targets) do
        task.spawn(function()
            local part = choosePart(inst)
            if not part then return end
            local impactCF = computeImpactCFrame(inst, part)
            local hitId    = nextHitId(inst)
            pcall(function()
                ToolDamageObject:InvokeServer(inst, tool, hitId, impactCF)
            end)
        end)
    end
end

--========================
-- 99 TAB (controls)
--========================
local NinetyNineTab = Window:CreateTab("99", 4483362458)
NinetyNineTab:CreateSection("Auto Damage Controls")

-- State toggles/sliders for trees/characters
local damageTrees        = false
local damageChars        = false
local TREE_RANGE         = 40
local CHAR_RANGE         = 40

local TreeToggle = NinetyNineTab:CreateToggle({
    Name = "Damage Trees",
    CurrentValue = false,
    Callback = function(v) damageTrees = v end
})

local TreeRangeSlider = NinetyNineTab:CreateSlider({
    Name = "Tree Range",
    Range = {10, 200},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = TREE_RANGE,
    Callback = function(val) TREE_RANGE = math.floor(val) end
})

local CharToggle = NinetyNineTab:CreateToggle({
    Name = "Damage Characters",
    CurrentValue = false,
    Callback = function(v) damageChars = v end
})

local CharRangeSlider = NinetyNineTab:CreateSlider({
    Name = "Character Range",
    Range = {10, 200},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = CHAR_RANGE,
    Callback = function(val) CHAR_RANGE = math.floor(val) end
})

--==================================================
-- Scanning (parallel-hit wave) — FINAL BASELINE
--==================================================
local function hrpPos()
    return (hrp and hrp.Position) or nil
end

local function treeIsValid(model)
    if not model or not model:IsA("Model") then return false end
    if model.Name ~= TREE_NAME then return false end
    local trunk = model:FindFirstChild("Trunk")
    if trunk and trunk:IsA("BasePart") then return true end
    local hr = model:FindFirstChild("HitRegisters")
    if hr then
        for _,c in ipairs(hr:GetChildren()) do
            if c:IsA("BasePart") then return true end
        end
    end
    return false
end

local function collectTreesInRange(origin, maxDist)
    local list = {}
    -- scan the declared tree root first (fast path)
    for _,desc in ipairs(TreeRoot:GetDescendants()) do
        if desc:IsA("Model") and desc.Name == TREE_NAME then
            local trunk = desc:FindFirstChild("Trunk")
            if trunk and trunk:IsA("BasePart") then
                if (trunk.Position - origin).Magnitude <= maxDist then
                    table.insert(list, desc)
                end
            else
                local hr = desc:FindFirstChild("HitRegisters")
                if hr then
                    for _,p in ipairs(hr:GetChildren()) do
                        if p:IsA("BasePart") then
                            if (p.Position - origin).Magnitude <= maxDist then
                                table.insert(list, desc)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    -- If that returned none, do a secondary fallback scan (rare)
    if #list == 0 then
        for _,desc in ipairs(Workspace:GetDescendants()) do
            if desc:IsA("Model") and desc.Name == TREE_NAME and treeIsValid(desc) then
                local trunk = desc:FindFirstChild("Trunk")
                local pos
                if trunk and trunk:IsA("BasePart") then
                    pos = trunk.Position
                else
                    local hr = desc:FindFirstChild("HitRegisters")
                    if hr then
                        local any = hr:FindFirstChildWhichIsA("BasePart")
                        if any then pos = any.Position end
                    end
                end
                if pos and (pos - origin).Magnitude <= maxDist then
                    table.insert(list, desc)
                end
            end
        end
    end
    return list
end

-- Characters usually under Workspace.Characters
local CharactersFolder = Workspace:FindFirstChild("Characters")

local function collectCharsInRange(origin, maxDist)
    local list = {}
    if CharactersFolder and CharactersFolder:IsA("Folder") then
        for _,m in ipairs(CharactersFolder:GetChildren()) do
            if m:IsA("Model") then
                local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                if root and root:IsA("BasePart") then
                    if (root.Position - origin).Magnitude <= maxDist then
                        table.insert(list, m)
                    end
                end
            end
        end
    else
        -- fallback: scan workspace for NPC models (avoid LocalPlayer.Character)
        for _,m in ipairs(Workspace:GetChildren()) do
            if m:IsA("Model") and m ~= LocalPlayer.Character then
                local root = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
                if root and root:IsA("BasePart") then
                    if (root.Position - origin).Magnitude <= maxDist then
                        table.insert(list, m)
                    end
                end
            end
        end
    end
    return list
end

-- Wave tick
task.spawn(function()
    while true do
        local origin = hrpPos()
        if origin then
            -- Trees
            if damageTrees then
                local trees = collectTreesInRange(origin, TREE_RANGE)
                if #trees > 0 then
                    waveHitTargets(trees, function(tree)
                        return bestHitRegister(tree)
                    end)
                end
            end

            -- Characters / animals
            if damageChars then
                local npcs = collectCharsInRange(origin, CHAR_RANGE)
                if #npcs > 0 then
                    waveHitTargets(npcs, function(npc)
                        return npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                    end)
                end
            end
        end

        -- single global wave delay (parallel preserved)
        task.wait(SWING_DELAY)
    end
end)
