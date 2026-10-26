local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local Camera = workspace.CurrentCamera

-- State
local LocalPlayer = Players.LocalPlayer
local EspObjects = {}
local ChamsObjects = {}
local FriendsCache = {}
local Connections = {}
local ClosestTarget = nil
local lastTriggerTime = 0
local lastFriendRefresh = 0
local frameCounter = 0
local rewritesThisSecond = 0
local rewriteSecond = 0

-- Element handles (for profiles)
local Handles = {}

local Settings = {
    -- Combat
    AimEnabled = false,
    AimMode = "Silent",          -- "Silent" | "Camera"
    AimSmooth = 0,
    AimFOVSize = 120,
    AimFOVColor = Color3.fromRGB(255, 0, 0),
    ShowAimFOV = true,
    AimMaxDistance = 1000,
    TargetPriority = "Crosshair", -- Crosshair | Distance | LowestHealth | Threat
    TargetPart = "Head",
    Predict = true,
    PredictionAmount = 1,
    HitboxSize = 0,
    WallCheck = true,
    Tracking = true,
    Triggerbot = false,
    TriggerbotFOV = 15,
    TriggerbotCooldown = 0.08,
    IgnorePassive = false,
    IgnoreFriends = false,
    -- Detection resistance
    StealthMode = false,
    MaxRewritesPerSecond = 30,
    AimJitter = 0,

    -- Visuals
    ChamsEnabled = false,
    ChamsFillColor = Color3.fromRGB(255, 0, 0),
    ChamsOutlineColor = Color3.fromRGB(255, 255, 255),
    ShowBox = true,
    EspBoxColor = Color3.fromRGB(255, 255, 255),
    ShowLookTracers = false,
    LookTracerColor = Color3.fromRGB(255, 200, 0),
    ShowPlayerTracers = false,
    PlayerTracerColor = Color3.fromRGB(255, 255, 255),
    ShowHealth = true,
    ShowNames = true,
    ShowDistance = false,
    ShowFOV = true,
    FOVSize = 180,
    FOVColor = Color3.fromRGB(0, 255, 255),
    MaxDistance = 2000,
    TeamCheck = true,
    TextSize = 13,

    -- World
    Fullbright = false,

    -- Performance
    PerformanceMode = false,   -- process ESP every other frame
}

-- ═══ PROFILES ═══════════════════════════════════════════════
local Profiles = {
    Legit = {
        AimEnabled = true, AimMode = "Camera", AimSmooth = 0.75, AimFOVSize = 40,
        Triggerbot = false, ShowBox = false, ChamsEnabled = false,
        ShowPlayerTracers = false, ShowLookTracers = false, StealthMode = true,
        AimJitter = 0.02, MaxRewritesPerSecond = 10,
    },
    Semi = {
        AimEnabled = true, AimMode = "Silent", AimSmooth = 0.35, AimFOVSize = 90,
        Triggerbot = true, TriggerbotCooldown = 0.12, ShowBox = true, ChamsEnabled = true,
        ShowPlayerTracers = false, ShowLookTracers = false, StealthMode = true,
        AimJitter = 0.01, MaxRewritesPerSecond = 20,
    },
    Rage = {
        AimEnabled = true, AimMode = "Silent", AimSmooth = 0, AimFOVSize = 300,
        Triggerbot = true, TriggerbotCooldown = 0.05, ShowBox = true, ChamsEnabled = true,
        ShowPlayerTracers = true, ShowLookTracers = true, StealthMode = false,
        AimJitter = 0, MaxRewritesPerSecond = 60,
    },
}

-- ─── FOV circles ─────────────────────────────────────────────
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1
FOVCircle.Filled = false
FOVCircle.Transparency = 1
FOVCircle.NumSides = 64

local AimFOVCircle = Drawing.new("Circle")
AimFOVCircle.Thickness = 1
AimFOVCircle.Filled = false
AimFOVCircle.Transparency = 1
AimFOVCircle.NumSides = 64

-- ─── Friends cache ──────────────────────────────────────────
local function RefreshFriendStatus(player)
    local ok, res = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
    FriendsCache[player.UserId] = ok and res or false
end
local function IsFriend(player)
    return FriendsCache[player.UserId] == true
end

-- ─── ESP lifecycle ──────────────────────────────────────────
local function CreateEsp(player)
    if EspObjects[player] or player == LocalPlayer then return end
    local esp = {
        Box = Drawing.new("Square"), BoxFill = Drawing.new("Square"),
        Tracer = Drawing.new("Line"), LookTracer = Drawing.new("Line"),
        HealthBar = Drawing.new("Line"), Name = Drawing.new("Text"),
        Distance = Drawing.new("Text"),
    }
    esp.Box.Thickness = 1
    esp.Box.Filled = false
    esp.BoxFill.Filled = true
    esp.BoxFill.Transparency = 0.5
    esp.Name.Center = true
    esp.Name.Outline = true
    esp.Distance.Center = true
    esp.Distance.Outline = true
    for _, d in pairs(esp) do d.Visible = false end
    EspObjects[player] = esp
end

local function RemoveEsp(player)
    local esp = EspObjects[player]
    if not esp then return end
    for _, d in pairs(esp) do pcall(function() d:Remove() end) end
    EspObjects[player] = nil
end

-- ─── Chams lifecycle ────────────────────────────────────────
local function ApplyChams(char)
    if not char then return nil end
    local hl = char:FindFirstChild("KewlChams")
    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "KewlChams"
        hl.Adornee = char
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = char
    end
    hl.FillColor = Settings.ChamsFillColor
    hl.OutlineColor = Settings.ChamsOutlineColor
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.Enabled = Settings.ChamsEnabled
    return hl
end

local function SetupChams(player)
    if player == LocalPlayer then return end
    local hl = ApplyChams(player.Character)
    if hl then ChamsObjects[player] = hl end
    table.insert(Connections, player.CharacterAdded:Connect(function(char)
        local h = ApplyChams(char)
        if h then ChamsObjects[player] = h end
    end))
end

-- ─── Fullbright ─────────────────────────────────────────────
local originalLighting = {
    Ambient = Lighting.Ambient, Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime, OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
}
local function SetFullbright(en)
    Settings.Fullbright = en
    if en then
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.ClockTime = 12
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
    else
        for k, v in pairs(originalLighting) do Lighting[k] = v end
    end
end

-- ─── FOV layout ─────────────────────────────────────────────
local function UpdateFOVs()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    FOVCircle.Position = center
    FOVCircle.Radius = Settings.FOVSize
    FOVCircle.Color = Settings.FOVColor
    FOVCircle.Visible = Settings.ShowFOV and (Settings.Enabled or Settings.ChamsEnabled)

    AimFOVCircle.Position = center
    AimFOVCircle.Radius = Settings.AimFOVSize
    AimFOVCircle.Color = Settings.AimFOVColor
    AimFOVCircle.Visible = Settings.ShowAimFOV and Settings.AimEnabled
end

-- ─── Weapon fire ────────────────────────────────────────────
local function FireWeapon()
    if mouse1click then mouse1click()
    elseif VirtualUser and VirtualUser.ClickButton1 then
        pcall(function() VirtualUser:ClickButton1(Vector2.new()) end)
    elseif keypress then
        keypress(0x01, true); task.wait(0.02); keypress(0x01, false)
    end
end

-- ─── Camera lock ────────────────────────────────────────────
local function ApplyCameraLock()
    if not (Settings.AimEnabled and Settings.AimMode == "Camera" and ClosestTarget) then return end
    local char = ClosestTarget.Character
    if not char then return end
    local part = char:FindFirstChild(Settings.TargetPart == "Random" and "Head" or Settings.TargetPart)
    if not part then return end

    local targetPos = part.Position
    if Settings.Predict then
        local root = char.PrimaryPart
        if root then
            local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
            targetPos = targetPos + root.AssemblyLinearVelocity * (ping * Settings.PredictionAmount)
        end
    end

    local alpha = math.clamp(1 - Settings.AimSmooth, 0.01, 1)
    if Settings.StealthMode then
        -- ease-out: fast initial correction, slow settle (less robotic than linear lerp)
        alpha = alpha * alpha
    end
    local goal = CFrame.new(Camera.CFrame.Position, targetPos)
    Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- ─── Target selection ───────────────────────────────────────
local function IsBetterTarget(player, char, hum, root, dist3d, screenDist, bestScore, bestPlayer)
    if not bestPlayer then return true end
    local prio = Settings.TargetPriority
    if prio == "Distance" then
        return dist3d < bestScore
    elseif prio == "LowestHealth" then
        return hum.Health < bestScore
    elseif prio == "Threat" then
        -- crude threat: closer + aiming roughly at us
        local look = Camera.CFrame.LookVector
        local toMe = (LocalPlayer.Character and LocalPlayer.Character.PrimaryPart
            and (LocalPlayer.Character.PrimaryPart.Position - root.Position).Unit) or Vector3.zero
        local threat = (1 - look:Dot(toMe)) * 0.5 + dist3d / Settings.AimMaxDistance
        return threat < bestScore
    end
    -- default: Crosshair
    return screenDist < bestScore
end

-- ─── Main loop ──────────────────────────────────────────────
local function UpdateAll()
    if not (Settings.Enabled or Settings.AimEnabled or Settings.Triggerbot or Settings.ChamsEnabled) then
        return
    end

    -- Performance: skip ESP rendering every other frame when enabled
    frameCounter = frameCounter + 1
    local renderThisFrame = true
    if Settings.PerformanceMode and frameCounter % 2 ~= 0 then
        renderThisFrame = false
    end

    local center2d = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local lpChar = LocalPlayer.Character
    local lpRoot = lpChar and lpChar.PrimaryPart
    local lpPos = lpRoot and lpRoot.Position

    ClosestTarget = nil
    local bestScore = math.huge

    for player, esp in pairs(EspObjects) do
        local chams = ChamsObjects[player]
        if chams and chams.Parent then
            chams.Enabled = Settings.ChamsEnabled
                and not (Settings.TeamCheck and player.Team == LocalPlayer.Team)
        end

        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char.PrimaryPart
        local head = char and char:FindFirstChild("Head")

        if not (char and hum and hum.Health > 0 and root and head and lpPos) then
            if renderThisFrame then
                for _, d in pairs(esp) do d.Visible = false end
            end
        else
            local dist3d = (lpPos - root.Position).Magnitude
            local maxCheck = math.max(Settings.MaxDistance, Settings.AimMaxDistance)

            if dist3d > maxCheck then
                if renderThisFrame then
                    for _, d in pairs(esp) do d.Visible = false end
                end
            else
                local headPos3d = head.Position
                local headScreen, onScreen = Camera:WorldToViewportPoint(headPos3d)
                local teamBlocked = Settings.TeamCheck and player.Team == LocalPlayer.Team

                local isPassive = Settings.IgnorePassive and
                    (hum.MoveDirection.Magnitude < 0.1 and root.AssemblyLinearVelocity.Magnitude < 2)
                local isFriendBlocked = Settings.IgnoreFriends and IsFriend(player)
                local blocked = teamBlocked or isPassive or isFriendBlocked

                local isVisible = true
                if (Settings.AimEnabled or Settings.Triggerbot) and Settings.WallCheck and onScreen and not blocked then
                    local origin = Camera.CFrame.Position
                    local params = RaycastParams.new()
                    params.FilterType = Enum.RaycastFilterType.Blacklist
                    params.FilterDescendantsInstances = { LocalPlayer.Character, char }
                    local ok, result = pcall(function() return workspace:Raycast(origin, headPos3d - origin, params) end)
                    isVisible = ok and (result == nil)
                end

                local screenDist = (Vector2.new(headScreen.X, headScreen.Y) - center2d).Magnitude

                -- Aim target selection
                if Settings.AimEnabled and onScreen and not blocked
                    and screenDist <= Settings.AimFOVSize
                    and dist3d <= Settings.AimMaxDistance
                    and isVisible then
                    if IsBetterTarget(player, char, hum, root, dist3d, screenDist, bestScore, ClosestTarget) then
                        bestScore = (Settings.TargetPriority == "Distance" and dist3d)
                            or (Settings.TargetPriority == "LowestHealth" and hum.Health)
                            or screenDist
                        ClosestTarget = player
                    end
                end

                -- Triggerbot
                if Settings.Triggerbot and onScreen and not blocked
                    and screenDist <= Settings.TriggerbotFOV
                    and dist3d <= Settings.AimMaxDistance
                    and isVisible then
                    if os.clock() - lastTriggerTime > Settings.TriggerbotCooldown then
                        FireWeapon()
                        lastTriggerTime = os.clock()
                    end
                end

                -- ESP rendering
                if not renderThisFrame then continue end

                if not onScreen or teamBlocked then
                    for _, d in pairs(esp) do d.Visible = false end
                else
                    local scale = math.clamp(2500 / dist3d, 1, 50)
                    local boxW, boxH = scale * 0.9, scale * 1.5
                    local boxPos = Vector2.new(headScreen.X - boxW / 2, headScreen.Y - boxH / 2)
                    local hpPct = hum.Health / hum.MaxHealth
                    local hpCol = Color3.new(1 - hpPct, hpPct, 0)

                    if Settings.Enabled and Settings.ShowBox then
                        esp.Box.Size = Vector2.new(boxW, boxH)
                        esp.Box.Position = boxPos
                        esp.Box.Color = Settings.EspBoxColor
                        esp.Box.Visible = true
                        esp.BoxFill.Size = Vector2.new(boxW, boxH)
                        esp.BoxFill.Position = boxPos
                        esp.BoxFill.Color = Settings.EspBoxColor
                        esp.BoxFill.Visible = true
                    else
                        esp.Box.Visible = false; esp.BoxFill.Visible = false
                    end

                    if Settings.Enabled and Settings.ShowNames then
                        esp.Name.Text = player.Name
                        esp.Name.Size = Settings.TextSize
                        esp.Name.Position = Vector2.new(headScreen.X, boxPos.Y - 16)
                        esp.Name.Color = Color3.new(1, 1, 1)
                        esp.Name.Visible = true
                    else esp.Name.Visible = false end

                    if Settings.Enabled and Settings.ShowDistance then
                        esp.Distance.Text = math.floor(dist3d) .. "m"
                        esp.Distance.Size = Settings.TextSize
                        esp.Distance.Position = Vector2.new(headScreen.X, boxPos.Y + boxH + 4)
                        esp.Distance.Color = Color3.new(1, 1, 1)
                        esp.Distance.Visible = true
                    else esp.Distance.Visible = false end

                    if Settings.Enabled and Settings.ShowHealth then
                        esp.HealthBar.From = Vector2.new(boxPos.X - 5, boxPos.Y)
                        esp.HealthBar.To = Vector2.new(boxPos.X - 5, boxPos.Y + boxH)
                        esp.HealthBar.Color = hpCol
                        esp.HealthBar.Thickness = 2
                        esp.HealthBar.Visible = true
                    else esp.HealthBar.Visible = false end

                    if Settings.Enabled and Settings.ShowPlayerTracers then
                        esp.Tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                        esp.Tracer.To = Vector2.new(headScreen.X, headScreen.Y)
                        esp.Tracer.Color = Settings.PlayerTracerColor
                        esp.Tracer.Thickness = 1
                        esp.Tracer.Visible = true
                    else esp.Tracer.Visible = false end

                    if Settings.Enabled and Settings.ShowLookTracers then
                        esp.LookTracer.From = center2d
                        esp.LookTracer.To = Vector2.new(headScreen.X, headScreen.Y)
                        esp.LookTracer.Color = Settings.LookTracerColor
                        esp.LookTracer.Thickness = 1
                        esp.LookTracer.Visible = true
                    else esp.LookTracer.Visible = false end
                end
            end
        end
    end

    UpdateFOVs()
    ApplyCameraLock()
end

-- Safe wrapper so one bad character cannot kill the loop
local function SafeUpdate()
    local ok, err = pcall(UpdateAll)
    if not ok then warn("[Kewl] UpdateAll error:", err) end
end

-- ─── Predicted aim point ────────────────────────────────────
local function GetPredictedPos(targetPlayer)
    local char = targetPlayer.Character
    if not char then return nil end
    local part
    if Settings.TargetPart == "Random" then
        local candidates = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" }
        local available = {}
        for _, name in ipairs(candidates) do
            local found = char:FindFirstChild(name)
            if found then table.insert(available, found) end
        end
        if #available == 0 then return nil end
        part = available[math.random(1, #available)]
    else
        part = char:FindFirstChild(Settings.TargetPart)
    end
    if not part then return nil end

    local targetPos = part.Position
    if Settings.Predict then
        local root = char.PrimaryPart
        if root then
            local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
            targetPos = targetPos + root.AssemblyLinearVelocity * (ping * Settings.PredictionAmount)
        end
    end

    -- per-shot hitbox randomisation (already present, keeps offsets small)
    local s = Settings.HitboxSize
    targetPos = targetPos + Vector3.new(
        math.random(-100, 100) / 100 * s,
        math.random(-50, 50) / 100 * s,
        math.random(-100, 100) / 100 * s
    )

    -- stealth jitter: tiny angular noise so every shot is not pixel-identical
    if Settings.StealthMode and Settings.AimJitter > 0 then
        targetPos = targetPos + Vector3.new(
            math.random(-100, 100) / 100 * Settings.AimJitter,
            math.random(-100, 100) / 100 * Settings.AimJitter,
            math.random(-100, 100) / 100 * Settings.AimJitter
        )
    end
    return targetPos
end

-- ─── Silent-aim raycast hook (rate-limited) ─────────────────
local mt = getrawmetatable(game)
local oldRaycast = mt.__namecall
setreadonly(mt, false)

mt.__namecall = newcclosure(function(self, ...)
    local args = { ... }
    local method = getnamecallmethod()

    if Settings.AimEnabled and Settings.AimMode == "Silent" and Settings.Tracking
        and ClosestTarget and method == "Raycast" and self == workspace then

        -- rate limit: no more than N rewrites per second
        local now = os.clock()
        if now - rewriteSecond >= 1 then
            rewriteSecond = now
            rewritesThisSecond = 0
        end
        if rewritesThisSecond >= Settings.MaxRewritesPerSecond then
            return oldRaycast(self, unpack(args))
        end

        local origin, direction = args[1], args[2]
        local targetPos = GetPredictedPos(ClosestTarget)
        if targetPos then
            local desiredDir = (targetPos - origin).Unit
            local finalDir = desiredDir
            if Settings.AimSmooth > 0 then
                local alpha = math.clamp(1 - Settings.AimSmooth, 0.01, 1)
                -- stealth: ease-out instead of linear lerp
                if Settings.StealthMode then alpha = alpha * alpha end
                finalDir = direction.Unit:Lerp(desiredDir, alpha).Unit
            end
            args[2] = finalDir * direction.Magnitude
            rewritesThisSecond = rewritesThisSecond + 1
        end
    end

    return oldRaycast(self, unpack(args))
end)
setreadonly(mt, true)

-- ─── Teardown ───────────────────────────────────────────────
local function DestroyAll()
    pcall(function() setreadonly(mt, false); mt.__namecall = oldRaycast; setreadonly(mt, true) end)
    for p in pairs(EspObjects) do RemoveEsp(p) end
    for p, hl in pairs(ChamsObjects) do pcall(function() if hl and hl.Parent then hl:Destroy() end end) end
    if Settings.Fullbright then SetFullbright(false) end
    pcall(function() FOVCircle:Remove(); AimFOVCircle:Remove() end)
    pcall(function() Rayfield:Destroy() end)
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
end

-- ─── Player population ──────────────────────────────────────
for _, p in ipairs(Players:GetPlayers()) do
    CreateEsp(p); SetupChams(p)
    if p ~= LocalPlayer then task.spawn(RefreshFriendStatus, p) end
end

table.insert(Connections, Players.PlayerAdded:Connect(function(p)
    CreateEsp(p); SetupChams(p); task.spawn(RefreshFriendStatus, p)
end))
table.insert(Connections, Players.PlayerRemoving:Connect(function(p)
    RemoveEsp(p)
    local hl = ChamsObjects[p]
    if hl and hl.Parent then pcall(function() hl:Destroy() end) end
    ChamsObjects[p] = nil
    FriendsCache[p.UserId] = nil
end))
-- Character removal: hide ESP immediately so boxes don't freeze on death
table.insert(Connections, Players.PlayerRemoving:Connect(function() end))
for _, p in ipairs(Players:GetPlayers()) do
    table.insert(Connections, p.CharacterRemoving:Connect(function()
        local esp = EspObjects[p]
        if esp then for _, d in pairs(esp) do d.Visible = false end end
    end))
end
table.insert(Connections, Players.PlayerAdded:Connect(function(p)
    table.insert(Connections, p.CharacterRemoving:Connect(function()
        local esp = EspObjects[p]
        if esp then for _, d in pairs(esp) do d.Visible = false end end
    end))
end))

table.insert(Connections, RunService.RenderStepped:Connect(SafeUpdate))

-- ═══ UI (Rayfield Gen2) ═════════════════════════════════════
local Window = Rayfield:CreateWindow({
    name = "🦎 Kewl GUI",
    subtitle = "Rayfield Gen2 · Complete",
    sidebarLayout = true,
    configuration = {
        autoSave = true, autoLoad = true,
        fileName = "KewlConfig", customFolder = "KewlGUI",
    },
})

-- ══ COMBAT ═════════════════════════════════════════════════
local CombatTab = Window:CreateTab({ name = "Combat", icon = "crosshair" })

CombatTab:CreateSection("Aim")

local aimToggle = CombatTab:CreateToggle({
    name = "Enable Aimlock", value = Settings.AimEnabled, flag = "Aim_Main",
    callback = function(v) Settings.AimEnabled = v end,
})
Handles.AimEnabled = aimToggle

CombatTab:CreateKeybind({
    name = "Aimlock Keybind", flag = "Aim_Key",
    callback = function()
        local new = not Settings.AimEnabled
        Settings.AimEnabled = new
        aimToggle:Set(new, true) -- silent UI sync
    end,
})

CombatTab:CreateDropdown({
    name = "Aim Mode", options = { "Silent", "Camera" },
    multiSelect = false, value = Settings.AimMode, flag = "Aim_Mode",
    callback = function(v) Settings.AimMode = v end,
})

CombatTab:CreateSlider({
    name = "Aim Smoothness", range = { 0, 1 }, increment = 0.01,
    value = Settings.AimSmooth, flag = "Aim_Smooth",
    callback = function(v) Settings.AimSmooth = v end,
})

CombatTab:CreateDropdown({
    name = "Target Priority",
    options = { "Crosshair", "Distance", "LowestHealth", "Threat" },
    multiSelect = false, value = Settings.TargetPriority, flag = "Aim_Priority",
    callback = function(v) Settings.TargetPriority = v end,
})

CombatTab:CreateDropdown({
    name = "Target Part",
    options = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Random" },
    multiSelect = false, value = Settings.TargetPart, flag = "Aim_Part",
    callback = function(v) Settings.TargetPart = v end,
})

CombatTab:CreateSlider({
    name = "FOV Size", range = { 10, 600 }, increment = 5,
    value = Settings.AimFOVSize, flag = "Aim_FOV",
    callback = function(v) Settings.AimFOVSize = v end,
})

CombatTab:CreateToggle({
    name = "Show FOV", value = Settings.ShowAimFOV, flag = "Aim_ShowFOV",
    callback = function(v) Settings.ShowAimFOV = v end,
})

CombatTab:CreateColorPicker({
    name = "FOV Circle Color", value = Settings.AimFOVColor, flag = "Aim_FOVColor",
    callback = function(c) Settings.AimFOVColor = c end,
})

CombatTab:CreateSection("Trigger")

local triggerToggle = CombatTab:CreateToggle({
    name = "Triggerbot", value = Settings.Triggerbot, flag = "Trigger_Main",
    callback = function(v) Settings.Triggerbot = v end,
})
Handles.Triggerbot = triggerToggle

CombatTab:CreateKeybind({
    name = "Triggerbot Keybind", flag = "Trigger_Key",
    callback = function()
        local new = not Settings.Triggerbot
        Settings.Triggerbot = new
        triggerToggle:Set(new, true)
    end,
})

CombatTab:CreateSlider({
    name = "Triggerbot FOV (px)", range = { 1, 60 }, increment = 1,
    value = Settings.TriggerbotFOV, flag = "Trigger_FOV",
    callback = function(v) Settings.TriggerbotFOV = v end,
})

CombatTab:CreateSection("Filters")

CombatTab:CreateToggle({
    name = "Wall Check", value = Settings.WallCheck, flag = "Filter_Wall",
    callback = function(v) Settings.WallCheck = v end,
})
CombatTab:CreateToggle({
    name = "Ignore Passive", value = Settings.IgnorePassive, flag = "Filter_Passive",
    callback = function(v) Settings.IgnorePassive = v end,
})
CombatTab:CreateToggle({
    name = "Ignore Friends", value = Settings.IgnoreFriends, flag = "Filter_Friends",
    callback = function(v) Settings.IgnoreFriends = v end,
})
CombatTab:CreateToggle({
    name = "Prediction", value = Settings.Predict, flag = "Filter_Predict",
    callback = function(v) Settings.Predict = v end,
})
CombatTab:CreateSlider({
    name = "Prediction Amount", range = { 0, 5 }, increment = 0.1,
    value = Settings.PredictionAmount, flag = "Filter_PredAmt",
    callback = function(v) Settings.PredictionAmount = v end,
})
CombatTab:CreateSlider({
    name = "Hitbox Size", range = { 0, 5 }, increment = 0.1,
    value = Settings.HitboxSize, flag = "Filter_Hitbox",
    callback = function(v) Settings.HitboxSize = v end,
})

-- ══ VISUALS ════════════════════════════════════════════════
local VisualsTab = Window:CreateTab({ name = "Visuals", icon = "eye" })

VisualsTab:CreateSection("ESP")

VisualsTab:CreateToggle({
    name = "Enable ESP Boxes", value = Settings.Enabled, flag = "ESP_Main",
    callback = function(v) Settings.Enabled = v end,
})
VisualsTab:CreateColorPicker({
    name = "ESP Box Color", value = Settings.EspBoxColor, flag = "ESP_BoxColor",
    callback = function(c) Settings.EspBoxColor = c end,
})
VisualsTab:CreateToggle({
    name = "Healthbar", value = Settings.ShowHealth, flag = "ESP_Health",
    callback = function(v) Settings.ShowHealth = v end,
})
VisualsTab:CreateToggle({
    name = "Player Nicknames", value = Settings.ShowNames, flag = "ESP_Names",
    callback = function(v) Settings.ShowNames = v end,
})
VisualsTab:CreateToggle({
    name = "Distance", value = Settings.ShowDistance, flag = "ESP_Dist",
    callback = function(v) Settings.ShowDistance = v end,
})
VisualsTab:CreateToggle({
    name = "Team Check", value = Settings.TeamCheck, flag = "ESP_Team",
    callback = function(v) Settings.TeamCheck = v end,
})
VisualsTab:CreateSlider({
    name = "Max Distance", range = { 100, 5000 }, increment = 50,
    value = Settings.MaxDistance, flag = "ESP_MaxDist",
    callback = function(v) Settings.MaxDistance = v end,
})
VisualsTab:CreateSlider({
    name = "Text Size", range = { 8, 24 }, increment = 1,
    value = Settings.TextSize, flag = "ESP_TextSize",
    callback = function(v) Settings.TextSize = v end,
})

VisualsTab:CreateSection("Chams")

VisualsTab:CreateToggle({
    name = "Enable Chams", value = Settings.ChamsEnabled, flag = "Chams_Main",
    callback = function(v)
        Settings.ChamsEnabled = v
        for _, hl in pairs(ChamsObjects) do
            if hl and hl.Parent then hl.Enabled = v end
        end
    end,
})
VisualsTab:CreateColorPicker({
    name = "Chams Fill Color", value = Settings.ChamsFillColor, flag = "Chams_Fill",
    callback = function(c)
        Settings.ChamsFillColor = c
        for _, hl in pairs(ChamsObjects) do
            if hl and hl.Parent then hl.FillColor = c end
        end
    end,
})
VisualsTab:CreateColorPicker({
    name = "Chams Outline Color", value = Settings.ChamsOutlineColor, flag = "Chams_Outline",
    callback = function(c)
        Settings.ChamsOutlineColor = c
        for _, hl in pairs(ChamsObjects) do
            if hl and hl.Parent then hl.OutlineColor = c end
        end
    end,
})

VisualsTab:CreateSection("Tracers")

VisualsTab:CreateToggle({
    name = "Look Tracers", value = Settings.ShowLookTracers, flag = "Tracer_Look",
    callback = function(v) Settings.ShowLookTracers = v end,
})
VisualsTab:CreateColorPicker({
    name = "Look Tracer Color", value = Settings.LookTracerColor, flag = "Tracer_LookColor",
    callback = function(c) Settings.LookTracerColor = c end,
})
VisualsTab:CreateToggle({
    name = "Player Tracers", value = Settings.ShowPlayerTracers, flag = "Tracer_Player",
    callback = function(v) Settings.ShowPlayerTracers = v end,
})
VisualsTab:CreateColorPicker({
    name = "Player Tracer Color", value = Settings.PlayerTracerColor, flag = "Tracer_PlayerColor",
    callback = function(c) Settings.PlayerTracerColor = c end,
})

-- ══ WORLD ══════════════════════════════════════════════════
local WorldTab = Window:CreateTab({ name = "World", icon = "sun" })

WorldTab:CreateToggle({
    name = "Fullbright", value = Settings.Fullbright, flag = "World_Fullbright",
    callback = SetFullbright,
})
WorldTab:CreateButton({
    name = "Reset Lighting",
    callback = function()
        for k, v in pairs(originalLighting) do Lighting[k] = v end
        Settings.Fullbright = false
    end,
})

-- ══ CONFIG / PERFORMANCE / STEALTH ═════════════════════════
local ConfigTab = Window:CreateTab({ name = "Config", icon = "settings" })

ConfigTab:CreateSection("Profiles")

ConfigTab:CreateButton({
    name = "Apply: Legit",
    callback = function()
        for k, v in pairs(Profiles.Legit) do
            Settings[k] = v
            if Handles[k] then Handles[k]:Set(v, true) end
        end
    end,
})
ConfigTab:CreateButton({
    name = "Apply: Semi",
    callback = function()
        for k, v in pairs(Profiles.Semi) do
            Settings[k] = v
            if Handles[k] then Handles[k]:Set(v, true) end
        end
    end,
})
ConfigTab:CreateButton({
    name = "Apply: Rage",
    callback = function()
        for k, v in pairs(Profiles.Rage) do
            Settings[k] = v
            if Handles[k] then Handles[k]:Set(v, true) end
        end
    end,
})

ConfigTab:CreateSection("Performance")

ConfigTab:CreateToggle({
    name = "Performance Mode (half-rate ESP)",
    value = Settings.PerformanceMode, flag = "Perf_Mode",
    callback = function(v) Settings.PerformanceMode = v end,
})

ConfigTab:CreateSection("Detection Resistance")

ConfigTab:CreateToggle({
    name = "Stealth Mode",
    description = "Ease-out aim, jitter, no Rage profile",
    value = Settings.StealthMode, flag = "Stealth_Main",
    callback = function(v) Settings.StealthMode = v end,
})
ConfigTab:CreateSlider({
    name = "Aim Jitter", range = { 0, 0.1 }, increment = 0.001,
    value = Settings.AimJitter, flag = "Stealth_Jitter",
    callback = function(v) Settings.AimJitter = v end,
})
ConfigTab:CreateSlider({
    name = "Max Raycast Rewrites / sec", range = { 5, 120 }, increment = 1,
    value = Settings.MaxRewritesPerSecond, flag = "Stealth_Rewrites",
    callback = function(v) Settings.MaxRewritesPerSecond = v end,
})

ConfigTab:CreateButton({
    name = "Unload Script",
    callback = DestroyAll,
})
