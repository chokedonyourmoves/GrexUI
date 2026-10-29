-- ═══ FEATURE DETECTION ═════════════════════════════════════
local Features = {}
do
    local function HasFunction(name)
        local fn = _ENV[name] or (getgenv and getgenv()[name])
        return type(fn) == "function"
    end

    Features.Drawing = HasFunction("Drawing") or (type(Drawing) == "table" and type(Drawing.new) == "function")
    Features.Metatable = HasFunction("getrawmetatable")
    Features.Newcclosure = HasFunction("newcclosure")
    Features.Setreadonly = HasFunction("setreadonly")
    Features.Getnamecall = HasFunction("getnamecallmethod")
    Features.Setclipboard = HasFunction("setclipboard")
end

-- Hard requirement check for the silent-aim hook
local HookReady = Features.Metatable and Features.Newcclosure
    and Features.Setreadonly and Features.Getnamecall

local Rayfield
do
    local ok, result = pcall(function()
        return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    end)
    if not ok or not result then
        warn("[Grex] Rayfield Gen2 failed to load. Aborting.")
        return
    end
    Rayfield = result
end

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

-- ═══ STATE ═════════════════════════════════════════════════
local EspObjects = {}
local ChamsObjects = {}
local FriendsCache = {}
local VisibilityCache = {}    -- [player] = { visible, key, tick }
local RandomPartCache = {}    -- [player] = { part, expires }
local Connections = {}
local Handles = {}
local ClosestTarget = nil
local lastTriggerTime = 0
local frameCounter = 0
local rewritesThisSecond = 0
local rewriteSecond = 0
local internalRaycastDepth = 0

local VIS_CACHE_TTL = 0.25    -- seconds; hard expiry even if positions match

-- Desync state
local desyncGen = 0
local desyncThread = nil
local desyncSavedVelocity = nil
local desyncState = { anchored = false, physics = false }

local Camera = workspace.CurrentCamera

-- ═══ SETTINGS ══════════════════════════════════════════════
local Settings = {
    Enabled = false,
    AimEnabled = false, AimMode = "Silent", AimSmooth = 0,
    AimFOVSize = 120, AimFOVColor = Color3.fromRGB(255, 0, 0),
    ShowAimFOV = true, AimMaxDistance = 1000,
    TargetPriority = "Crosshair", TargetPart = "Head",
    Predict = true, PredictionAmount = 1, HitboxSize = 0,
    WallCheck = true, Tracking = true,
    Triggerbot = false, TriggerbotFOV = 15, TriggerbotCooldown = 0.08,
    IgnorePassive = false, IgnoreFriends = false,
    StealthMode = false, MaxRewritesPerSecond = 30, AimJitter = 0,
    ChamsEnabled = false,
    ChamsFillColor = Color3.fromRGB(255, 0, 0),
    ChamsOutlineColor = Color3.fromRGB(255, 255, 255),
    ShowBox = true, EspBoxColor = Color3.fromRGB(255, 255, 255),
    ShowLookTracers = false, LookTracerColor = Color3.fromRGB(255, 200, 0),
    ShowPlayerTracers = false, PlayerTracerColor = Color3.fromRGB(255, 255, 255),
    ShowHealth = true, ShowNames = true, ShowDistance = false,
    ShowFOV = true, FOVSize = 180, FOVColor = Color3.fromRGB(0, 255, 255),
    MaxDistance = 2000, TeamCheck = true, TextSize = 13,
    Fullbright = false,
    PerformanceMode = "Off",
    DesyncEnabled = false, DesyncMethod = "Anchor",
    DesyncFreezeDuration = 0.5, DesyncCycleInterval = 1.0,
}

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

-- ═══ DRAWING OBJECTS (guarded) ═════════════════════════════
local FOVCircle, AimFOVCircle
if Features.Drawing then
    local ok1, c1 = pcall(Drawing.new, "Circle")
    local ok2, c2 = pcall(Drawing.new, "Circle")
    if ok1 and c1 then
        c1.Thickness = 1; c1.Filled = false; c1.Transparency = 1; c1.NumSides = 64
        FOVCircle = c1
    end
    if ok2 and c2 then
        c2.Thickness = 1; c2.Filled = false; c2.Transparency = 1; c2.NumSides = 64
        AimFOVCircle = c2
    end
end

local function SafeDrawingNew(class)
    if not Features.Drawing then return nil end
    local ok, obj = pcall(Drawing.new, class)
    return ok and obj or nil
end

-- ═══ HELPERS ═══════════════════════════════════════════════
local function GetCharacter()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char.PrimaryPart
    if not (char and hum and root and hum.Health > 0) then return nil end
    return char, hum, root
end

local function RefreshFriendStatus(player)
    local ok, res = pcall(function() return LocalPlayer:IsFriendsWith(player.UserId) end)
    FriendsCache[player.UserId] = ok and res or false
end

local function IsFriend(player)
    return FriendsCache[player.UserId] == true
end

local function CacheKey(origin, targetPos)
    local function q(v) return math.floor(v * 2 + 0.5) end
    return string.format("%d|%d|%d|%d|%d|%d",
        q(origin.X), q(origin.Y), q(origin.Z),
        q(targetPos.X), q(targetPos.Y), q(targetPos.Z))
end

local function SelectTargetPart(char, player)
    if not char then return nil end
    if Settings.TargetPart ~= "Random" then
        return char:FindFirstChild(Settings.TargetPart)
    end
    if not player then return nil end
    local now = os.clock()
    local cached = RandomPartCache[player]
    if cached and cached.expires > now and cached.part and cached.part.Parent == char then
        return cached.part
    end
    local names = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" }
    local available = {}
    for _, name in ipairs(names) do
        local found = char:FindFirstChild(name)
        if found then table.insert(available, found) end
    end
    if #available == 0 then return nil end
    local part = available[math.random(1, #available)]
    RandomPartCache[player] = { part = part, expires = now + 1 }
    return part
end

-- ═══ ESP LIFECYCLE ═════════════════════════════════════════
local function CreateEsp(player)
    if EspObjects[player] or player == LocalPlayer then return end
    if not Features.Drawing then return end
    local esp = {
        Box = SafeDrawingNew("Square"), BoxFill = SafeDrawingNew("Square"),
        Tracer = SafeDrawingNew("Line"), LookTracer = SafeDrawingNew("Line"),
        HealthBar = SafeDrawingNew("Line"), Name = SafeDrawingNew("Text"),
        Distance = SafeDrawingNew("Text"),
    }
    for _, d in pairs(esp) do
        if not d then
            for _, dd in pairs(esp) do pcall(function() if dd then dd:Remove() end end) end
            return
        end
    end
    esp.Box.Thickness = 1; esp.Box.Filled = false
    esp.BoxFill.Filled = true; esp.BoxFill.Transparency = 0.5
    esp.Name.Center = true; esp.Name.Outline = true
    esp.Distance.Center = true; esp.Distance.Outline = true
    for _, d in pairs(esp) do d.Visible = false end
    EspObjects[player] = esp
end

local function RemoveEsp(player)
    local esp = EspObjects[player]
    if not esp then return end
    for _, d in pairs(esp) do pcall(function() d:Remove() end) end
    EspObjects[player] = nil
end

-- ═══ CHAMS ═════════════════════════════════════════════════
local function ApplyChams(char)
    if not char then return nil end
    local hl = char:FindFirstChild("GrexChams")
    if not hl then
        local ok, h = pcall(function()
            local inst = Instance.new("Highlight")
            inst.Name = "GrexChams"
            inst.Adornee = char
            inst.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            inst.Parent = char
            return inst
        end)
        if not ok then return nil end
        hl = h
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

-- ═══ FULLBRIGHT ════════════════════════════════════════════
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

-- ═══ FOV LAYOUT ════════════════════════════════════════════
-- Called every frame from UpdateAll, and also from toggles that change FOV state.
-- This guarantees the circles are never left visible after features disable.
local function UpdateFOVs()
    if not Camera then return end
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    if FOVCircle then
        FOVCircle.Position = center
        FOVCircle.Radius = Settings.FOVSize
        FOVCircle.Color = Settings.FOVColor
        FOVCircle.Visible = Settings.ShowFOV
    end
    if AimFOVCircle then
        AimFOVCircle.Position = center
        AimFOVCircle.Radius = Settings.AimFOVSize
        AimFOVCircle.Color = Settings.AimFOVColor
        AimFOVCircle.Visible = Settings.ShowAimFOV and Settings.AimEnabled
    end
end

-- ═══ WEAPON FIRE ═══════════════════════════════════════════
local function FireWeapon()
    if mouse1click then mouse1click()
    elseif VirtualUser and VirtualUser.ClickButton1 then
        pcall(function() VirtualUser:ClickButton1(Vector2.new()) end)
    elseif keypress then
        keypress(0x01, true); task.wait(0.02); keypress(0x01, false)
    end
end

-- ═══ PREDICTED AIM POINT ═══════════════════════════════════
local function GetAimPoint(player)
    local char = player.Character
    if not char then return nil end
    local part = SelectTargetPart(char, player)
    if not part then return nil end

    local pos = part.Position
    if Settings.Predict then
        local root = char.PrimaryPart
        if root then
            local ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
            pos = pos + root.AssemblyLinearVelocity * (ping * Settings.PredictionAmount)
        end
    end

    local s = Settings.HitboxSize
    if s > 0 then
        pos = pos + Vector3.new(
            math.random(-100, 100) / 100 * s,
            math.random(-50, 50) / 100 * s,
            math.random(-100, 100) / 100 * s
        )
    end

    if Settings.StealthMode and Settings.AimJitter > 0 then
        local j = Settings.AimJitter
        pos = pos + Vector3.new(
            math.random(-100, 100) / 100 * j,
            math.random(-100, 100) / 100 * j,
            math.random(-100, 100) / 100 * j
        )
    end
    return pos
end

-- ═══ CAMERA LOCK ═══════════════════════════════════════════
local function ApplyCameraLock()
    if not (Settings.AimEnabled and Settings.AimMode == "Camera" and ClosestTarget and Camera) then return end
    local targetPos = GetAimPoint(ClosestTarget)
    if not targetPos then return end
    local alpha = math.clamp(1 - Settings.AimSmooth, 0.01, 1)
    if Settings.StealthMode then alpha = alpha * alpha end
    local goal = CFrame.new(Camera.CFrame.Position, targetPos)
    Camera.CFrame = Camera.CFrame:Lerp(goal, alpha)
end

-- ═══ TARGET SCORING ════════════════════════════════════════
local function GetTargetScore(hum, root, dist3d, screenDist)
    local prio = Settings.TargetPriority
    if prio == "Distance" then
        return dist3d
    elseif prio == "LowestHealth" then
        return hum.Health
    elseif prio == "Threat" then
        local targetHead = root.Parent and root.Parent:FindFirstChild("Head")
        if not targetHead then return math.huge end
        local look = targetHead.CFrame.LookVector
        local lpChar = LocalPlayer.Character
        local lpRoot = lpChar and lpChar.PrimaryPart
        if not lpRoot then return math.huge end
        local toMe = (lpRoot.Position - targetHead.Position).Unit
        local facing = look:Dot(toMe)
        return (1 - facing) * 0.5 + dist3d / Settings.AimMaxDistance
    end
    return screenDist
end

-- ═══ VISIBILITY (position-keyed + time-expiring cache) ════
local function CheckVisible(player, origin, targetPos, filter)
    local key = CacheKey(origin, targetPos)
    local now = os.clock()
    local cached = VisibilityCache[player]
    if cached and cached.key == key and (now - cached.tick) < VIS_CACHE_TTL then
        return cached.visible
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = filter
    internalRaycastDepth = internalRaycastDepth + 1
    local ok, result = pcall(function() return workspace:Raycast(origin, targetPos - origin, params) end)
    internalRaycastDepth = internalRaycastDepth - 1
    local visible = ok and (result == nil)
    VisibilityCache[player] = { visible = visible, key = key, tick = now }
    return visible
end

-- ═══ DESYNC ════════════════════════════════════════════════
local function DesyncAnchor()
    local _, _, root = GetCharacter()
    if not root then return end
    desyncSavedVelocity = root.AssemblyLinearVelocity
    local ok1 = pcall(function() root.Anchored = true end)
    if not ok1 then
        warn("[Grex] DesyncAnchor: anchor failed")
        return
    end
    desyncState.anchored = true
    task.wait(Settings.DesyncFreezeDuration)
    local ok2 = pcall(function()
        root.Anchored = false
        if desyncSavedVelocity then
            root.AssemblyLinearVelocity = desyncSavedVelocity
        end
    end)
    if ok2 then desyncState.anchored = false end
end

local function DesyncVelocity()
    local _, _, root = GetCharacter()
    if not root then return end
    local dir = Camera and Camera.CFrame.LookVector or Vector3.new(0, 0, -1)
    pcall(function()
        root.AssemblyLinearVelocity = dir * 500 + Vector3.new(0, 50, 0)
    end)
    task.wait(0.05)
    pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
end

local function DesyncHumanoidState()
    local char, hum = GetCharacter()
    if not (char and hum) then return end
    local ok1 = pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    if ok1 then desyncState.physics = true end
    task.wait(Settings.DesyncFreezeDuration)
    local ok2 = pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    if ok2 then desyncState.physics = false end
end

local function DesyncOwnership()
    local _, _, root = GetCharacter()
    if not root then return end
    pcall(function() root:SetNetworkOwner(nil) end)
    task.wait(Settings.DesyncFreezeDuration)
end

local DesyncMethods = {
    Anchor = DesyncAnchor, Velocity = DesyncVelocity,
    HumanoidState = DesyncHumanoidState, Ownership = DesyncOwnership,
}

local function DesyncLoop(myGen)
    while Settings.DesyncEnabled and desyncGen == myGen do
        local char = GetCharacter()
        if char then
            local method = DesyncMethods[Settings.DesyncMethod]
            if method then pcall(method) end
        end
        task.wait(Settings.DesyncCycleInterval)
    end
end

local function RestoreCharacterState()
    local _, hum, root = GetCharacter()
    if hum and desyncState.physics then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        desyncState.physics = false
    end
    if root and desyncState.anchored then
        pcall(function() root.Anchored = false end)
        desyncState.anchored = false
    end
end

local function ToggleDesync(en)
    Settings.DesyncEnabled = en
    desyncGen = desyncGen + 1
    if en then
        local gen = desyncGen
        desyncThread = task.spawn(function() DesyncLoop(gen) end)
    else
        desyncThread = nil
        RestoreCharacterState()
    end
end

-- ═══ MAIN UPDATE LOOP ══════════════════════════════════════
local function UpdateAll()
    Camera = workspace.CurrentCamera
    if not Camera then return end

    -- FOV must be refreshed even when the main features are off, so the
    -- circle visibility tracks the toggle state immediately.
    if not (Settings.Enabled or Settings.AimEnabled or Settings.Triggerbot or Settings.ChamsEnabled) then
        UpdateFOVs()
        return
    end

    frameCounter = frameCounter + 1
    local renderThisFrame = true
    if Settings.PerformanceMode ~= "Off" and frameCounter % 2 ~= 0 then
        if Settings.PerformanceMode == "Half-Rate All" then
            UpdateFOVs()
            return
        end
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
                local isPassive = Settings.IgnorePassive
                    and hum.MoveDirection.Magnitude < 0.1
                    and root.AssemblyLinearVelocity.Magnitude < 2
                local isFriendBlocked = Settings.IgnoreFriends and IsFriend(player)
                local blocked = teamBlocked or isPassive or isFriendBlocked

                local needWall = (Settings.AimEnabled or Settings.Triggerbot)
                    and Settings.WallCheck and onScreen and not blocked
                local isVisible = true
                if needWall then
                    isVisible = CheckVisible(
                        player,
                        Camera.CFrame.Position,
                        headPos3d,
                        { LocalPlayer.Character, char }
                    )
                end

                local screenDist = (Vector2.new(headScreen.X, headScreen.Y) - center2d).Magnitude

                if Settings.AimEnabled and onScreen and not blocked
                    and screenDist <= Settings.AimFOVSize
                    and dist3d <= Settings.AimMaxDistance
                    and isVisible then
                    local score = GetTargetScore(hum, root, dist3d, screenDist)
                    if score < bestScore then
                        bestScore = score
                        ClosestTarget = player
                    end
                end

                if Settings.Triggerbot and onScreen and not blocked
                    and screenDist <= Settings.TriggerbotFOV
                    and dist3d <= Settings.AimMaxDistance
                    and isVisible then
                    if os.clock() - lastTriggerTime > Settings.TriggerbotCooldown then
                        FireWeapon()
                        lastTriggerTime = os.clock()
                    end
                end

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

local function SafeUpdate()
    local ok, err = pcall(UpdateAll)
    if not ok then warn("[Grex] UpdateAll error:", err) end
end

-- ═══ SILENT-AIM HOOK ═══════════════════════════════════════
if HookReady then
    local ok, mt = pcall(getrawmetatable, game)
    if ok and mt then
        setreadonly(mt, false)
        local oldRaycast = mt.__namecall
        mt.__namecall = newcclosure(function(self, ...)
            local args = { ... }
            local method = getnamecallmethod()

            if internalRaycastDepth > 0 then
                return oldRaycast(self, unpack(args))
            end

            if Settings.AimEnabled and Settings.AimMode == "Silent" and Settings.Tracking
                and ClosestTarget and method == "Raycast" and self == workspace then

                local now = os.clock()
                if now - rewriteSecond >= 1 then
                    rewriteSecond = now
                    rewritesThisSecond = 0
                end
                if rewritesThisSecond >= Settings.MaxRewritesPerSecond then
                    return oldRaycast(self, unpack(args))
                end

                local origin, direction = args[1], args[2]
                local mag = direction and direction.Magnitude or 0
                if type(origin) == "Vector3" and type(direction) == "Vector3"
                    and mag >= 10 and mag <= 5000 then
                    local targetPos = GetAimPoint(ClosestTarget)
                    if targetPos then
                        local desiredDir = (targetPos - origin).Unit
                        local finalDir = desiredDir
                        if Settings.AimSmooth > 0 then
                            local alpha = math.clamp(1 - Settings.AimSmooth, 0.01, 1)
                            if Settings.StealthMode then alpha = alpha * alpha end
                            finalDir = direction.Unit:Lerp(desiredDir, alpha).Unit
                        end
                        args[2] = finalDir * mag
                        rewritesThisSecond = rewritesThisSecond + 1
                    end
                end
            end

            return oldRaycast(self, unpack(args))
        end)
        setreadonly(mt, true)
    else
        warn("[Grex] getrawmetatable failed; silent aim disabled.")
    end
else
    warn("[Grex] Metatable primitives missing; silent aim disabled.")
end

-- ═══ TEARDOWN ══════════════════════════════════════════════
local destroyed = false
local function DestroyAll()
    if destroyed then return end
    destroyed = true

    Settings.DesyncEnabled = false
    desyncGen = desyncGen + 1
    desyncThread = nil
    RestoreCharacterState()

    for p in pairs(EspObjects) do RemoveEsp(p) end
    for _, hl in pairs(ChamsObjects) do
        pcall(function() if hl and hl.Parent then hl:Destroy() end end)
    end
    ChamsObjects = {}

    if Settings.Fullbright then
        pcall(SetFullbright, false)
        if Handles.Fullbright then pcall(function() Handles.Fullbright:Set(false, true) end) end
    end

    if FOVCircle then pcall(function() FOVCircle:Remove() end) end
    if AimFOVCircle then pcall(function() AimFOVCircle:Remove() end) end

    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() Rayfield:Destroy() end)
end

-- ═══ PLAYER POPULATION ═════════════════════════════════════
for _, p in ipairs(Players:GetPlayers()) do
    CreateEsp(p); SetupChams(p)
    if p ~= LocalPlayer then task.spawn(RefreshFriendStatus, p) end
end

table.insert(Connections, Players.PlayerAdded:Connect(function(p)
    CreateEsp(p); SetupChams(p); task.spawn(RefreshFriendStatus, p)
    table.insert(Connections, p.CharacterRemoving:Connect(function()
        local esp = EspObjects[p]
        if esp then for _, d in pairs(esp) do d.Visible = false end end
        VisibilityCache[p] = nil
        RandomPartCache[p] = nil
    end))
end))

table.insert(Connections, Players.PlayerRemoving:Connect(function(p)
    RemoveEsp(p)
    local hl = ChamsObjects[p]
    if hl and hl.Parent then pcall(function() hl:Destroy() end) end
    ChamsObjects[p] = nil
    FriendsCache[p.UserId] = nil
    VisibilityCache[p] = nil
    RandomPartCache[p] = nil
end))

for _, p in ipairs(Players:GetPlayers()) do
    table.insert(Connections, p.CharacterRemoving:Connect(function()
        local esp = EspObjects[p]
        if esp then for _, d in pairs(esp) do d.Visible = false end end
        VisibilityCache[p] = nil
        RandomPartCache[p] = nil
    end))
end

table.insert(Connections, LocalPlayer.CharacterAdded:Connect(function()
    VisibilityCache = {}
    RandomPartCache = {}
end))

table.insert(Connections, RunService.RenderStepped:Connect(SafeUpdate))

-- ═══ UI ════════════════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    name = "🦎 Grex UI",
    subtitle = "Velocity Compatible",
    sidebarLayout = true,
    configuration = {
        autoSave = true, autoLoad = true,
        fileName = "GrexConfig", customFolder = "GrexUI",
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
        aimToggle:Set(new, true)
    end,
})

Handles.AimMode = CombatTab:CreateDropdown({
    name = "Aim Mode", options = { "Silent", "Camera" },
    multiSelect = false, value = Settings.AimMode, flag = "Aim_Mode",
    callback = function(v) Settings.AimMode = v end,
})

Handles.AimSmooth = CombatTab:CreateSlider({
    name = "Aim Smoothness", range = { 0, 1 }, increment = 0.01,
    value = Settings.AimSmooth, flag = "Aim_Smooth",
    callback = function(v) Settings.AimSmooth = v end,
})

Handles.TargetPriority = CombatTab:CreateDropdown({
    name = "Target Priority",
    options = { "Crosshair", "Distance", "LowestHealth", "Threat" },
    multiSelect = false, value = Settings.TargetPriority, flag = "Aim_Priority",
    callback = function(v) Settings.TargetPriority = v end,
})

Handles.TargetPart = CombatTab:CreateDropdown({
    name = "Target Part",
    options = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "Random" },
    multiSelect = false, value = Settings.TargetPart, flag = "Aim_Part",
    callback = function(v) Settings.TargetPart = v end,
})

Handles.AimFOVSize = CombatTab:CreateSlider({
    name = "FOV Size", range = { 10, 600 }, increment = 5,
    value = Settings.AimFOVSize, flag = "Aim_FOV",
    callback = function(v) Settings.AimFOVSize = v end,
})

CombatTab:CreateToggle({
    name = "Show FOV", value = Settings.ShowAimFOV, flag = "Aim_ShowFOV",
    callback = function(v) Settings.ShowAimFOV = v; UpdateFOVs() end,
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

Handles.TriggerbotCooldown = CombatTab:CreateSlider({
    name = "Triggerbot Cooldown (s)", range = { 0.02, 0.5 }, increment = 0.01,
    value = Settings.TriggerbotCooldown, flag = "Trigger_Cooldown",
    callback = function(v) Settings.TriggerbotCooldown = v end,
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

Handles.Enabled = VisualsTab:CreateToggle({
    name = "Enable ESP Boxes", value = Settings.Enabled, flag = "ESP_Main",
    callback = function(v) Settings.Enabled = v end,
})
VisualsTab:CreateColorPicker({
    name = "ESP Box Color", value = Settings.EspBoxColor, flag = "ESP_BoxColor",
    callback = function(c) Settings.EspBoxColor = c end,
})
VisualsTab:CreateToggle({
    name = "Show FOV Circle", value = Settings.ShowFOV, flag = "ESP_ShowFOV",
    callback = function(v) Settings.ShowFOV = v; UpdateFOVs() end,
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

Handles.ChamsEnabled = VisualsTab:CreateToggle({
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

Handles.ShowLookTracers = VisualsTab:CreateToggle({
    name = "Look Tracers", value = Settings.ShowLookTracers, flag = "Tracer_Look",
    callback = function(v) Settings.ShowLookTracers = v end,
})
VisualsTab:CreateColorPicker({
    name = "Look Tracer Color", value = Settings.LookTracerColor, flag = "Tracer_LookColor",
    callback = function(c) Settings.LookTracerColor = c end,
})
Handles.ShowPlayerTracers = VisualsTab:CreateToggle({
    name = "Player Tracers", value = Settings.ShowPlayerTracers, flag = "Tracer_Player",
    callback = function(v) Settings.ShowPlayerTracers = v end,
})
VisualsTab:CreateColorPicker({
    name = "Player Tracer Color", value = Settings.PlayerTracerColor, flag = "Tracer_PlayerColor",
    callback = function(c) Settings.PlayerTracerColor = c end,
})

-- ══ DESYNC ═════════════════════════════════════════════════
local DesyncTab = Window:CreateTab({ name = "Desync", icon = "wifi-off" })

DesyncTab:CreateSection("Position Desync")
DesyncTab:CreateToggle({
    name = "Enable Desync", value = Settings.DesyncEnabled, flag = "DS_Main",
    callback = ToggleDesync,
})
DesyncTab:CreateDropdown({
    name = "Method",
    options = { "Anchor", "Velocity", "HumanoidState", "Ownership" },
    multiSelect = false, value = Settings.DesyncMethod, flag = "DS_Method",
    callback = function(v) Settings.DesyncMethod = v end,
})
DesyncTab:CreateSlider({
    name = "Freeze Duration (s)", range = { 0.05, 2 }, increment = 0.05,
    value = Settings.DesyncFreezeDuration, flag = "DS_FreezeDuration",
    callback = function(v) Settings.DesyncFreezeDuration = v end,
})
DesyncTab:CreateSlider({
    name = "Cycle Interval (s)", range = { 0.1, 5 }, increment = 0.1,
    value = Settings.DesyncCycleInterval, flag = "DS_CycleInterval",
    callback = function(v) Settings.DesyncCycleInterval = v end,
})

DesyncTab:CreateSection("Diagnostics")
DesyncTab:CreateButton({
    name = "Log Position (3s)",
    callback = function()
        local _, _, root = GetCharacter()
        if not root then return end
        local startPos = root.Position
        print(string.format("[Grex] Start: %.1f, %.1f, %.1f", startPos.X, startPos.Y, startPos.Z))
        task.wait(3)
        local _, _, root2 = GetCharacter()
        if not root2 then return end
        local endPos = root2.Position
        print(string.format("[Grex] End: %.1f, %.1f, %.1f (moved %.1f studs)",
            endPos.X, endPos.Y, endPos.Z, (endPos - startPos).Magnitude))
    end,
})

-- ══ WORLD ══════════════════════════════════════════════════
local WorldTab = Window:CreateTab({ name = "World", icon = "sun" })

Handles.Fullbright = WorldTab:CreateToggle({
    name = "Fullbright", value = Settings.Fullbright, flag = "World_Fullbright",
    callback = SetFullbright,
})
WorldTab:CreateButton({
    name = "Reset Lighting",
    callback = function()
        for k, v in pairs(originalLighting) do Lighting[k] = v end
        Settings.Fullbright = false
        if Handles.Fullbright then
            pcall(function() Handles.Fullbright:Set(false, true) end)
        end
    end,
})

-- ══ CONFIG ═════════════════════════════════════════════════
local ConfigTab = Window:CreateTab({ name = "Config", icon = "settings" })

ConfigTab:CreateSection("Profiles")
ConfigTab:CreateButton({
    name = "Apply: Legit",
    callback = function()
        for k, v in pairs(Profiles.Legit) do
            Settings[k] = v
            if Handles[k] then pcall(function() Handles[k]:Set(v, true) end) end
        end
        UpdateFOVs()
    end,
})
ConfigTab:CreateButton({
    name = "Apply: Semi",
    callback = function()
        for k, v in pairs(Profiles.Semi) do
            Settings[k] = v
            if Handles[k] then pcall(function() Handles[k]:Set(v, true) end) end
        end
        UpdateFOVs()
    end,
})
ConfigTab:CreateButton({
    name = "Apply: Rage",
    callback = function()
        for k, v in pairs(Profiles.Rage) do
            Settings[k] = v
            if Handles[k] then pcall(function() Handles[k]:Set(v, true) end) end
        end
        UpdateFOVs()
    end,
})

ConfigTab:CreateSection("Performance")
ConfigTab:CreateDropdown({
    name = "Performance Mode",
    options = { "Off", "Half-Rate ESP", "Half-Rate All" },
    multiSelect = false, value = Settings.PerformanceMode, flag = "Perf_Mode",
    callback = function(v) Settings.PerformanceMode = v end,
})

ConfigTab:CreateSection("Behavior Shaping")
ConfigTab:CreateLabel("Reduces obviousness. Does NOT evade detection.")

Handles.StealthMode = ConfigTab:CreateToggle({
    name = "Stealth Mode",
    description = "Ease-out aim + jitter. Cosmetic, not a bypass.",
    value = Settings.StealthMode, flag = "Stealth_Main",
    callback = function(v) Settings.StealthMode = v end,
})
Handles.AimJitter = ConfigTab:CreateSlider({
    name = "Aim Jitter", range = { 0, 0.1 }, increment = 0.001,
    value = Settings.AimJitter, flag = "Stealth_Jitter",
    callback = function(v) Settings.AimJitter = v end,
})
Handles.MaxRewritesPerSecond = ConfigTab:CreateSlider({
    name = "Max Raycast Rewrites / sec", range = { 5, 120 }, increment = 1,
    value = Settings.MaxRewritesPerSecond, flag = "Stealth_Rewrites",
    callback = function(v) Settings.MaxRewritesPerSecond = v end,
})

ConfigTab:CreateButton({ name = "Unload Script", callback = DestroyAll })
