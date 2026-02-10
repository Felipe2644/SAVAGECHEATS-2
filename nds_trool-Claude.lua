--[[
    ╔═══════════════════════════════════════════════════════╗
    ║        NDS TROLL HUB v9.0 — OPTIMIZED EDITION        ║
    ║     Natural Disaster Survival | Mobile Compatible     ║
    ║              PARTE 1/3: CORE + ENGINE                 ║
    ╚═══════════════════════════════════════════════════════╝
]]

-- ═══ SERVICES ═══
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UIS           = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local Workspace     = game:GetService("Workspace")
local CoreGui       = game:GetService("CoreGui")
local LP            = Players.LocalPlayer
local Camera        = Workspace.CurrentCamera

-- ═══ CONFIG UNIFICADO ═══
local Config = {
    OrbitRadius = 15,   OrbitSpeed = 2,
    SpinRadius = 8,     SpinSpeed = 8,     SpinVertAmp = 0.5,
    CageRadius = 12,    CageSpeed = 1,
    MagnetOffset = Vector3.zero,
    PredictionFactor = 0.15,
    SuddenDeathDist = 10, SuddenDeathSpeedMul = 3, SuddenDeathRadiusMul = 0.5,
    NetworkTick = 0.5,
    MaxParts = 60,       CaptureRadius = 200,
    AlignMaxVel = 1000,  AlignResp = 200,
    PartDensity = 0.01,  SimRadius = 1e9,
    SpeedMultiplier = 3,
}

-- ═══ STATE ═══
local State = {
    SelectedPlayer = nil,
    ServerMagnet = false, HatFling = false, BodyFling = false,
    Launch = false, GodMode = false, Fly = false, View = false,
    Noclip = false, Speed = false, ESP = false, Telekinesis = false,
}

-- ═══ CONSTANTES ═══
local HUGE_AXIS     = Vector3.new(math.huge, math.huge, math.huge)
local LIGHT_PHYS    = PhysicalProperties.new(Config.PartDensity, 0, 0, 0, 0)
local DEFAULT_PHYS  = PhysicalProperties.new(0.7, 0.3, 0.5)
local ANCHOR_CF     = CFrame.new(0, 10000, 0)
local TWO_PI        = 2 * math.pi
local GOLDEN_ANGLE  = math.pi * (3 - math.sqrt(5))

-- ═══ ESTADO GLOBAL ═══
local CreatedObjects    = {}
local Connections       = {}
local AnchorPart, MainAttachment
local ActiveControls    = {}   -- [BasePart] → {attach, align}
local OriginalProps     = {}   -- [BasePart] → backup
local TelekTarget, TelekDist   -- Telekinesis (local, não global)

-- ═══ POOLS ═══
local AttachPool, AlignPool = {}, {}

-- ═══ MOTION ENGINE STATE ═══
local CurrentMode       = "None"
local TargetPlayer      = nil
local MotionAnchor      = nil
local MotionConnection  = nil
local _motionClock      = 0
local TargetAttachments = {}
local TargetAttachPool  = {}
local _partBuf, _ctrlBuf, _targBuf = {}, {}, {}
local _prevCount = 0

-- ╔═══════════════════════════════════════════════════════╗
-- ║                    HELPERS                            ║
-- ╚═══════════════════════════════════════════════════════╝

local function GetChar()     return LP.Character end
local function GetHRP()      local c = GetChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function GetHumanoid() local c = GetChar(); return c and c:FindFirstChildOfClass("Humanoid") end

local function Notify(title, text, dur)
    task.spawn(function()
        local sg = Instance.new("ScreenGui")
        sg.Name = "_NDSNotify"
        pcall(function() sg.Parent = CoreGui end)
        if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end

        local f = Instance.new("Frame")
        f.Size = UDim2.new(0, 220, 0, 48)
        f.Position = UDim2.new(0.5, -110, 0.82, 0)
        f.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        f.BorderSizePixel = 0
        f.BackgroundTransparency = 1
        f.Parent = sg
        Instance.new("UICorner").Parent = f
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(138, 43, 226)
        stroke.Thickness = 1
        stroke.Transparency = 1
        stroke.Parent = f

        local t1 = Instance.new("TextLabel")
        t1.Size = UDim2.new(1, -8, 0.5, 0)
        t1.Position = UDim2.new(0, 4, 0, 0)
        t1.BackgroundTransparency = 1
        t1.Text = title
        t1.TextColor3 = Color3.fromRGB(138, 43, 226)
        t1.Font = Enum.Font.GothamBold
        t1.TextScaled = true
        t1.TextTransparency = 1
        t1.Parent = f

        local t2 = t1:Clone()
        t2.Position = UDim2.new(0, 4, 0.5, 0)
        t2.Text = text
        t2.TextColor3 = Color3.fromRGB(255, 255, 255)
        t2.Font = Enum.Font.Gotham
        t2.Parent = f

        local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quad)
        TweenService:Create(f,  ti, {BackgroundTransparency = 0}):Play()
        TweenService:Create(stroke, ti, {Transparency = 0}):Play()
        TweenService:Create(t1, ti, {TextTransparency = 0}):Play()
        TweenService:Create(t2, ti, {TextTransparency = 0}):Play()
        task.wait(dur or 2)
        TweenService:Create(f,  ti, {BackgroundTransparency = 1}):Play()
        TweenService:Create(stroke, ti, {Transparency = 1}):Play()
        TweenService:Create(t1, ti, {TextTransparency = 1}):Play()
        TweenService:Create(t2, ti, {TextTransparency = 1}):Play()
        task.wait(0.3)
        sg:Destroy()
    end)
end

local function ClearConn(prefix)
    if not prefix then return end
    for key, conn in pairs(Connections) do
        if key == prefix or string.sub(key, 1, #prefix) == prefix then
            pcall(function() conn:Disconnect() end)
            Connections[key] = nil
        end
    end
end

-- Cache de peças com expiração (1s)
local _partsCache, _cacheTime = {}, 0

local function GetAvailableParts(force)
    local now = os.clock()
    if not force and now - _cacheTime < 1 then return _partsCache end
    local result, myChar = {}, GetChar()
    for _, p in Workspace:GetDescendants() do
        if p:IsA("BasePart") and not p.Anchored
            and not (myChar and p:IsDescendantOf(myChar))
            and not (p.Parent and p.Parent:FindFirstChildOfClass("Humanoid"))
            and not string.find(p.Name, "_NDS", 1, true) then
            result[#result + 1] = p
        end
    end
    _partsCache, _cacheTime = result, now
    return result
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║               OBJECT POOLING                          ║
-- ╚═══════════════════════════════════════════════════════╝

local function AcqAttach(parent)
    local a = table.remove(AttachPool)
    if a then a.Parent = parent; return a end
    a = Instance.new("Attachment")
    a.Name = "_NDSa"; a.Parent = parent
    return a
end

local function AcqAlign(parent, a0, a1)
    local al = table.remove(AlignPool)
    if al then
        al.Attachment0 = a0; al.Attachment1 = a1
        al.Enabled = true; al.Parent = parent
        return al
    end
    al = Instance.new("AlignPosition"); al.Name = "_NDSal"
    al.RigidityEnabled = false
    al.MaxVelocity = Config.AlignMaxVel
    al.Responsiveness = Config.AlignResp
    if not pcall(function()
        al.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        al.MaxAxesForce = HUGE_AXIS
    end) then pcall(function() al.MaxForce = math.huge end) end
    al.Attachment0 = a0; al.Attachment1 = a1; al.Parent = parent
    return al
end

local function RelAttach(a)
    if not a then return end
    a.Parent = nil; table.insert(AttachPool, a)
end

local function RelAlign(al)
    if not al then return end
    al.Enabled = false
    al.Attachment0 = nil; al.Attachment1 = nil
    al.Parent = nil; table.insert(AlignPool, al)
end

local function WarmPools(n)
    for _ = 1, (n or 30) do
        local a = Instance.new("Attachment"); a.Name = "_NDSa"
        table.insert(AttachPool, a)
        local al = Instance.new("AlignPosition"); al.Name = "_NDSal"
        al.RigidityEnabled = false
        al.MaxVelocity = Config.AlignMaxVel
        al.Responsiveness = Config.AlignResp
        if not pcall(function()
            al.ForceLimitMode = Enum.ForceLimitMode.PerAxis
            al.MaxAxesForce = HUGE_AXIS
        end) then pcall(function() al.MaxForce = math.huge end) end
        al.Enabled = false
        table.insert(AlignPool, al)
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              NETWORK CONTROL                          ║
-- ╚═══════════════════════════════════════════════════════╝

local _netConn, _netAcc = nil, 0

local function ForceSimRadius()
    local sr = Config.SimRadius
    if typeof(sethiddenproperty) == "function" then
        pcall(sethiddenproperty, LP, "SimulationRadius", sr)
        pcall(sethiddenproperty, LP, "MaximumSimulationRadius", sr)
    end
    if typeof(setsimulationradius) == "function" then
        pcall(setsimulationradius, sr, sr)
    end
end

local function SetupNetwork()
    if AnchorPart then pcall(game.Destroy, AnchorPart) end
    if _netConn then _netConn:Disconnect() end

    AnchorPart = Instance.new("Part")
    AnchorPart.Name = "_NDSAnchor"
    AnchorPart.Size = Vector3.one
    AnchorPart.Transparency = 1
    AnchorPart.CanCollide = false
    AnchorPart.CanQuery = false
    AnchorPart.CanTouch = false
    AnchorPart.Anchored = true
    AnchorPart.CFrame = ANCHOR_CF
    AnchorPart.Parent = Workspace
    table.insert(CreatedObjects, AnchorPart)

    MainAttachment = Instance.new("Attachment")
    MainAttachment.Name = "_NDSMain"
    MainAttachment.Parent = AnchorPart

    ForceSimRadius()
    _netAcc = 0
    _netConn = RunService.Heartbeat:Connect(function(dt)
        _netAcc += dt
        if _netAcc < Config.NetworkTick then return end
        _netAcc = 0; ForceSimRadius()
    end)
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              PART CONTROL                             ║
-- ╚═══════════════════════════════════════════════════════╝

local function IsLocalPart(p)
    local c = LP.Character
    return c ~= nil and p:IsDescendantOf(c)
end

local function StripMovers(p)
    for _, ch in p:GetChildren() do
        if string.sub(ch.Name, 1, 4) == "_NDS" then continue end
        if ch:IsA("AlignPosition") or ch:IsA("AlignOrientation")
            or ch:IsA("BodyPosition") or ch:IsA("BodyVelocity")
            or ch:IsA("BodyGyro") or ch:IsA("BodyForce") then
            pcall(ch.Destroy, ch)
        end
    end
end

function SetupPartControl(part, targetAttach)
    if not part or not part:IsA("BasePart") then return nil, nil end
    if part.Anchored or string.find(part.Name, "_NDS", 1, true) then return nil, nil end
    if IsLocalPart(part) then return nil, nil end

    local ex = ActiveControls[part]
    if ex then
        RelAlign(ex.align); RelAttach(ex.attach)
        ActiveControls[part] = nil
    end

    pcall(StripMovers, part)

    if not OriginalProps[part] then
        OriginalProps[part] = {
            CC = part.CanCollide, CQ = part.CanQuery,
            CT = part.CanTouch,   Ph = part.CustomPhysicalProperties,
        }
    end

    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false
    pcall(function() part.CustomPhysicalProperties = LIGHT_PHYS end)

    local att = AcqAttach(part)
    local ali = AcqAlign(part, att, targetAttach or MainAttachment)
    ActiveControls[part] = { attach = att, align = ali }
    return att, ali
end

function CleanPartControl(part)
    if not part then return end
    local c = ActiveControls[part]
    if c then
        RelAlign(c.align); RelAttach(c.attach)
        ActiveControls[part] = nil
    else
        pcall(function()
            local a = part:FindFirstChild("_NDSal"); if a then a:Destroy() end
            local b = part:FindFirstChild("_NDSa");  if b then b:Destroy() end
        end)
    end
    local o = OriginalProps[part]
    if o then
        pcall(function()
            part.CanCollide = o.CC
            part.CanQuery = o.CQ
            part.CanTouch = o.CT
            part.CustomPhysicalProperties = o.Ph or DEFAULT_PHYS
        end)
        OriginalProps[part] = nil
    else
        pcall(function() part.CanCollide = true end)
    end
end

-- ═══ CAPTURA DE PEÇAS (BUG FIX PRINCIPAL) ═══
local function CaptureParts(maxN, radius)
    maxN = maxN or Config.MaxParts
    radius = radius or Config.CaptureRadius
    local hrp = GetHRP()
    if not hrp then return 0 end

    local count = 0
    for _ in ActiveControls do count += 1 end
    if count >= maxN then return count end

    local parts = GetAvailableParts(true)
    local pos = hrp.Position

    -- Ordena por distância para pegar os mais próximos
    table.sort(parts, function(a, b)
        return (a.Position - pos).Magnitude < (b.Position - pos).Magnitude
    end)

    for _, p in parts do
        if count >= maxN then break end
        if not ActiveControls[p] and (p.Position - pos).Magnitude <= radius then
            SetupPartControl(p, nil)
            count += 1
        end
    end
    return count
end

local function ReleaseAllParts()
    for part in ActiveControls do CleanPartControl(part) end
end

local function FlushAll()
    ReleaseAllParts()
    for _, a in AttachPool do pcall(a.Destroy, a) end;  table.clear(AttachPool)
    for _, a in AlignPool do pcall(a.Destroy, a) end;   table.clear(AlignPool)
    if _netConn then _netConn:Disconnect(); _netConn = nil end
    table.clear(OriginalProps)
    table.clear(CreatedObjects)
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║             MOTION ENGINE                             ║
-- ╚═══════════════════════════════════════════════════════╝

-- Target Attachment Pool
local function AcqTargetAttach()
    local a = table.remove(TargetAttachPool)
    if a then a.Parent = MotionAnchor; return a end
    a = Instance.new("Attachment")
    a.Name = "_NDSt"; a.Parent = MotionAnchor
    return a
end

local function RelTargetAttach(a)
    if not a then return end
    a.Position = Vector3.zero; a.Parent = nil
    table.insert(TargetAttachPool, a)
end

-- Prediction
local function GetPredictedTarget(player)
    if not player then return nil end
    local c = player.Character
    if not c then return nil end
    local r = c:FindFirstChild("HumanoidRootPart")
    if not r then return nil end
    return r.Position + r.AssemblyLinearVelocity * Config.PredictionFactor
end

-- Sync Target Attachments
local function SyncTargetAttachments()
    for part, ctrl in ActiveControls do
        if not TargetAttachments[part] then
            local ta = AcqTargetAttach()
            TargetAttachments[part] = ta
            if ctrl.align then ctrl.align.Attachment1 = ta end
        end
    end
    for part, ta in TargetAttachments do
        if not ActiveControls[part] then
            RelTargetAttach(ta)
            TargetAttachments[part] = nil
        end
    end
end

local function ReleaseAllTargetAttachments()
    for part, ta in TargetAttachments do
        local ctrl = ActiveControls[part]
        if ctrl and ctrl.align then ctrl.align.Attachment1 = MainAttachment end
        RelTargetAttach(ta)
    end
    table.clear(TargetAttachments)
end

-- Collect active parts into buffers (zero alloc)
local function CollectActive()
    local n = 0
    for part, ctrl in ActiveControls do
        local ta = TargetAttachments[part]
        if ta and ctrl.align and ctrl.align.Enabled then
            n += 1
            _partBuf[n]  = part
            _ctrlBuf[n]  = ctrl
            _targBuf[n]  = ta
        end
    end
    for i = n + 1, _prevCount do
        _partBuf[i] = nil; _ctrlBuf[i] = nil; _targBuf[i] = nil
    end
    _prevCount = n
    return n
end

-- ═══ FORMATION CALCULATORS (Trig incremental) ═══

local function ComputeOrbit(count, t, speed, radius)
    local base = t * speed
    local step = TWO_PI / count
    local sSin, sCos = math.sin(step), math.cos(step)
    local cSin, cCos = math.sin(base), math.cos(base)
    for i = 1, count do
        _targBuf[i].Position = Vector3.new(cCos * radius, 0, cSin * radius)
        cCos, cSin = cCos * sCos - cSin * sSin, cSin * sCos + cCos * sSin
    end
end

local function ComputeSpin(count, t, speed, radius)
    local base = t * speed
    local step = TWO_PI / count
    local vAmp = radius * Config.SpinVertAmp
    local sSin, sCos = math.sin(step), math.cos(step)
    local cSin, cCos = math.sin(base), math.cos(base)
    local hStep = 1.0
    local hSSin, hSCos = math.sin(hStep), math.cos(hStep)
    local hSin, hCos = math.sin(t * speed * 0.5 + hStep), math.cos(t * speed * 0.5 + hStep)
    for i = 1, count do
        _targBuf[i].Position = Vector3.new(cCos * radius, hSin * vAmp, cSin * radius)
        cCos, cSin = cCos * sCos - cSin * sSin, cSin * sCos + cCos * sSin
        hCos, hSin = hCos * hSCos - hSin * hSSin, hSin * hSCos + hCos * hSSin
    end
end

local function ComputeCage(count, t, speed, radius)
    local off = t * speed
    local cMax = math.max(count - 1, 1)
    local cInv = 1 / cMax
    local gSin, gCos = math.sin(GOLDEN_ANGLE), math.cos(GOLDEN_ANGLE)
    local th0 = GOLDEN_ANGLE + off
    local tSin, tCos = math.sin(th0), math.cos(th0)
    for i = 1, count do
        local y = 1 - 2 * (i - 1) * cInv
        local r = math.sqrt(math.max(0, 1 - y * y))
        _targBuf[i].Position = Vector3.new(r * tCos * radius, y * radius, r * tSin * radius)
        tCos, tSin = tCos * gCos - tSin * gSin, tSin * gCos + tCos * gSin
    end
end

local function ComputeMagnet(count)
    local off = Config.MagnetOffset
    for i = 1, count do _targBuf[i].Position = off end
end

-- Dispatch table
local ModeCompute = {
    Orbit  = function(n, t, sm, rm) ComputeOrbit(n, t, Config.OrbitSpeed * sm, Config.OrbitRadius * rm) end,
    Spin   = function(n, t, sm, rm) ComputeSpin(n, t, Config.SpinSpeed * sm, Config.SpinRadius * rm) end,
    Cage   = function(n, t, sm, rm) ComputeCage(n, t, Config.CageSpeed * sm, Config.CageRadius * rm) end,
    Magnet = function(n, t, sm, rm) ComputeMagnet(n) end,
}

-- ═══ MOTION LOOP (único Heartbeat) ═══
local function MotionLoop(dt)
    if CurrentMode == "None" or not TargetPlayer then return end

    local targetPos = GetPredictedTarget(TargetPlayer)
    if not targetPos then return end

    SyncTargetAttachments()
    local count = CollectActive()
    if count == 0 then return end

    MotionAnchor.CFrame = CFrame.new(targetPos)
    _motionClock += dt

    -- Sudden Death
    local sm, rm = 1, 1
    local lRoot = GetHRP()
    if lRoot then
        local dx = targetPos.X - lRoot.Position.X
        local dy = targetPos.Y - lRoot.Position.Y
        local dz = targetPos.Z - lRoot.Position.Z
        if dx*dx + dy*dy + dz*dz < Config.SuddenDeathDist^2 then
            sm = Config.SuddenDeathSpeedMul
            rm = Config.SuddenDeathRadiusMul
        end
    end

    local compute = ModeCompute[CurrentMode]
    if compute then compute(count, _motionClock, sm, rm) end
end

-- ═══ MOTION INIT / SHUTDOWN ═══
local function InitMotionEngine()
    if MotionAnchor then pcall(game.Destroy, MotionAnchor) end
    if MotionConnection then MotionConnection:Disconnect() end

    MotionAnchor = Instance.new("Part")
    MotionAnchor.Name = "_NDSMotion"
    MotionAnchor.Size = Vector3.one
    MotionAnchor.Transparency = 1
    MotionAnchor.CanCollide = false
    MotionAnchor.CanQuery = false
    MotionAnchor.CanTouch = false
    MotionAnchor.Anchored = true
    MotionAnchor.CFrame = ANCHOR_CF
    MotionAnchor.Parent = Workspace
    table.insert(CreatedObjects, MotionAnchor)

    for _ = 1, 30 do
        local a = Instance.new("Attachment"); a.Name = "_NDSt"
        table.insert(TargetAttachPool, a)
    end

    MotionConnection = RunService.Heartbeat:Connect(MotionLoop)
end

local function ShutdownMotionEngine()
    if MotionConnection then MotionConnection:Disconnect(); MotionConnection = nil end
    ReleaseAllTargetAttachments()
    CurrentMode = "None"; TargetPlayer = nil; _motionClock = 0
    for _, a in TargetAttachPool do pcall(a.Destroy, a) end
    table.clear(TargetAttachPool)
    if MotionAnchor then pcall(game.Destroy, MotionAnchor); MotionAnchor = nil end
end

-- ═══ MODE CONTROL (Toggle central) ═══
local function SetMode(mode, target)
    -- Toggle OFF
    if CurrentMode == mode then
        ReleaseAllTargetAttachments()
        ReleaseAllParts()
        CurrentMode = "None"; TargetPlayer = nil; _motionClock = 0
        if MotionAnchor then MotionAnchor.CFrame = ANCHOR_CF end
        return
    end

    local resolved = target or TargetPlayer
    if not resolved then
        Notify("Erro", "Selecione um player primeiro!", 2)
        return
    end

    -- Ativar / Trocar
    CurrentMode = mode
    TargetPlayer = resolved
    _motionClock = 0

    -- ★ CAPTURA AUTOMÁTICA DE PEÇAS (fix do bug principal)
    local captured = CaptureParts()
    if captured == 0 then
        Notify("Aviso", "Nenhuma peça encontrada!", 2)
    else
        Notify(mode, captured .. " peças capturadas!", 1.5)
    end
end

-- Toggle functions que retornam (bool, string) para a UI
function ToggleOrbit(target)
    SetMode("Orbit", target)
    local on = CurrentMode == "Orbit"
    State.Orbit = on
    return on, on and "Orbit ATIVO" or "Orbit OFF"
end

function ToggleSpin(target)
    SetMode("Spin", target)
    local on = CurrentMode == "Spin"
    State.Spin = on
    return on, on and "Spin ATIVO" or "Spin OFF"
end

function ToggleCage(target)
    SetMode("Cage", target)
    local on = CurrentMode == "Cage"
    State.Cage = on
    return on, on and "Cage ATIVO" or "Cage OFF"
end

function ToggleMagnet(target)
    SetMode("Magnet", target)
    local on = CurrentMode == "Magnet"
    State.Magnet = on
    return on, on and "Magnet ATIVO" or "Magnet OFF"
end

function SetTarget(player)
    TargetPlayer = player
    State.SelectedPlayer = player
end

function IsMotionActive()
    return CurrentMode ~= "None"
end

-- ═══ DESATIVAR TUDO ═══
function DisableAllFunctions()
    SetMode("None", nil)
    State.ServerMagnet = false; ClearConn("ServerMagnet")
    State.HatFling = false;    ClearConn("HatFling")
    State.BodyFling = false;   ClearConn("BodyFling")
    State.Launch = false;      ClearConn("Launch")
    State.GodMode = false;     ClearConn("GodMode")
    State.View = false;        ClearConn("View")
    State.Noclip = false;      ClearConn("Noclip")
    State.Speed = false;       ClearConn("Speed")
    State.Telekinesis = false; ClearConn("Telek")
end

-- ═══ INIT CORE ═══
WarmPools(40)
SetupNetwork()
InitMotionEngine()

-- ╔═══════════════════════════════════════════════════════╗
-- ║     COMPETITION ENGINE — DOMINÂNCIA DE PEÇAS          ║
-- ║                                                       ║
-- ║  • Re-strip movers inimigos a cada 0.3s               ║
-- ║  • Re-captura peças roubadas automaticamente          ║
-- ║  • AlignPosition com força DOMINANTE                  ║
-- ║  • Network ownership agressivo por peça               ║
-- ╚═══════════════════════════════════════════════════════╝

-- Config de competição
Config.CompetitionTick      = 0.3    -- Intervalo de verificação (s)
Config.DominantMaxVel       = 2000   -- 2x o padrão (1000)
Config.DominantResp         = 500    -- 2.5x o padrão (200)
Config.RecaptureRadius      = 300    -- Raio para re-capturar peças perdidas
Config.AggressiveStrip      = true   -- Remove movers inimigos continuamente
Config.AutoRecapture        = true   -- Re-captura peças que perdeu controle

local _compConn     = nil  -- Conexão do competition loop
local _compAcc      = 0    -- Acumulador de tempo
local _trackedParts = {}   -- [BasePart] = true — peças que JÁ controlamos antes

-- ═══ FORÇA DOMINANTE ═══
-- Aplica valores mais altos que o padrão no AlignPosition
-- para "ganhar" a disputa de forças com outros scripts
local function ApplyDominantForce(align)
    if not align then return end
    align.MaxVelocity = Config.DominantMaxVel
    align.Responsiveness = Config.DominantResp

    -- Tenta aumentar a força máxima ao limite
    pcall(function()
        if align.ForceLimitMode == Enum.ForceLimitMode.PerAxis then
            align.MaxAxesForce = Vector3.new(math.huge, math.huge, math.huge)
        else
            align.MaxForce = math.huge
        end
    end)
end

-- ═══ STRIP AGRESSIVO ═══
-- Remove QUALQUER mover que não seja nosso
-- Mais completo que o StripMovers original
local function AggressiveStrip(part)
    for _, child in part:GetChildren() do
        -- Pula os nossos (prefixo _NDS)
        if string.sub(child.Name, 1, 4) == "_NDS" then continue end

        local isEnemy = child:IsA("AlignPosition")
            or child:IsA("AlignOrientation")
            or child:IsA("LinearVelocity")
            or child:IsA("AngularVelocity")
            or child:IsA("VectorForce")
            or child:IsA("Torque")
            or child:IsA("BodyPosition")
            or child:IsA("BodyVelocity")
            or child:IsA("BodyGyro")
            or child:IsA("BodyForce")
            or child:IsA("BodyThrust")
            or child:IsA("BodyAngularVelocity")
            or child:IsA("RocketPropulsion")

        if isEnemy then
            pcall(child.Destroy, child)
        end
    end
end

-- ═══ NETWORK OWNERSHIP POR PEÇA ═══
-- Tenta forçar ownership de cada peça individual
local function ClaimNetworkOwnership(part)
    -- Método 1: SetNetworkOwner (alguns executores)
    pcall(function()
        part:SetNetworkOwner(LP)
    end)

    -- Método 2: SetNetworkOwnership (alternativo)
    pcall(function()
        part:SetNetworkOwnership(true)
    end)
end

-- ═══ VERIFICAR SE PEÇA AINDA ESTÁ SOB CONTROLE ═══
local function IsPartStillControlled(part)
    if not part or not part.Parent then return false end
    local ctrl = ActiveControls[part]
    if not ctrl then return false end
    -- Verifica se o AlignPosition ainda existe e está ativo
    if not ctrl.align or not ctrl.align.Parent then return false end
    if not ctrl.align.Enabled then return false end
    -- Verifica se o Attachment ainda existe
    if not ctrl.attach or not ctrl.attach.Parent then return false end
    return true
end

-- ═══ COMPETITION LOOP ═══
local function CompetitionLoop(dt)
    _compAcc += dt
    if _compAcc < Config.CompetitionTick then return end
    _compAcc = 0

    local hrp = GetHRP()
    if not hrp then return end
    local myPos = hrp.Position

    -- FASE 1: Defender peças que temos
    for part, ctrl in ActiveControls do
        if not part or not part.Parent then
            -- Peça foi destruída — limpar referência
            ActiveControls[part] = nil
            continue
        end

        -- 1A: Strip contínuo de movers inimigos
        if Config.AggressiveStrip then
            pcall(AggressiveStrip, part)
        end

        -- 1B: Garantir que nosso AlignPosition está dominante
        if ctrl.align and ctrl.align.Parent and ctrl.align.Enabled then
            ApplyDominantForce(ctrl.align)
        end

        -- 1C: Se nosso controle foi corrompido, re-setup
        if not IsPartStillControlled(part) then
            -- Tenta re-capturar
            CleanPartControl(part)
            local att, ali = SetupPartControl(part, nil)
            if ali then
                ApplyDominantForce(ali)
                -- Reconectar ao target attachment se Motion Engine ativo
                local ta = TargetAttachments[part]
                if ta then ali.Attachment1 = ta end
            end
        end

        -- 1D: Forçar network ownership
        ClaimNetworkOwnership(part)

        -- 1E: Rastrear peça
        _trackedParts[part] = true
    end

    -- FASE 2: Re-capturar peças que perdemos
    if Config.AutoRecapture and (CurrentMode ~= "None" or State.ServerMagnet or State.Launch) then
        for part in _trackedParts do
            if part and part.Parent and not ActiveControls[part] then
                -- Peça que tínhamos mas perdemos
                local dist = (part.Position - myPos).Magnitude
                if dist <= Config.RecaptureRadius then
                    local att, ali = SetupPartControl(part, nil)
                    if ali then
                        ApplyDominantForce(ali)
                    end
                end
            elseif not part or not part.Parent then
                -- Peça destruída — remover do tracking
                _trackedParts[part] = nil
            end
        end
    end

    -- FASE 3: Roubar peças de outros scripts nas proximidades
    -- Procura por peças com movers que não são nossos
    if Config.AggressiveStrip then
        local partCount = 0
        for _ in ActiveControls do partCount += 1 end

        -- Só procura peças novas se não estiver no limite
        if partCount < Config.MaxParts then
            for _, desc in Workspace:GetDescendants() do
                if partCount >= Config.MaxParts then break end
                if not desc:IsA("BasePart") then continue end
                if desc.Anchored then continue end
                if ActiveControls[desc] then continue end
                if string.find(desc.Name, "_NDS", 1, true) then continue end
                if desc.Parent and desc.Parent:FindFirstChildOfClass("Humanoid") then continue end
                local isLocal = LP.Character and desc:IsDescendantOf(LP.Character)
                if isLocal then continue end

                -- Verifica se tem mover de outro script
                local hasEnemyMover = false
                for _, ch in desc:GetChildren() do
                    if string.sub(ch.Name, 1, 4) == "_NDS" then continue end
                    if ch:IsA("AlignPosition") or ch:IsA("BodyPosition")
                        or ch:IsA("BodyVelocity") or ch:IsA("LinearVelocity") then
                        hasEnemyMover = true
                        break
                    end
                end

                if hasEnemyMover then
                    local dist = (desc.Position - myPos).Magnitude
                    if dist <= Config.RecaptureRadius then
                        -- ROUBAR: strip + capturar
                        pcall(AggressiveStrip, desc)
                        local att, ali = SetupPartControl(desc, nil)
                        if ali then
                            ApplyDominantForce(ali)
                            partCount += 1
                        end
                    end
                end
            end
        end
    end
end

-- ═══ INICIAR/PARAR COMPETITION ENGINE ═══
local function StartCompetition()
    if _compConn then return end -- Já rodando
    _compAcc = 0
    _compConn = RunService.Heartbeat:Connect(CompetitionLoop)
end

local function StopCompetition()
    if _compConn then
        _compConn:Disconnect()
        _compConn = nil
    end
    _compAcc = 0
end

-- ═══ OVERRIDE DO SetMode PARA ATIVAR COMPETIÇÃO ═══
local _originalSetMode = SetMode

SetMode = function(mode, target)
    _originalSetMode(mode, target)

    -- Ativa competição quando tem modo ativo
    if CurrentMode ~= "None" then
        -- Aplica força dominante em todas as peças atuais
        for _, ctrl in ActiveControls do
            if ctrl.align then
                ApplyDominantForce(ctrl.align)
            end
        end
        StartCompetition()
    else
        -- Mantém competição se ServerMagnet ou Launch estiver ativo
        if not State.ServerMagnet and not State.Launch then
            StopCompetition()
            table.clear(_trackedParts)
        end
    end
end

-- ═══ OVERRIDE DO ToggleServerMagnet PARA COMPETIÇÃO ═══
local _originalServerMagnet = ToggleServerMagnet

ToggleServerMagnet = function()
    local result, msg = _originalServerMagnet()

    if State.ServerMagnet then
        for _, ctrl in ActiveControls do
            if ctrl.align then ApplyDominantForce(ctrl.align) end
        end
        StartCompetition()
    else
        if CurrentMode == "None" and not State.Launch then
            StopCompetition()
        end
    end

    return result, msg
end

-- ═══ OVERRIDE DO ToggleLaunch PARA COMPETIÇÃO ═══
local _originalLaunch = ToggleLaunch

ToggleLaunch = function()
    local result, msg = _originalLaunch()

    if State.Launch then
        for _, ctrl in ActiveControls do
            if ctrl.align then ApplyDominantForce(ctrl.align) end
        end
        StartCompetition()
    else
        if CurrentMode == "None" and not State.ServerMagnet then
            StopCompetition()
        end
    end

    return result, msg
end

-- ═══ OVERRIDE DO DisableAllFunctions PARA COMPETIÇÃO ═══
local _originalDisable = DisableAllFunctions

DisableAllFunctions = function()
    StopCompetition()
    table.clear(_trackedParts)
    _originalDisable()
end

print("[NDS v9.0] Competition Engine carregado — Dominância ativa")

print("[NDS v9.0] PARTE 1/3 carregada — Core + Engine")
-- ══════════════════════════════════════════════════════
-- CONTINUE COLANDO A PARTE 2 ABAIXO DESTE PONTO
-- ══════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════
-- PARTE 2/3: FUNÇÕES DE AÇÃO — Cole ABAIXO da Parte 1
-- ══════════════════════════════════════════════════════

-- ╔═══════════════════════════════════════════════════════╗
-- ║            SERVER MAGNET (REESCRITO)                   ║
-- ║  Âncoras individuais por inimigo | Sem CFrame hack    ║
-- ║  AlignPosition puro = estável + forte                 ║
-- ╚═══════════════════════════════════════════════════════╝

local EnemyAnchors = {}  -- [Player] → {part, attach}

local function GetOrCreateEnemyAnchor(player)
    if EnemyAnchors[player] then
        local ea = EnemyAnchors[player]
        if ea.part and ea.part.Parent then return ea end
        pcall(game.Destroy, ea.part)
        EnemyAnchors[player] = nil
    end
    local p = Instance.new("Part")
    p.Name = "_NDSEAnchor"
    p.Size = Vector3.one; p.Transparency = 1
    p.CanCollide = false; p.CanQuery = false
    p.CanTouch = false; p.Anchored = true
    p.CFrame = ANCHOR_CF; p.Parent = Workspace
    table.insert(CreatedObjects, p)

    local a = Instance.new("Attachment")
    a.Name = "_NDSea"; a.Parent = p

    EnemyAnchors[player] = { part = p, attach = a }
    return EnemyAnchors[player]
end

local function CleanEnemyAnchors()
    for _, ea in EnemyAnchors do
        if ea.part then pcall(game.Destroy, ea.part) end
    end
    table.clear(EnemyAnchors)
end

function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet

    if State.ServerMagnet then
        if CurrentMode ~= "None" then SetMode("None", nil) end

        local captured = CaptureParts(Config.MaxParts, Config.CaptureRadius)
        if captured == 0 then
            State.ServerMagnet = false
            return false, "Sem peças por perto!"
        end

        Connections.ServerMagnetLoop = RunService.Heartbeat:Connect(function()
            if not State.ServerMagnet then return end

            local enemies = {}
            local myHRP = GetHRP()
            if not myHRP then return end

            for _, plr in Players:GetPlayers() do
                if plr ~= LP and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        enemies[#enemies + 1] = plr
                    end
                end
            end

            if #enemies == 0 then return end

            for _, plr in enemies do
                local ea = GetOrCreateEnemyAnchor(plr)
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp and ea.part then
                    local predicted = hrp.Position + hrp.AssemblyLinearVelocity * 0.1
                    ea.part.CFrame = CFrame.new(predicted)
                end
            end

            local idx = 1
            for part, ctrl in ActiveControls do
                if ctrl.align and ctrl.align.Enabled then
                    local targetPlr = enemies[idx]
                    local ea = EnemyAnchors[targetPlr]
                    if ea and ea.attach then
                        if ctrl.align.Attachment1 ~= ea.attach then
                            ctrl.align.Attachment1 = ea.attach
                        end
                        ctrl.align.MaxVelocity = 1500
                        ctrl.align.Responsiveness = 400
                    end
                    idx += 1
                    if idx > #enemies then idx = 1 end
                end
            end
        end)

        return true, "Server Magnet: " .. captured .. " peças!"
    else
        ClearConn("ServerMagnet")
        for _, ctrl in ActiveControls do
            if ctrl.align then
                ctrl.align.Attachment1 = MainAttachment
                ctrl.align.MaxVelocity = Config.AlignMaxVel
                ctrl.align.Responsiveness = Config.AlignResp
            end
        end
        CleanEnemyAnchors()
        ReleaseAllParts()
        return false, "Server Magnet OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              HAT FLING                                ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleHatFling()
    State.HatFling = not State.HatFling

    if State.HatFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.HatFling = false
            return false, "Selecione um player!"
        end

        local angle = 0
        Connections.HatFlingLoop = RunService.Heartbeat:Connect(function(dt)
            if not State.HatFling then return end
            local tChar = State.SelectedPlayer and State.SelectedPlayer.Character
            if not tChar then return end
            local tHRP = tChar:FindFirstChild("HumanoidRootPart")
            local myHRP = GetHRP()
            if not tHRP or not myHRP then return end

            angle += dt * 30
            local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
            myHRP.CFrame = CFrame.new(tHRP.Position + offset)
            myHRP.AssemblyLinearVelocity = Vector3.new(9e5, 9e5, 9e5)
            myHRP.AssemblyAngularVelocity = Vector3.new(9e5, 9e5, 9e5)
        end)
        return true, "Hat Fling ATIVO!"
    else
        ClearConn("HatFling")
        local hrp = GetHRP()
        if hrp then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        return false, "Hat Fling OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              BODY FLING                               ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleBodyFling()
    State.BodyFling = not State.BodyFling

    if State.BodyFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.BodyFling = false
            return false, "Selecione um player!"
        end

        Connections.BodyFlingLoop = RunService.Heartbeat:Connect(function()
            if not State.BodyFling then return end
            local tChar = State.SelectedPlayer and State.SelectedPlayer.Character
            if not tChar then return end
            local tHRP = tChar:FindFirstChild("HumanoidRootPart")
            local myHRP = GetHRP()
            if not tHRP or not myHRP then return end

            myHRP.CFrame = tHRP.CFrame
            myHRP.AssemblyLinearVelocity = Vector3.new(9e7, 9e7, 9e7)
        end)
        return true, "Body Fling ATIVO!"
    else
        ClearConn("BodyFling")
        local hrp = GetHRP()
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
        return false, "Body Fling OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              LAUNCH (Bombardeio)                      ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleLaunch()
    State.Launch = not State.Launch

    if State.Launch then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Launch = false
            return false, "Selecione um player!"
        end

        if CurrentMode ~= "None" then SetMode("None", nil) end
        local captured = CaptureParts()

        Connections.LaunchLoop = RunService.Heartbeat:Connect(function()
            if not State.Launch then return end
            local tChar = State.SelectedPlayer and State.SelectedPlayer.Character
            if not tChar then return end
            local hrp = tChar:FindFirstChild("HumanoidRootPart")
            if hrp and AnchorPart then
                AnchorPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, -3, 0))
            end
        end)
        return true, "Launch: " .. captured .. " peças!"
    else
        ClearConn("Launch")
        AnchorPart.CFrame = ANCHOR_CF
        ReleaseAllParts()
        return false, "Launch OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║     SKYLIFT (Empurra com peças físicas)               ║
-- ║  Cria plataforma CanCollide sob o alvo e sobe         ║
-- ║  Physics-based = funciona contra outros players       ║
-- ╚═══════════════════════════════════════════════════════╝

local _skyLiftData = {}
local _skyLiftHeight = 0

function ToggleSkyLift()
    State.SkyLift = not State.SkyLift

    if State.SkyLift then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.SkyLift = false
            return false, "Selecione um player!"
        end

        _skyLiftHeight = 0
        table.clear(_skyLiftData)

        local offsets = {
            Vector3.new(-2, 0, -2), Vector3.new(2, 0, -2),
            Vector3.new(-2, 0, 0),  Vector3.new(2, 0, 0),
            Vector3.new(-2, 0, 2),  Vector3.new(2, 0, 2),
        }

        for i, offset in offsets do
            local part = Instance.new("Part")
            part.Name = "_NDSSkyLift"
            part.Size = Vector3.new(4, 1.5, 4)
            part.Transparency = 0.7
            part.Material = Enum.Material.Neon
            part.Color = Color3.fromRGB(138, 43, 226)
            part.Anchored = false
            part.CanCollide = true
            part.CanQuery = false
            part.CanTouch = true
            part.Massless = false
            part.CustomPhysicalProperties = PhysicalProperties.new(100, 1, 0, 1, 1)
            part.Parent = Workspace
            table.insert(CreatedObjects, part)

            local anchor = Instance.new("Part")
            anchor.Name = "_NDSSkyAnc"
            anchor.Size = Vector3.one
            anchor.Transparency = 1
            anchor.CanCollide = false
            anchor.CanQuery = false
            anchor.CanTouch = false
            anchor.Anchored = true
            anchor.CFrame = ANCHOR_CF
            anchor.Parent = Workspace
            table.insert(CreatedObjects, anchor)

            local att0 = Instance.new("Attachment"); att0.Parent = part
            local att1 = Instance.new("Attachment"); att1.Parent = anchor

            local align = Instance.new("AlignPosition")
            align.RigidityEnabled = true
            align.Attachment0 = att0
            align.Attachment1 = att1
            align.Parent = part

            _skyLiftData[i] = {
                part = part, anchor = anchor,
                att0 = att0, att1 = att1,
                align = align, offset = offset,
            }
        end

        Connections.SkyLiftLoop = RunService.Heartbeat:Connect(function(dt)
            if not State.SkyLift then return end
            local sel = State.SelectedPlayer
            if not sel or not sel.Character then return end
            local tHRP = sel.Character:FindFirstChild("HumanoidRootPart")
            if not tHRP then return end

            _skyLiftHeight += dt * 15

            local basePos = tHRP.Position
            for _, data in _skyLiftData do
                if type(data) == "table" and data.anchor and data.anchor.Parent then
                    data.anchor.CFrame = CFrame.new(
                        basePos + data.offset + Vector3.new(0, -2 + _skyLiftHeight, 0)
                    )
                end
            end
        end)

        Notify("SkyLift", "Elevando " .. State.SelectedPlayer.DisplayName, 2)
        return true, "SkyLift ATIVO!"
    else
        ClearConn("SkyLift")
        _skyLiftHeight = 0

        for _, data in _skyLiftData do
            if type(data) == "table" then
                pcall(function()
                    if data.align  then data.align:Destroy() end
                    if data.att0   then data.att0:Destroy() end
                    if data.att1   then data.att1:Destroy() end
                    if data.part   then data.part:Destroy() end
                    if data.anchor then data.anchor:Destroy() end
                end)
            end
        end
        table.clear(_skyLiftData)

        return false, "SkyLift OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              GOD MODE                                 ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleGodMode()
    State.GodMode = not State.GodMode

    if State.GodMode then
        local char = GetChar()
        local hum = GetHumanoid()
        if not char or not hum then
            State.GodMode = false
            return false, "Sem personagem!"
        end

        local ff = Instance.new("ForceField")
        ff.Name = "_NDSff"; ff.Visible = false; ff.Parent = char
        table.insert(CreatedObjects, ff)

        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)

        Connections.GodModeLoop = RunService.Heartbeat:Connect(function()
            if not State.GodMode then return end
            local h = GetHumanoid()
            if h then h.Health = h.MaxHealth end
            local c = GetChar()
            if c and not c:FindFirstChild("_NDSff") then
                local nff = Instance.new("ForceField")
                nff.Name = "_NDSff"; nff.Visible = false; nff.Parent = c
            end
        end)
        return true, "God Mode ATIVO!"
    else
        ClearConn("GodMode")
        local c = GetChar()
        if c then
            local ff = c:FindFirstChild("_NDSff")
            if ff then ff:Destroy() end
        end
        local h = GetHumanoid()
        if h then pcall(function() h:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end) end
        return false, "God Mode OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              VIEW PLAYER                              ║
-- ║  Persiste entre mortes | Cleanup automático           ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleView()
    State.View = not State.View

    if State.View then
        if not State.SelectedPlayer then
            State.View = false
            return false, "Selecione um player!"
        end

        local target = State.SelectedPlayer

        local function UpdateCam()
            if not State.View or not target or not target.Parent then return end
            local c = target.Character
            if c then
                local h = c:FindFirstChildOfClass("Humanoid")
                if h then Camera.CameraSubject = h end
            end
        end

        UpdateCam()

        Connections.ViewCharAdded = target.CharacterAdded:Connect(function()
            task.wait(0.2); UpdateCam()
        end)

        Connections.ViewRemoving = Players.PlayerRemoving:Connect(function(plr)
            if plr == target then
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConn("View")
                Notify("View", "Player saiu", 2)
            end
        end)

        Connections.ViewLoop = RunService.Heartbeat:Connect(function()
            if not State.View then return end
            UpdateCam()
        end)

        return true, "View: " .. target.DisplayName
    else
        ClearConn("View")
        Camera.CameraSubject = GetHumanoid()
        return false, "View OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              NOCLIP                                   ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleNoclip()
    State.Noclip = not State.Noclip

    if State.Noclip then
        Connections.NoclipLoop = RunService.Stepped:Connect(function()
            if not State.Noclip then return end
            local c = GetChar()
            if not c then return end
            for _, p in c:GetDescendants() do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
        return true, "Noclip ATIVO!"
    else
        ClearConn("Noclip")
        return false, "Noclip OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              SPEED BOOST                              ║
-- ╚═══════════════════════════════════════════════════════╝

local _originalSpeed = 16

function ToggleSpeed()
    State.Speed = not State.Speed

    if State.Speed then
        local h = GetHumanoid()
        if h then
            _originalSpeed = h.WalkSpeed
            h.WalkSpeed = _originalSpeed * Config.SpeedMultiplier
        end

        Connections.SpeedLoop = RunService.Heartbeat:Connect(function()
            if not State.Speed then return end
            local h2 = GetHumanoid()
            if h2 then
                local target = _originalSpeed * Config.SpeedMultiplier
                if h2.WalkSpeed < target then h2.WalkSpeed = target end
            end
        end)
        return true, "Speed x" .. Config.SpeedMultiplier
    else
        ClearConn("Speed")
        local h = GetHumanoid()
        if h then h.WalkSpeed = _originalSpeed end
        return false, "Speed OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              ESP (Highlight)                          ║
-- ╚═══════════════════════════════════════════════════════╝

local _espHighlights = {}

function ToggleESP()
    State.ESP = not State.ESP

    if State.ESP then
        local function CreateESP(plr)
            if plr == LP then return end
            if _espHighlights[plr] then
                pcall(game.Destroy, _espHighlights[plr])
                _espHighlights[plr] = nil
            end
            if not plr.Character then return end

            local hl = Instance.new("Highlight")
            hl.Name = "_NDSesp"
            hl.FillColor = Color3.fromRGB(255, 0, 0)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = plr.Character
            hl.Parent = plr.Character
            _espHighlights[plr] = hl
        end

        for _, plr in Players:GetPlayers() do
            CreateESP(plr)
            Connections["ESPc_" .. plr.UserId] = plr.CharacterAdded:Connect(function()
                task.wait(0.3); if State.ESP then CreateESP(plr) end
            end)
        end

        Connections.ESPAdded = Players.PlayerAdded:Connect(function(plr)
            Connections["ESPc_" .. plr.UserId] = plr.CharacterAdded:Connect(function()
                task.wait(0.3); if State.ESP then CreateESP(plr) end
            end)
        end)

        Connections.ESPRemoved = Players.PlayerRemoving:Connect(function(plr)
            if _espHighlights[plr] then
                pcall(game.Destroy, _espHighlights[plr])
                _espHighlights[plr] = nil
            end
        end)

        return true, "ESP ATIVO!"
    else
        ClearConn("ESP")
        for _, hl in _espHighlights do pcall(game.Destroy, hl) end
        table.clear(_espHighlights)
        return false, "ESP OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║        TELEKINESIS (PC + Mobile)                      ║
-- ║  Click/Touch = pegar | Scroll/Pinch = distância       ║
-- ║  Right Click / 2 dedos = arremessar                   ║
-- ╚═══════════════════════════════════════════════════════╝

function ToggleTelekinesis()
    State.Telekinesis = not State.Telekinesis

    if State.Telekinesis then
        local indicator = Instance.new("Part")
        indicator.Name = "_NDStelek"
        indicator.Size = Vector3.new(0.5, 0.5, 0.5)
        indicator.Shape = Enum.PartType.Ball
        indicator.Material = Enum.Material.Neon
        indicator.Color = Color3.fromRGB(138, 43, 226)
        indicator.Transparency = 0.3
        indicator.CanCollide = false; indicator.Anchored = true
        indicator.Parent = Workspace
        table.insert(CreatedObjects, indicator)

        -- Raio de seleção reutilizável
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        Connections.TelekSelect = UIS.InputBegan:Connect(function(input, gpe)
            if gpe or not State.Telekinesis then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then return end

            rayParams.FilterDescendantsInstances = { GetChar(), AnchorPart, MotionAnchor }
            local ray = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
            local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)

            if result and result.Instance and result.Instance:IsA("BasePart") then
                local part = result.Instance
                pcall(function() part.Anchored = false end)
                if TelekTarget and TelekTarget ~= part then
                    CleanPartControl(TelekTarget)
                end
                TelekTarget = part
                TelekDist = (part.Position - Camera.CFrame.Position).Magnitude
                SetupPartControl(part, MainAttachment)
                Notify("Telecinese", part.Name, 1)
            end
        end)

        Connections.TelekMove = RunService.RenderStepped:Connect(function()
            if not State.Telekinesis or not TelekTarget or not TelekTarget.Parent then return end
            local mousePos = UIS:GetMouseLocation()
            local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
            local targetPos = ray.Origin + ray.Direction * TelekDist
            if AnchorPart then AnchorPart.CFrame = CFrame.new(targetPos) end
            if indicator and indicator.Parent then indicator.CFrame = CFrame.new(targetPos) end
        end)

        Connections.TelekScroll = UIS.InputChanged:Connect(function(input)
            if not State.Telekinesis then return end
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                TelekDist = math.clamp(TelekDist + input.Position.Z * 5, 5, 200)
            end
        end)

        Connections.TelekRelease = UIS.InputBegan:Connect(function(input)
            if not State.Telekinesis then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                if TelekTarget then
                    pcall(function()
                        TelekTarget.AssemblyLinearVelocity = Camera.CFrame.LookVector * 200
                    end)
                    CleanPartControl(TelekTarget)
                    TelekTarget = nil
                    AnchorPart.CFrame = ANCHOR_CF
                    Notify("Telecinese", "Arremessado!", 1)
                end
            end
        end)

        return true, "Telecinese ATIVA!"
    else
        ClearConn("Telek")
        if TelekTarget then
            CleanPartControl(TelekTarget)
            TelekTarget = nil
        end
        AnchorPart.CFrame = ANCHOR_CF
        for i, obj in CreatedObjects do
            if obj and obj.Name == "_NDStelek" then
                pcall(game.Destroy, obj)
                CreatedObjects[i] = nil
            end
        end
        return false, "Telecinese OFF"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║         TELEPORT TO PLAYER                            ║
-- ╚═══════════════════════════════════════════════════════╝

function TeleportToPlayer()
    local sel = State.SelectedPlayer
    if not sel or not sel.Character then return false, "Selecione um player!" end
    local hrp = GetHRP()
    local tHRP = sel.Character:FindFirstChild("HumanoidRootPart")
    if hrp and tHRP then
        hrp.CFrame = tHRP.CFrame * CFrame.new(0, 0, 3)
        return true, "Teleportado!"
    end
    return false, "Erro!"
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║         FLY GUI V3 (COMPACTO + MOBILE)                ║
-- ║  Joystick nativo funciona | Botões touch              ║
-- ║  UP/DOWN com hold pattern | Auto-cleanup              ║
-- ╚═══════════════════════════════════════════════════════╝

local FlyV3 = { GUI = nil, Active = false }

local function CreateFlyGui()
    if FlyV3.GUI then pcall(game.Destroy, FlyV3.GUI) end

    local sg = Instance.new("ScreenGui")
    sg.Name = "_NDSFly"
    sg.ResetOnSpawn = false
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() sg.Parent = CoreGui end)
    if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end
    FlyV3.GUI = sg

    local flying = false
    local speeds = 1
    local tpWalking = false
    local ctrl = { f = 0, b = 0, l = 0, r = 0 }
    local lastCtrl = { f = 0, b = 0, l = 0, r = 0 }
    local bg, bv

    -- Frame
    local fr = Instance.new("Frame")
    fr.Size = UDim2.new(0, 190, 0, 57)
    fr.Position = UDim2.new(0.1, 0, 0.38, 0)
    fr.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    fr.BorderSizePixel = 0; fr.Active = true; fr.Draggable = true
    fr.Parent = sg
    Instance.new("UICorner").Parent = fr
    local frStroke = Instance.new("UIStroke")
    frStroke.Color = Color3.fromRGB(138, 43, 226)
    frStroke.Thickness = 1; frStroke.Parent = fr

    -- Botão helper
    local function Btn(text, pos, size, color)
        local b = Instance.new("TextButton")
        b.Text = text; b.Position = pos; b.Size = size
        b.BackgroundColor3 = color
        b.TextColor3 = Color3.fromRGB(255, 255, 255)
        b.Font = Enum.Font.GothamBold; b.TextSize = 13
        b.Parent = fr
        Instance.new("UICorner").Parent = b
        return b
    end

    local btnUp    = Btn("UP",   UDim2.new(0,0,0,0),       UDim2.new(0,44,0,28), Color3.fromRGB(50,180,100))
    local btnDown  = Btn("DOWN", UDim2.new(0,0,0.5,0),     UDim2.new(0,44,0,28), Color3.fromRGB(180,180,50))
    local btnMinus = Btn("-",    UDim2.new(0.23,0,0.5,0),  UDim2.new(0,45,0,28), Color3.fromRGB(100,200,220))
    local btnPlus  = Btn("+",    UDim2.new(0.23,0,0,0),    UDim2.new(0,45,0,28), Color3.fromRGB(100,120,255))
    local btnFly   = Btn("FLY",  UDim2.new(0.7,0,0.5,0),  UDim2.new(0,56,0,28), Color3.fromRGB(200,200,50))
    local btnClose = Btn("X",    UDim2.new(1,-30,0,-28),   UDim2.new(0,30,0,26), Color3.fromRGB(200,50,50))

    -- Título
    local titleL = Instance.new("TextLabel")
    titleL.Size = UDim2.new(0, 100, 0, 28)
    titleL.Position = UDim2.new(0.47, 0, 0, 0)
    titleL.BackgroundColor3 = Color3.fromRGB(138, 43, 226)
    titleL.Text = "FLY V3"; titleL.TextColor3 = Color3.fromRGB(255,255,255)
    titleL.Font = Enum.Font.GothamBold; titleL.TextScaled = true
    titleL.Parent = fr
    Instance.new("UICorner").Parent = titleL

    -- Speed label
    local speedL = Instance.new("TextLabel")
    speedL.Size = UDim2.new(0, 44, 0, 28)
    speedL.Position = UDim2.new(0.47, 0, 0.5, 0)
    speedL.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    speedL.Text = "1"; speedL.TextColor3 = Color3.fromRGB(255,255,255)
    speedL.Font = Enum.Font.GothamBold; speedL.TextScaled = true
    speedL.Parent = fr
    Instance.new("UICorner").Parent = speedL

    -- TP Walking (funciona com joystick mobile)
    local function StartTPWalk()
        tpWalking = true
        for _ = 1, speeds do
            task.spawn(function()
                local c, h = GetChar(), GetHumanoid()
                while tpWalking and c and h and h.Parent do
                    RunService.Heartbeat:Wait()
                    if h.MoveDirection.Magnitude > 0 then
                        c:TranslateBy(h.MoveDirection)
                    end
                end
            end)
        end
    end

    -- Humanoid states
    local function SetStates(on)
        local h = GetHumanoid(); if not h then return end
        local states = {
            "Climbing","FallingDown","Flying","Freefall","GettingUp",
            "Jumping","Landed","Physics","PlatformStanding","Ragdoll",
            "Running","RunningNoPhysics","Seated","StrafingNoPhysics","Swimming"
        }
        for _, s in states do
            pcall(function() h:SetStateEnabled(Enum.HumanoidStateType[s], on) end)
        end
        pcall(function()
            h:ChangeState(on and Enum.HumanoidStateType.RunningNoPhysics or Enum.HumanoidStateType.Swimming)
        end)
    end

    -- Stop fly
    local function StopFly()
        flying = false; FlyV3.Active = false; State.Fly = false
        tpWalking = false; SetStates(true)
        ctrl = { f=0, b=0, l=0, r=0 }
        if bg then bg:Destroy(); bg = nil end
        if bv then bv:Destroy(); bv = nil end
        local h = GetHumanoid(); if h then h.PlatformStand = false end
        local c = GetChar()
        if c then local an = c:FindFirstChild("Animate"); if an then an.Disabled = false end end
        ClearConn("FlyV3")
    end

    -- FLY toggle
    btnFly.MouseButton1Click:Connect(function()
        local c = GetChar(); local h = GetHumanoid()
        if not c or not h then return end
        if flying then StopFly(); return end

        flying = true; FlyV3.Active = true; State.Fly = true
        StartTPWalk()

        local animate = c:FindFirstChild("Animate")
        if animate then animate.Disabled = true end
        for _, v in h:GetPlayingAnimationTracks() do v:AdjustSpeed(0) end
        SetStates(false)

        local torso = c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso")
        if not torso then StopFly(); return end

        bg = Instance.new("BodyGyro", torso)
        bg.P = 9e4; bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.CFrame = torso.CFrame

        bv = Instance.new("BodyVelocity", torso)
        bv.Velocity = Vector3.new(0, 0.1, 0)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        h.PlatformStand = true

        local maxspeed = 50; local speed = 0

        -- Teclado (PC)
        Connections.FlyV3Key = UIS.InputBegan:Connect(function(inp, gpe)
            if gpe then return end
            if inp.KeyCode == Enum.KeyCode.W then ctrl.f = 1 end
            if inp.KeyCode == Enum.KeyCode.S then ctrl.b = -1 end
            if inp.KeyCode == Enum.KeyCode.A then ctrl.l = -1 end
            if inp.KeyCode == Enum.KeyCode.D then ctrl.r = 1 end
        end)
        Connections.FlyV3KeyUp = UIS.InputEnded:Connect(function(inp)
            if inp.KeyCode == Enum.KeyCode.W then ctrl.f = 0 end
            if inp.KeyCode == Enum.KeyCode.S then ctrl.b = 0 end
            if inp.KeyCode == Enum.KeyCode.A then ctrl.l = 0 end
            if inp.KeyCode == Enum.KeyCode.D then ctrl.r = 0 end
        end)

        -- Loop principal
        Connections.FlyV3Loop = RunService.RenderStepped:Connect(function()
            if not flying or not bv or not bg or h.Health == 0 then return end

            -- Mobile: usa MoveDirection do joystick como input
            if UIS.TouchEnabled then
                local moveDir = h.MoveDirection
                if moveDir.Magnitude > 0.1 then
                    ctrl.f = moveDir.Z < -0.1 and 1 or (moveDir.Z > 0.1 and -1 or 0)
                    ctrl.l = moveDir.X < -0.1 and -1 or (moveDir.X > 0.1 and 1 or 0)
                else
                    ctrl.f = 0; ctrl.l = 0
                end
            end

            local moving = (ctrl.l + ctrl.r ~= 0) or (ctrl.f + ctrl.b ~= 0)
            if moving then
                speed = math.min(speed + 0.5 + speed / maxspeed, maxspeed)
            else
                speed = math.max(speed - 1, 0)
            end

            local cam = Camera
            if moving then
                bv.Velocity = (cam.CFrame.LookVector * (ctrl.f + ctrl.b)
                    + (cam.CFrame * CFrame.new(ctrl.l + ctrl.r, (ctrl.f + ctrl.b) * 0.2, 0).Position
                    - cam.CFrame.Position)) * speed
                lastCtrl = { f = ctrl.f, b = ctrl.b, l = ctrl.l, r = ctrl.r }
            elseif speed > 0 then
                bv.Velocity = (cam.CFrame.LookVector * (lastCtrl.f + lastCtrl.b)
                    + (cam.CFrame * CFrame.new(lastCtrl.l + lastCtrl.r, (lastCtrl.f + lastCtrl.b) * 0.2, 0).Position
                    - cam.CFrame.Position)) * speed
            else
                bv.Velocity = Vector3.zero
            end
            bg.CFrame = cam.CFrame * CFrame.Angles(-math.rad((ctrl.f + ctrl.b) * 50 * speed / maxspeed), 0, 0)
        end)
    end)

    -- UP / DOWN (hold pattern — mobile friendly)
    local function HoldButton(btn, dir)
        local holding = false
        btn.MouseButton1Down:Connect(function()
            holding = true
            task.spawn(function()
                while holding do
                    local hrp = GetHRP()
                    if hrp then hrp.CFrame *= CFrame.new(0, dir, 0) end
                    task.wait()
                end
            end)
        end)
        btn.MouseButton1Up:Connect(function() holding = false end)
        btn.MouseLeave:Connect(function() holding = false end)
    end
    HoldButton(btnUp, 1)
    HoldButton(btnDown, -1)

    -- Speed +/-
    btnPlus.MouseButton1Click:Connect(function()
        speeds += 1; speedL.Text = tostring(speeds)
        if flying then tpWalking = false; task.wait(0.05); StartTPWalk() end
    end)
    btnMinus.MouseButton1Click:Connect(function()
        if speeds <= 1 then
            speedL.Text = "min!"
            task.delay(0.5, function() speedL.Text = "1" end)
            return
        end
        speeds -= 1; speedL.Text = tostring(speeds)
        if flying then tpWalking = false; task.wait(0.05); StartTPWalk() end
    end)

    -- Close
    btnClose.MouseButton1Click:Connect(function()
        if flying then StopFly() end
        FlyV3.GUI = nil; sg:Destroy()
    end)

    -- Respawn
    local respConn
    respConn = LP.CharacterAdded:Connect(function()
        task.wait(0.5); StopFly()
    end)
    sg.Destroying:Connect(function()
        if respConn then respConn:Disconnect() end
    end)

    return sg
end

function ToggleFly()
    if not FlyV3.GUI then
        CreateFlyGui()
        return true, "Fly GUI aberto!"
    else
        pcall(game.Destroy, FlyV3.GUI)
        FlyV3.GUI = nil; State.Fly = false
        return false, "Fly GUI fechado"
    end
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║     DISABLE ALL (ATUALIZADO COM SKYLIFT)              ║
-- ╚═══════════════════════════════════════════════════════╝

function DisableAllFunctions()
    SetMode("None", nil)
    State.ServerMagnet = false; ClearConn("ServerMagnet"); CleanEnemyAnchors()
    State.HatFling = false;    ClearConn("HatFling")
    State.BodyFling = false;   ClearConn("BodyFling")
    State.Launch = false;      ClearConn("Launch")
    State.GodMode = false;     ClearConn("GodMode")
    State.View = false;        ClearConn("View")
    State.Noclip = false;      ClearConn("Noclip")
    State.Speed = false;       ClearConn("Speed")
    State.Telekinesis = false; ClearConn("Telek")
    State.SkyLift = false;     ClearConn("SkyLift")
    -- Limpa peças do SkyLift
    for _, data in _skyLiftData do
        if type(data) == "table" then
            pcall(function()
                if data.align  then data.align:Destroy() end
                if data.att0   then data.att0:Destroy() end
                if data.att1   then data.att1:Destroy() end
                if data.part   then data.part:Destroy() end
                if data.anchor then data.anchor:Destroy() end
            end)
        end
    end
    table.clear(_skyLiftData)
    _skyLiftHeight = 0
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║         RESPAWN HANDLER                               ║
-- ╚═══════════════════════════════════════════════════════╝

LP.CharacterAdded:Connect(function()
    DisableAllFunctions()
    task.wait(1)
    SetupNetwork()
end)

print("[NDS v9.0] PARTE 2/3 carregada — Ações + SkyLift + Fly Mobile")
-- ══════════════════════════════════════════════════════
-- CONTINUE COLANDO A PARTE 3 ABAIXO DESTE PONTO
-- ══════════════════════════════════════════════════════
-- ══════════════════════════════════════════════════════
-- PARTE 3/3: INTERFACE — Cole ABAIXO da Parte 2
-- ══════════════════════════════════════════════════════

-- ╔═══════════════════════════════════════════════════════╗
-- ║           UI ENGINE — NDS TROLL HUB v9.0              ║
-- ║  Dark theme | Roxo accent | Scroll | Drag | Mobile   ║
-- ╚═══════════════════════════════════════════════════════╝

local function CreateUI()
    -- Limpar UI anterior
    pcall(function() CoreGui:FindFirstChild("NDSTrollHub"):Destroy() end)
    pcall(function() LP.PlayerGui:FindFirstChild("NDSTrollHub"):Destroy() end)

    -- ═══ CORES ═══
    local C = {
        Bg      = Color3.fromRGB(18, 18, 22),
        Card    = Color3.fromRGB(28, 28, 35),
        Accent  = Color3.fromRGB(138, 43, 226),
        Text    = Color3.fromRGB(240, 240, 240),
        Dim     = Color3.fromRGB(110, 110, 120),
        Green   = Color3.fromRGB(50, 205, 50),
        Red     = Color3.fromRGB(220, 50, 50),
        Orange  = Color3.fromRGB(255, 165, 0),
    }

    -- ═══ SCREEN GUI ═══
    local SG = Instance.new("ScreenGui")
    SG.Name = "NDSTrollHub"
    SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    SG.ResetOnSpawn = false
    pcall(function() SG.Parent = CoreGui end)
    if not SG.Parent then SG.Parent = LP:WaitForChild("PlayerGui") end

    -- ═══ HELPERS DE CONSTRUÇÃO ═══
    local function Corner(parent, r)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, r or 8)
        c.Parent = parent
        return c
    end

    local function Stroke(parent, color, thick)
        local s = Instance.new("UIStroke")
        s.Color = color or C.Accent
        s.Thickness = thick or 1.5
        s.Parent = parent
        return s
    end

    local function Label(parent, text, size, color, font, align)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.Text = text
        l.TextColor3 = color or C.Text
        l.Font = font or Enum.Font.Gotham
        l.TextSize = size or 12
        l.TextXAlignment = align or Enum.TextXAlignment.Left
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.Parent = parent
        return l
    end

    -- ═══ MAIN FRAME ═══
    local Main = Instance.new("Frame")
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 310, 0, 440)
    Main.Position = UDim2.new(0.5, -155, 0.5, -220)
    Main.BackgroundColor3 = C.Bg
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.Parent = SG
    Corner(Main, 12)
    Stroke(Main, C.Accent, 2)

    -- ═══ HEADER ═══
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 38)
    Header.BackgroundColor3 = C.Card
    Header.BorderSizePixel = 0
    Header.Parent = Main
    Corner(Header, 12)

    -- Fix cantos inferiores do header
    local HFix = Instance.new("Frame")
    HFix.Size = UDim2.new(1, 0, 0, 12)
    HFix.Position = UDim2.new(0, 0, 1, -12)
    HFix.BackgroundColor3 = C.Card
    HFix.BorderSizePixel = 0
    HFix.Parent = Header

    -- Título
    local Title = Label(Header, "⚡ NDS Troll Hub v9.0", 13, C.Text, Enum.Font.GothamBold)
    Title.Size = UDim2.new(1, -80, 1, 0)
    Title.Position = UDim2.new(0, 12, 0, 0)

    -- Botão Minimizar
    local BtnMin = Instance.new("TextButton")
    BtnMin.Size = UDim2.new(0, 28, 0, 28)
    BtnMin.Position = UDim2.new(1, -64, 0, 5)
    BtnMin.BackgroundColor3 = C.Accent
    BtnMin.Text = "—"; BtnMin.TextColor3 = C.Text
    BtnMin.Font = Enum.Font.GothamBold; BtnMin.TextSize = 14
    BtnMin.Parent = Header
    Corner(BtnMin, 6)

    -- Botão Fechar
    local BtnClose = Instance.new("TextButton")
    BtnClose.Size = UDim2.new(0, 28, 0, 28)
    BtnClose.Position = UDim2.new(1, -32, 0, 5)
    BtnClose.BackgroundColor3 = C.Red
    BtnClose.Text = "✕"; BtnClose.TextColor3 = C.Text
    BtnClose.Font = Enum.Font.GothamBold; BtnClose.TextSize = 12
    BtnClose.Parent = Header
    Corner(BtnClose, 6)

    -- ═══ CONTENT CONTAINER ═══
    local Content = Instance.new("Frame")
    Content.Name = "Content"
    Content.Size = UDim2.new(1, -16, 1, -46)
    Content.Position = UDim2.new(0, 8, 0, 42)
    Content.BackgroundTransparency = 1
    Content.Parent = Main

    -- ═══ PLAYER SELECTOR ═══
    local PlayerBox = Instance.new("Frame")
    PlayerBox.Size = UDim2.new(1, 0, 0, 95)
    PlayerBox.BackgroundColor3 = C.Card
    PlayerBox.BorderSizePixel = 0
    PlayerBox.Parent = Content
    Corner(PlayerBox, 8)

    local SelLabel = Label(PlayerBox, "🎯 Selecionar Alvo:", 10, C.Dim, Enum.Font.GothamBold)
    SelLabel.Size = UDim2.new(1, -10, 0, 16)
    SelLabel.Position = UDim2.new(0, 8, 0, 4)

    -- Lista de players (scroll horizontal compacto)
    local PList = Instance.new("ScrollingFrame")
    PList.Size = UDim2.new(1, -12, 0, 48)
    PList.Position = UDim2.new(0, 6, 0, 22)
    PList.BackgroundColor3 = C.Bg
    PList.BorderSizePixel = 0
    PList.ScrollBarThickness = 3
    PList.ScrollBarImageColor3 = C.Accent
    PList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    PList.CanvasSize = UDim2.new(0, 0, 0, 0)
    PList.Parent = PlayerBox
    Corner(PList, 6)

    local PLayout = Instance.new("UIListLayout")
    PLayout.SortOrder = Enum.SortOrder.Name
    PLayout.Padding = UDim.new(0, 2)
    PLayout.Parent = PList

    local PPad = Instance.new("UIPadding")
    PPad.PaddingTop = UDim.new(0, 3)
    PPad.PaddingBottom = UDim.new(0, 3)
    PPad.PaddingLeft = UDim.new(0, 3)
    PPad.PaddingRight = UDim.new(0, 3)
    PPad.Parent = PList

    -- Status text
    local SelStatus = Label(PlayerBox, "Nenhum selecionado", 9, C.Dim)
    SelStatus.Size = UDim2.new(1, -12, 0, 14)
    SelStatus.Position = UDim2.new(0, 8, 1, -17)

    -- Atualizar lista
    local function RefreshPlayers()
        for _, ch in PList:GetChildren() do
            if ch:IsA("TextButton") then ch:Destroy() end
        end

        for _, plr in Players:GetPlayers() do
            local isSelected = State.SelectedPlayer == plr
            local btn = Instance.new("TextButton")
            btn.Name = plr.Name
            btn.Size = UDim2.new(1, -6, 0, 20)
            btn.BackgroundColor3 = isSelected and C.Accent or C.Card
            btn.Text = plr.DisplayName
            btn.TextColor3 = C.Text
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 10
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.Parent = PList
            Corner(btn, 4)

            btn.MouseButton1Click:Connect(function()
                State.SelectedPlayer = plr
                SetTarget(plr)
                SelStatus.Text = "✓ " .. plr.DisplayName
                SelStatus.TextColor3 = C.Green
                RefreshPlayers()
                Notify("Alvo", plr.DisplayName, 1)
            end)
        end
    end

    RefreshPlayers()
    Players.PlayerAdded:Connect(RefreshPlayers)
    Players.PlayerRemoving:Connect(function(plr)
        if State.SelectedPlayer == plr then
            State.SelectedPlayer = nil
            SelStatus.Text = "Player saiu!"
            SelStatus.TextColor3 = C.Red
        end
        task.wait(0.1)
        RefreshPlayers()
    end)

    -- ═══ SCROLL DE BOTÕES ═══
    local BtnScroll = Instance.new("ScrollingFrame")
    BtnScroll.Name = "Buttons"
    BtnScroll.Size = UDim2.new(1, 0, 1, -102)
    BtnScroll.Position = UDim2.new(0, 0, 0, 100)
    BtnScroll.BackgroundTransparency = 1
    BtnScroll.BorderSizePixel = 0
    BtnScroll.ScrollBarThickness = 3
    BtnScroll.ScrollBarImageColor3 = C.Accent
    BtnScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    BtnScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    BtnScroll.Parent = Content

    local BLayout = Instance.new("UIListLayout")
    BLayout.SortOrder = Enum.SortOrder.LayoutOrder
    BLayout.Padding = UDim.new(0, 4)
    BLayout.Parent = BtnScroll

    local BPad = Instance.new("UIPadding")
    BPad.PaddingTop = UDim.new(0, 2)
    BPad.PaddingBottom = UDim.new(0, 8)
    BPad.Parent = BtnScroll

    -- Tabela de indicadores para atualização externa
    local Indicators = {}

    -- ═══ CRIADOR DE CATEGORIA ═══
    local function Category(name, order)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, 0, 0, 20)
        f.BackgroundTransparency = 1
        f.LayoutOrder = order
        f.Parent = BtnScroll

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -8, 0, 1)
        line.Position = UDim2.new(0, 4, 0.5, 0)
        line.BackgroundColor3 = C.Accent
        line.BackgroundTransparency = 0.7
        line.BorderSizePixel = 0
        line.Parent = f

        local lbl = Label(f, "  " .. name .. "  ", 9, C.Accent, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
        lbl.Size = UDim2.new(0, 0, 1, 0)
        lbl.Position = UDim2.new(0.5, 0, 0, 0)
        lbl.AnchorPoint = Vector2.new(0.5, 0)
        lbl.AutomaticSize = Enum.AutomaticSize.X
        lbl.BackgroundColor3 = C.Bg
        lbl.BackgroundTransparency = 0
    end

    -- ═══ CRIADOR DE TOGGLE ═══
    local function Toggle(name, callback, order, stateKey)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = C.Card
        btn.Text = ""
        btn.LayoutOrder = order
        btn.AutoButtonColor = false
        btn.Parent = BtnScroll
        Corner(btn, 6)

        -- Hover effect
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(38, 38, 48)}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = C.Card}):Play()
        end)

        local lbl = Label(btn, name, 11, C.Text, Enum.Font.Gotham)
        lbl.Size = UDim2.new(1, -40, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)

        -- Indicador circular
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 12, 0, 12)
        dot.Position = UDim2.new(1, -22, 0.5, -6)
        dot.BackgroundColor3 = C.Dim
        dot.Parent = btn
        Corner(dot, 6)

        if stateKey then Indicators[stateKey] = dot end

        btn.MouseButton1Click:Connect(function()
            local ok, msg = callback()
            -- Animação do indicador
            local color = ok and C.Green or C.Dim
            TweenService:Create(dot, TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
            -- Feedback de escala
            TweenService:Create(btn, TweenInfo.new(0.08), {Size = UDim2.new(0.98, 0, 0, 28)}):Play()
            task.delay(0.08, function()
                TweenService:Create(btn, TweenInfo.new(0.08), {Size = UDim2.new(1, 0, 0, 30)}):Play()
            end)
            if msg then Notify(name, msg, 2) end
        end)

        return btn
    end

    -- ═══ CRIADOR DE BOTÃO SIMPLES ═══
    local function SimpleBtn(name, callback, order, color)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.BackgroundColor3 = color or C.Card
        btn.Text = name
        btn.TextColor3 = C.Text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.LayoutOrder = order
        btn.AutoButtonColor = false
        btn.Parent = BtnScroll
        Corner(btn, 6)

        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = C.Accent}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = color or C.Card}):Play()
        end)

        btn.MouseButton1Click:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.06), {Size = UDim2.new(0.98, 0, 0, 28)}):Play()
            task.delay(0.06, function()
                TweenService:Create(btn, TweenInfo.new(0.06), {Size = UDim2.new(1, 0, 0, 30)}):Play()
            end)
            local ok, msg = callback()
            if msg then Notify(name, msg, 2) end
        end)

        return btn
    end

    -- ╔═══════════════════════════════════════════════════╗
    -- ║       CRIAÇÃO DOS BOTÕES — TODOS                  ║
    -- ╚═══════════════════════════════════════════════════╝

    -- ── ATAQUES COM PEÇAS ──
    Category("⚔️ ATAQUES COM PEÇAS", 1)
    Toggle("🧲 Íma de Objetos (Magnet)",    ToggleMagnet,        2,  "Magnet")
    Toggle("🌀 Orbit Attack",               ToggleOrbit,         3,  "Orbit")
    Toggle("🌪️ Spin Tornado",               ToggleSpin,          4,  "Spin")
    Toggle("🔵 Cage Sphere",                ToggleCage,          5,  "Cage")
    Toggle("💀 Server Magnet (Todos)",       ToggleServerMagnet,  6,  "ServerMagnet")
    Toggle("🚀 Launch (Bombardeio)",         ToggleLaunch,        7,  "Launch")

    -- ── TROLL PLAYER ──
    Category("🎯 TROLL NO PLAYER", 10)
    Toggle("⬆️ Sky Lift",                   ToggleSkyLift,       11, "SkyLift")
    Toggle("🎩 Hat Fling",                  ToggleHatFling,      12, "HatFling")
    Toggle("💥 Body Fling",                 ToggleBodyFling,     13, "BodyFling")
    Toggle("🔮 Telecinese (PC/Touch)",      ToggleTelekinesis,   14, "Telekinesis")
    SimpleBtn("📍 Teleportar ao Player",     TeleportToPlayer,    15, Color3.fromRGB(40, 40, 55))

    -- ── PERSONAGEM ──
    Category("🛡️ PERSONAGEM", 20)
    Toggle("❤️ God Mode",                   ToggleGodMode,       21, "GodMode")
    Toggle("⚡ Speed x3",                   ToggleSpeed,         22, "Speed")
    Toggle("👻 Noclip",                     ToggleNoclip,        23, "Noclip")
    SimpleBtn("✈️ Fly GUI V3",              ToggleFly,           24, Color3.fromRGB(40, 40, 55))

    -- ── VISUAL ──
    Category("👁️ VISUAL", 30)
    Toggle("📷 View Player",                ToggleView,          31, "View")
    Toggle("🔴 ESP (Highlight)",            ToggleESP,           32, "ESP")

    -- ── UTILITÁRIOS ──
    Category("🔧 UTILITÁRIOS", 40)
    SimpleBtn("🔄 Recapturar Peças", function()
        local n = CaptureParts(Config.MaxParts, Config.CaptureRadius)
        return n > 0, n .. " peças capturadas"
    end, 41, Color3.fromRGB(50, 35, 70))

    SimpleBtn("🗑️ Soltar Todas as Peças", function()
        ReleaseAllParts()
        return true, "Peças liberadas"
    end, 42, Color3.fromRGB(50, 35, 70))

    SimpleBtn("⛔ Desativar TUDO", function()
        DisableAllFunctions()
        -- Reseta todos os indicadores
        for _, dot in Indicators do
            TweenService:Create(dot, TweenInfo.new(0.2), {BackgroundColor3 = C.Dim}):Play()
        end
        return true, "Tudo desativado!"
    end, 43, C.Red)

    -- ═══ BOTÃO FLUTUANTE (Reabrir) ═══
    local FloatBtn = Instance.new("TextButton")
    FloatBtn.Name = "Float"
    FloatBtn.Size = UDim2.new(0, 46, 0, 46)
    FloatBtn.Position = UDim2.new(0, 10, 0.5, -23)
    FloatBtn.BackgroundColor3 = C.Accent
    FloatBtn.Text = "⚡"
    FloatBtn.TextColor3 = C.Text
    FloatBtn.Font = Enum.Font.GothamBold
    FloatBtn.TextSize = 18
    FloatBtn.Visible = false
    FloatBtn.Active = true
    FloatBtn.Parent = SG
    Corner(FloatBtn, 23)
    Stroke(FloatBtn, C.Text, 1)

    -- Pulse animation no float btn
    task.spawn(function()
        while SG and SG.Parent do
            if FloatBtn.Visible then
                TweenService:Create(FloatBtn, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Size = UDim2.new(0, 50, 0, 50),
                    Position = UDim2.new(FloatBtn.Position.X.Scale, FloatBtn.Position.X.Offset - 2, FloatBtn.Position.Y.Scale, FloatBtn.Position.Y.Offset - 2)
                }):Play()
                task.wait(0.8)
                if FloatBtn.Visible then
                    TweenService:Create(FloatBtn, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                        Size = UDim2.new(0, 46, 0, 46),
                        Position = UDim2.new(FloatBtn.Position.X.Scale, FloatBtn.Position.X.Offset + 2, FloatBtn.Position.Y.Scale, FloatBtn.Position.Y.Offset + 2)
                    }):Play()
                end
                task.wait(0.8)
            else
                task.wait(0.5)
            end
        end
    end)

    -- ╔═══════════════════════════════════════════════════╗
    -- ║          MINIMIZAR / FECHAR / REABRIR              ║
    -- ╚═══════════════════════════════════════════════════╝

    local minimized = false

    BtnMin.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 310, 0, 38)
            }):Play()
            BtnMin.Text = "+"
            task.delay(0.1, function() Content.Visible = false end)
        else
            Content.Visible = true
            TweenService:Create(Main, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
                Size = UDim2.new(0, 310, 0, 440)
            }):Play()
            BtnMin.Text = "—"
        end
    end)

    BtnClose.MouseButton1Click:Connect(function()
        TweenService:Create(Main, TweenInfo.new(0.2), {
            Position = UDim2.new(Main.Position.X.Scale, Main.Position.X.Offset, 1.5, 0)
        }):Play()
        task.delay(0.25, function()
            Main.Visible = false
            FloatBtn.Visible = true
        end)
    end)

    FloatBtn.MouseButton1Click:Connect(function()
        FloatBtn.Visible = false
        Main.Visible = true
        Main.Position = UDim2.new(0.5, -155, -0.5, 0)
        TweenService:Create(Main, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
            Position = UDim2.new(0.5, -155, 0.5, -220)
        }):Play()
    end)

    -- ╔═══════════════════════════════════════════════════╗
    -- ║          DRAG SYSTEM (PC + Mobile)                 ║
    -- ╚═══════════════════════════════════════════════════╝

    local function MakeDraggable(frame, handle)
        local dragging = false
        local dragStart, startPos

        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = frame.Position
            end
        end)

        handle.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        UIS.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                local delta = input.Position - dragStart
                frame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end)
    end

    MakeDraggable(Main, Header)
    MakeDraggable(FloatBtn, FloatBtn)

    -- ╔═══════════════════════════════════════════════════╗
    -- ║       ANIMAÇÃO DE ENTRADA                          ║
    -- ╚═══════════════════════════════════════════════════╝

    Main.Position = UDim2.new(0.5, -155, -0.5, 0)
    Main.BackgroundTransparency = 1

    task.delay(0.1, function()
        TweenService:Create(Main, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
            Position = UDim2.new(0.5, -155, 0.5, -220),
            BackgroundTransparency = 0,
        }):Play()
    end)

    -- ╔═══════════════════════════════════════════════════╗
    -- ║       INFO BAR (Rodapé com stats)                  ║
    -- ╚═══════════════════════════════════════════════════╝

    local InfoBar = Instance.new("Frame")
    InfoBar.Size = UDim2.new(1, 0, 0, 16)
    InfoBar.Position = UDim2.new(0, 0, 1, -16)
    InfoBar.BackgroundColor3 = C.Card
    InfoBar.BackgroundTransparency = 0.5
    InfoBar.BorderSizePixel = 0
    InfoBar.Parent = Main

    local InfoLabel = Label(InfoBar, "Peças: 0 | Modo: None | FPS: --", 8, C.Dim, Enum.Font.Gotham, Enum.TextXAlignment.Center)
    InfoLabel.Size = UDim2.new(1, 0, 1, 0)

    -- Atualizar info bar
    local _infoAcc = 0
    local _fpsFrames = 0
    local _fpsDisplay = 0

    RunService.Heartbeat:Connect(function(dt)
        _infoAcc += dt
        _fpsFrames += 1

        if _infoAcc >= 0.5 then
            _fpsDisplay = math.floor(_fpsFrames / _infoAcc)
            _fpsFrames = 0
            _infoAcc = 0

            local partCount = 0
            for _ in ActiveControls do partCount += 1 end

            local modeText = CurrentMode
            if State.ServerMagnet then modeText = "ServerMagnet" end
            if State.Launch then modeText = "Launch" end

            InfoLabel.Text = string.format(
                "⚙️ Peças: %d | Modo: %s | FPS: %d",
                partCount, modeText, _fpsDisplay
            )

            -- Cor do FPS
            if _fpsDisplay >= 50 then
                InfoLabel.TextColor3 = C.Green
            elseif _fpsDisplay >= 30 then
                InfoLabel.TextColor3 = C.Orange
            else
                InfoLabel.TextColor3 = C.Red
            end
        end
    end)

    return SG
end

-- ╔═══════════════════════════════════════════════════════╗
-- ║              INICIALIZAÇÃO FINAL                      ║
-- ╚═══════════════════════════════════════════════════════╝

local UI = CreateUI()

-- Notificação de boas-vindas
task.delay(0.8, function()
    Notify("NDS Troll Hub v9.0", "Carregado com sucesso!", 3)
end)

-- Cleanup ao fechar/reiniciar
CoreGui.ChildRemoved:Connect(function(child)
    if child.Name == "NDSTrollHub" then
        FlushAll()
        ShutdownMotionEngine()
        DisableAllFunctions()
    end
end)

print("[NDS v9.0] PARTE 3/3 carregada — Interface completa")
print("═══════════════════════════════════════════════")
print("  NDS TROLL HUB v9.0 — PRONTO PARA USO!")
print("  Core + Engine + Ações + UI = INTEGRADO")
print("═══════════════════════════════════════════════")
