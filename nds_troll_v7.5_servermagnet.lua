--[[
    ╔═══════════════════════════════════════════════════════════════════════════╗
    ║                     NDS TROLL HUB v7.5 - SERVER MAGNET                         ║
    ║                   Natural Disaster Survival                               ║
    ║                 Compatível com Executores Mobile                          ║
    ╚═══════════════════════════════════════════════════════════════════════════╝
--]]

-- SERVIÇOS
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- CONFIGURAÇÃO
local Config = {
    OrbitRadius = 25,
    OrbitSpeed = 2,
    OrbitHeight = 5,
    MagnetForce = 500,
    SpinRadius = 15,
    SpinSpeed = 4,
    FlySpeed = 60,
    SpeedMultiplier = 3,
    
    -- OTIMIZAÇÕES DE PERFORMANCE (baseado em pesquisa)
    OrbitUpdateInterval = 0.05,  -- 20 FPS para orbit (era 60)
    BlackholeUpdateInterval = 0.05,  -- 20 FPS para blackhole
    SpinUpdateInterval = 0.05,  -- 20 FPS para spin
    
    -- COMPETIÇÃO (SÓ PARA ORBIT)
    OrbitRecaptureInterval = 0.3,  -- Re-captura rápida para Orbit competir
    OrbitResponsiveness = 400,  -- Responsiveness maior só para Orbit
    OrbitMaxVelocity = 800,  -- Velocidade maior só para Orbit
}

-- ESTADO
local State = {
    SelectedPlayer = nil,
    Magnet = false,
    Orbit = false,
    Blackhole = false,
    PartRain = false,
    Cage = false,
    Spin = false,
    HatFling = false,
    BodyFling = false,
    Launch = false,
    SlowPlayer = false,
    GodMode = false,
    Fly = false,
    View = false,
    Noclip = false,
    Speed = false,
    ESP = false,
    Telekinesis = false,
    SkyLift = false,
    ServerMagnet = false,
}

--[[ ═══════════════════════════════════════════════════════════════════════
     NDS TROLL HUB — CORE REFATORADO
     Object Pooling | Network Dominance | Super Strong Physics
     ═══════════════════════════════════════════════════════════════════════ ]]

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  CONSTANTES PRÉ-ALOCADAS (zero alocação em runtime)                │
-- └──────────────────────────────────────────────────────────────────────┘
local ALIGN_MAX_VELOCITY       = 1000
local ALIGN_RESPONSIVENESS     = 200
local PART_DENSITY             = 0.01
local SIM_RADIUS_VALUE         = 1e9   -- Alto mas finito (estável)
local NETWORK_TICK_RATE        = 0.5   -- Intervalo do heartbeat de rede (s)
local ANCHOR_SIZE              = Vector3.new(1, 1, 1)
local ANCHOR_CFRAME            = CFrame.new(0, 10000, 0)
local HUGE_AXIS_FORCE          = Vector3.new(math.huge, math.huge, math.huge)
local LIGHT_PHYSICS            = PhysicalProperties.new(PART_DENSITY, 0, 0, 0, 0)

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  SERVIÇOS (cache local para acesso rápido)                          │
-- └──────────────────────────────────────────────────────────────────────┘
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local LocalPlayer  = Players.LocalPlayer

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  ESTADO GLOBAL                                                      │
-- └──────────────────────────────────────────────────────────────────────┘
local CreatedObjects = {}
local AnchorPart     = nil  :: Part?
local MainAttachment = nil  :: Attachment?

-- Conexão do Heartbeat de rede (referência para cleanup)
local _networkHeartbeat     = nil  :: RBXScriptConnection?
local _networkAccumulator   = 0

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  OBJECT POOLING — Attachment & AlignPosition                        │
-- │                                                                     │
-- │  Lógica: Nunca chama Instance.new após warm-up.                     │
-- │  Nunca chama :Destroy(). Objetos são desativados (Enabled=false,    │
-- │  Parent=nil) e devolvidos à pool para reutilização imediata.        │
-- └──────────────────────────────────────────────────────────────────────┘

local AttachmentPool      = {}  -- Stack de Attachments disponíveis
local AlignPositionPool   = {}  -- Stack de AlignPositions disponíveis

-- Mapa de controle ativo: [BasePart] → { attach: Attachment, align: AlignPosition }
-- Evita FindFirstChild() repetido — lookup O(1).
local ActiveControls = {}

-- Backup de propriedades originais: [BasePart] → { CanCollide, CanQuery, CanTouch, Physics }
local OriginalProperties = {}

--- Retira um Attachment da pool (ou cria um novo se a pool estiver vazia).
--- @param parent Instance — O BasePart onde será parenteado.
--- @return Attachment
local function AcquireAttachment(parent: Instance): Attachment
    local attach = table.remove(AttachmentPool)
    if attach then
        attach.Parent = parent
        return attach
    end

    -- Pool vazia: criação única (acontece só no warm-up)
    local newAttach = Instance.new("Attachment")
    newAttach.Name = "_NDSAttach"
    newAttach.Parent = parent
    return newAttach
end

--- Retira um AlignPosition da pool (ou cria e configura um novo).
--- A configuração de força/velocidade/responsividade é feita APENAS
--- na criação — nunca repetida ao reutilizar.
--- @param parent Instance
--- @param att0 Attachment — Attachment no objeto controlado
--- @param att1 Attachment — Attachment âncora (MainAttachment)
--- @return AlignPosition
local function AcquireAlignPosition(parent: Instance, att0: Attachment, att1: Attachment): AlignPosition
    local align = table.remove(AlignPositionPool)

    if align then
        -- Reutilização: apenas reconecta os attachments e reativa
        align.Attachment0 = att0
        align.Attachment1 = att1
        align.Enabled = true
        align.Parent = parent
        return align
    end

    -- Pool vazia: criação + configuração completa (uma única vez)
    local newAlign = Instance.new("AlignPosition")
    newAlign.Name = "_NDSAlign"
    newAlign.RigidityEnabled = false
    newAlign.MaxVelocity = ALIGN_MAX_VELOCITY
    newAlign.Responsiveness = ALIGN_RESPONSIVENESS

    -- Tenta API moderna (ForceLimitMode.PerAxis) para força independente por eixo
    local perAxisOk = pcall(function()
        newAlign.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        newAlign.MaxAxesForce = HUGE_AXIS_FORCE
    end)

    -- Fallback: API legada com MaxForce escalar
    if not perAxisOk then
        pcall(function()
            newAlign.MaxForce = math.huge
        end)
    end

    newAlign.Attachment0 = att0
    newAlign.Attachment1 = att1
    newAlign.Parent = parent
    return newAlign
end

--- Devolve um Attachment à pool (desparenta, mas NÃO destrói).
--- @param attach Attachment?
local function ReleaseAttachment(attach: Attachment?)
    if not attach then return end
    attach.Parent = nil
    table.insert(AttachmentPool, attach)
end

--- Devolve um AlignPosition à pool (desativa, limpa refs, desparenta).
--- @param align AlignPosition?
local function ReleaseAlignPosition(align: AlignPosition?)
    if not align then return end
    align.Enabled = false
    align.Attachment0 = nil  -- Libera referência ao part (evita memory leak)
    align.Attachment1 = nil
    align.Parent = nil
    table.insert(AlignPositionPool, align)
end

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  NETWORK OWNERSHIP AGRESSIVO                                        │
-- │                                                                     │
-- │  • Heartbeat dedicado com throttle (não roda todo frame)            │
-- │  • Maximiza SimulationRadius + MaximumSimulationRadius              │
-- │  • Verificação segura de existência das funções do executor         │
-- └──────────────────────────────────────────────────────────────────────┘

--- Função interna que força o SimulationRadius ao máximo.
--- Chamada periodicamente pelo Heartbeat.
local function ForceSimulationRadius()
    -- Método 1: sethiddenproperty (Synapse, Script-Ware, Fluxus, etc.)
    local _sethiddenproperty = typeof(sethiddenproperty) == "function" and sethiddenproperty or nil
    if _sethiddenproperty then
        pcall(_sethiddenproperty, LocalPlayer, "SimulationRadius", SIM_RADIUS_VALUE)
        pcall(_sethiddenproperty, LocalPlayer, "MaximumSimulationRadius", SIM_RADIUS_VALUE)
    end

    -- Método 2: setsimulationradius (API alternativa de alguns executores)
    local _setsimulationradius = typeof(setsimulationradius) == "function" and setsimulationradius or nil
    if _setsimulationradius then
        pcall(_setsimulationradius, SIM_RADIUS_VALUE, SIM_RADIUS_VALUE)
    end
end

local function SetupNetworkControl()
    -- ── Cleanup do AnchorPart anterior (se existir) ──
    if AnchorPart then
        pcall(function()
            -- MainAttachment é filho do AnchorPart, será destruído junto
            AnchorPart:Destroy()
        end)
        AnchorPart = nil
        MainAttachment = nil
    end

    -- ── Cleanup do Heartbeat anterior ──
    if _networkHeartbeat then
        _networkHeartbeat:Disconnect()
        _networkHeartbeat = nil
    end

    -- ── Criar AnchorPart (peça invisível e ancorada no céu) ──
    AnchorPart = Instance.new("Part")
    AnchorPart.Name = "_NDSAnchor"
    AnchorPart.Size = ANCHOR_SIZE
    AnchorPart.Transparency = 1
    AnchorPart.CanCollide = false
    AnchorPart.CanQuery = false
    AnchorPart.CanTouch = false
    AnchorPart.Anchored = true
    AnchorPart.CFrame = ANCHOR_CFRAME
    AnchorPart.Parent = Workspace
    table.insert(CreatedObjects, AnchorPart)

    -- ── MainAttachment (alvo de todos os AlignPositions) ──
    MainAttachment = Instance.new("Attachment")
    MainAttachment.Name = "MainAttach"
    MainAttachment.Parent = AnchorPart

    -- ── Forçar SimulationRadius imediatamente (primeira vez) ──
    ForceSimulationRadius()

    -- ── Heartbeat Thread dedicada com throttle ──
    -- Em vez de task.spawn + while true + task.wait(0.5),
    -- usamos Heartbeat com acumulador. Vantagens:
    --   1. Respeita o ciclo de vida do jogo (pausa se o jogo pausar)
    --   2. Pode ser desconectado limpo com :Disconnect()
    --   3. Não cria coroutine permanente
    _networkAccumulator = 0
    _networkHeartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
        _networkAccumulator += deltaTime
        if _networkAccumulator < NETWORK_TICK_RATE then return end
        _networkAccumulator = 0
        ForceSimulationRadius()
    end)
end

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  CONTROLE DE PARTES — Setup & Clean                                 │
-- │                                                                     │
-- │  • Usa pool em vez de Instance.new/Destroy                          │
-- │  • Salva e restaura propriedades originais da parte                 │
-- │  • Densidade ultra-baixa para movimento sem resistência             │
-- │  • Remove movers conflitantes de terceiros                          │
-- └──────────────────────────────────────────────────────────────────────┘

--- Verifica se a parte pertence ao Character do LocalPlayer.
--- @param part BasePart
--- @return boolean
local function IsLocalPlayerPart(part: BasePart): boolean
    local character = LocalPlayer.Character
    return character ~= nil and part:IsDescendantOf(character)
end

--- Remove qualquer BodyMover / Constraint de terceiros que possa
--- conflitar com nosso AlignPosition. NÃO remove os nossos (prefixo _NDS).
--- @param part BasePart
local function StripConflictingMovers(part: BasePart)
    for _, child in part:GetChildren() do
        if child.Name == "_NDSAlign" or child.Name == "_NDSAttach" then
            continue -- Nosso: será tratado pela pool
        end

        if child:IsA("AlignPosition")
            or child:IsA("AlignOrientation")
            or child:IsA("BodyPosition")
            or child:IsA("BodyVelocity")
            or child:IsA("BodyGyro")
            or child:IsA("BodyForce")
        then
            pcall(child.Destroy, child) -- Objetos de terceiros: Destroy é seguro
        end
    end
end

function SetupPartControl(part: BasePart?, targetAttachment: Attachment?): (Attachment?, AlignPosition?)
    -- ── Validações rápidas ──
    if not part or not part:IsA("BasePart") then return nil, nil end
    if part.Anchored then return nil, nil end
    if string.find(part.Name, "_NDS", 1, true) then return nil, nil end
    if IsLocalPlayerPart(part) then return nil, nil end

    -- ── Se já tem controle ativo, libera primeiro (evita duplicatas) ──
    local existing = ActiveControls[part]
    if existing then
        ReleaseAlignPosition(existing.align)
        ReleaseAttachment(existing.attach)
        ActiveControls[part] = nil
    end

    -- ── Remove movers conflitantes de terceiros ──
    pcall(StripConflictingMovers, part)

    -- ── Salvar propriedades originais (para restauração no Clean) ──
    if not OriginalProperties[part] then
        OriginalProperties[part] = {
            CanCollide = part.CanCollide,
            CanQuery   = part.CanQuery,
            CanTouch   = part.CanTouch,
            Physics    = part.CustomPhysicalProperties, -- pode ser nil (default)
        }
    end

    -- ── Configurar parte para máxima movimentação ──
    part.CanCollide = false
    part.CanQuery = false
    part.CanTouch = false

    -- Densidade ultra-baixa: parte se comporta como "sem massa"
    -- Facilita o AlignPosition mover instantaneamente
    pcall(function()
        part.CustomPhysicalProperties = LIGHT_PHYSICS
    end)

    -- ── Adquirir objetos da Pool ──
    local attach = AcquireAttachment(part)
    local alignTarget = targetAttachment or MainAttachment
    local align = AcquireAlignPosition(part, attach, alignTarget)

    -- ── Registrar no mapa de controle ativo ──
    ActiveControls[part] = {
        attach = attach,
        align  = align,
    }

    return attach, align
end

function CleanPartControl(part: BasePart?)
    if not part then return end

    -- ── Devolver objetos à pool (O(1) via lookup no mapa) ──
    local control = ActiveControls[part]
    if control then
        ReleaseAlignPosition(control.align)
        ReleaseAttachment(control.attach)
        ActiveControls[part] = nil
    else
        -- Fallback: caso existam objetos órfãos (de sessão anterior, crash, etc.)
        pcall(function()
            local orphanAlign = part:FindFirstChild("_NDSAlign")
            local orphanAttach = part:FindFirstChild("_NDSAttach")
            if orphanAlign then orphanAlign:Destroy() end
            if orphanAttach then orphanAttach:Destroy() end
        end)
    end

    -- ── Restaurar propriedades originais ──
    local original = OriginalProperties[part]
    if original then
        pcall(function()
            part.CanCollide = original.CanCollide
            part.CanQuery   = original.CanQuery
            part.CanTouch   = original.CanTouch
            if original.Physics then
                part.CustomPhysicalProperties = original.Physics
            else
                -- Remover custom properties (volta ao material default)
                part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5)
            end
        end)
        OriginalProperties[part] = nil
    else
        -- Fallback mínimo se não temos backup
        pcall(function()
            part.CanCollide = true
        end)
    end
end

-- ┌──────────────────────────────────────────────────────────────────────┐
-- │  UTILIDADES DE POOL (opcional, para debug/cleanup global)           │
-- └──────────────────────────────────────────────────────────────────────┘

--- Pré-aquece as pools criando N objetos antecipadamente.
--- Chamar uma vez no init para eliminar QUALQUER alocação durante gameplay.
--- @param count number — Quantos objetos pré-criar (recomendado: 20-50)
local function WarmUpPools(count: number)
    count = count or 30
    for _ = 1, count do
        local a = Instance.new("Attachment")
        a.Name = "_NDSAttach"
        table.insert(AttachmentPool, a)

        local al = Instance.new("AlignPosition")
        al.Name = "_NDSAlign"
        al.RigidityEnabled = false
        al.MaxVelocity = ALIGN_MAX_VELOCITY
        al.Responsiveness = ALIGN_RESPONSIVENESS

        local ok = pcall(function()
            al.ForceLimitMode = Enum.ForceLimitMode.PerAxis
            al.MaxAxesForce = HUGE_AXIS_FORCE
        end)
        if not ok then
            pcall(function() al.MaxForce = math.huge end)
        end

        al.Enabled = false
        table.insert(AlignPositionPool, al)
    end
end

--- Libera todos os controles ativos e limpa as pools.
--- Usar ao desligar o script / unload.
local function FlushAll()
    -- Soltar todas as partes controladas
    for part, _ in ActiveControls do
        CleanPartControl(part)
    end

    -- Destruir objetos nas pools (liberação real de memória)
    for _, a in AttachmentPool do
        pcall(a.Destroy, a)
    end
    table.clear(AttachmentPool)

    for _, a in AlignPositionPool do
        pcall(a.Destroy, a)
    end
    table.clear(AlignPositionPool)

    -- Desconectar heartbeat de rede
    if _networkHeartbeat then
        _networkHeartbeat:Disconnect()
        _networkHeartbeat = nil
    end

    table.clear(OriginalProperties)
end

-- FUNÇÕES DE TROLAGEM

--[[ ═══════════════════════════════════════════════════════════════════════════
     NDS TROLL HUB — MOTION ENGINE UNIFICADO v2.0
     ─────────────────────────────────────────────────────────────────────────
     ✦ Heartbeat ÚNICO para todos os modos (Orbit/Spin/Cage/Magnet)
     ✦ Velocity Prediction (intercepta alvos em movimento)
     ✦ Zero sin/cos dentro dos loops (fórmula de adição trigonométrica)
     ✦ Sudden Death automático (intensifica quando próximo)
     ✦ Plug-and-play: cole ABAIXO do Core Refatorado (Passo 1)
     ═══════════════════════════════════════════════════════════════════════════ ]]

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  DEPENDÊNCIAS DO CORE (variáveis que já existem no escopo do Passo 1)  │
-- │                                                                        │
-- │  ActiveControls    : { [BasePart] → { attach, align } }               │
-- │  MainAttachment    : Attachment (âncora padrão no AnchorPart)          │
-- │  AnchorPart        : Part (âncora invisível)                           │
-- │  CreatedObjects    : { Instance }                                      │
-- │  ANCHOR_SIZE       : Vector3                                           │
-- │  ANCHOR_CFRAME     : CFrame                                            │
-- │  LocalPlayer       : Player                                            │
-- │  RunService        : Service                                            │
-- │  Workspace         : Service                                            │
-- │  Players           : Service                                            │
-- └──────────────────────────────────────────────────────────────────────────┘

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  CONFIGURAÇÃO — valores padrão (preserva Config existente)             │
-- └──────────────────────────────────────────────────────────────────────────┘
Config = Config or {}

Config.OrbitRadius            = Config.OrbitRadius            or 15
Config.OrbitSpeed             = Config.OrbitSpeed             or 2
Config.SpinRadius             = Config.SpinRadius             or 8
Config.SpinSpeed              = Config.SpinSpeed              or 8
Config.SpinVerticalAmplitude  = Config.SpinVerticalAmplitude  or 0.5
Config.CageRadius             = Config.CageRadius             or 12
Config.CageSpeed              = Config.CageSpeed              or 1
Config.MagnetOffset           = Config.MagnetOffset           or Vector3.zero
Config.PredictionFactor       = Config.PredictionFactor       or 0.15
Config.SuddenDeathDistance    = Config.SuddenDeathDistance     or 10
Config.SuddenDeathSpeedMult   = Config.SuddenDeathSpeedMult   or 3
Config.SuddenDeathRadiusMult  = Config.SuddenDeathRadiusMult  or 0.5

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  CONSTANTES MATEMÁTICAS PRÉ-ALOCADAS                                   │
-- └──────────────────────────────────────────────────────────────────────────┘
local TWO_PI        = 2 * math.pi
local GOLDEN_ANGLE  = math.pi * (3 - math.sqrt(5))  -- ≈ 2.39996 rad
local VECTOR3_ZERO  = Vector3.zero
local CFRAME_IDENT  = CFrame.identity

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  ESTADO DO MOTION ENGINE                                                │
-- └──────────────────────────────────────────────────────────────────────────┘
local CurrentMode       = "None"  -- "None" | "Orbit" | "Spin" | "Cage" | "Magnet"
local TargetPlayer      = nil     :: Player?
local MotionAnchor      = nil     :: Part?
local MotionConnection  = nil     :: RBXScriptConnection?

-- Relógio acumulado (resetado em troca de modo para transições limpas)
local _motionClock = 0

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  TARGET ATTACHMENT POOL                                                 │
-- │                                                                        │
-- │  Cada part controlada recebe um Attachment INDIVIDUAL no MotionAnchor.  │
-- │  Isso permite posicionar cada peça em um ponto diferente da formação.   │
-- │  Attachments são reciclados via pool (zero Instance.new após warm-up). │
-- └──────────────────────────────────────────────────────────────────────────┘
local TargetAttachments    = {}  -- [BasePart] → Attachment (filho do MotionAnchor)
local TargetAttachmentPool = {}  -- Stack de Attachments reutilizáveis

local function AcquireTargetAttachment(): Attachment
    local attach = table.remove(TargetAttachmentPool)
    if attach then
        attach.Parent = MotionAnchor
        return attach
    end
    -- Pool vazia — criação única
    local new = Instance.new("Attachment")
    new.Name = "_NDSTarget"
    new.Parent = MotionAnchor
    return new
end

local function ReleaseTargetAttachment(attach: Attachment?)
    if not attach then return end
    attach.Position = VECTOR3_ZERO
    attach.Parent = nil
    table.insert(TargetAttachmentPool, attach)
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  BUFFERS DE ITERAÇÃO PRÉ-ALOCADOS                                      │
-- │                                                                        │
-- │  Reutilizados a cada frame. CollectActiveParts preenche sem alocar     │
-- │  tabelas novas. Elimina pressão sobre o GC completamente.              │
-- └──────────────────────────────────────────────────────────────────────────┘
local _partBuf    = {}  -- BasePart[]
local _controlBuf = {}  -- { attach, align }[]
local _targetBuf  = {}  -- Attachment[]
local _prevCount  = 0   -- Contagem do frame anterior (para limpeza)

--- Coleta todas as parts ativas com target attachment válido.
--- Preenche os buffers _partBuf, _controlBuf, _targetBuf.
--- @return number — Quantidade de parts ativas neste frame
local function CollectActiveParts(): number
    local n = 0

    for part, control in ActiveControls do
        local ta = TargetAttachments[part]
        if ta and control.align and control.align.Enabled then
            n += 1
            _partBuf[n]    = part
            _controlBuf[n] = control
            _targetBuf[n]  = ta
        end
    end

    -- Limpar entradas excedentes do frame anterior (evitar referências fantasma)
    for i = n + 1, _prevCount do
        _partBuf[i]    = nil
        _controlBuf[i] = nil
        _targetBuf[i]  = nil
    end
    _prevCount = n

    return n
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  PREDICTION ENGINE                                                      │
-- │                                                                        │
-- │  Calcula posição futura do alvo baseada em velocidade atual.            │
-- │  Faz as peças interceptarem o inimigo em vez de perseguí-lo.            │
-- └──────────────────────────────────────────────────────────────────────────┘

--- @param player Player — Jogador alvo
--- @return Vector3? — Posição prevista, ou nil se inválido
local function GetPredictedTarget(player: Player): Vector3?
    if not player then return nil end
    local character = player.Character
    if not character then return nil end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil end

    -- AssemblyLinearVelocity é a API moderna; Velocity é legado mas ainda funciona
    local velocity = rootPart.AssemblyLinearVelocity
    return rootPart.Position + velocity * Config.PredictionFactor
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  SINCRONIZAÇÃO DE TARGET ATTACHMENTS                                    │
-- │                                                                        │
-- │  Garante que cada part em ActiveControls tenha um target attachment     │
-- │  no MotionAnchor, e que parts removidas devolvam o attachment à pool.   │
-- └──────────────────────────────────────────────────────────────────────────┘

local function SyncTargetAttachments()
    -- 1. Adicionar target attachments para parts NOVAS
    for part, control in ActiveControls do
        if not TargetAttachments[part] then
            local ta = AcquireTargetAttachment()
            TargetAttachments[part] = ta

            -- Redirecionar AlignPosition para o target individual
            if control.align then
                control.align.Attachment1 = ta
            end
        end
    end

    -- 2. Remover target attachments de parts que SAÍRAM
    for part, ta in TargetAttachments do
        if not ActiveControls[part] then
            ReleaseTargetAttachment(ta)
            TargetAttachments[part] = nil
        end
    end
end

--- Desvincula TODOS os target attachments e restaura MainAttachment.
--- Chamado ao desativar um modo ou no shutdown.
local function ReleaseAllTargetAttachments()
    for part, ta in TargetAttachments do
        local control = ActiveControls[part]
        if control and control.align then
            control.align.Attachment1 = MainAttachment
        end
        ReleaseTargetAttachment(ta)
    end
    table.clear(TargetAttachments)
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  CALCULADORES DE FORMAÇÃO (um por modo)                                 │
-- │                                                                        │
-- │  OTIMIZAÇÃO CHAVE: Fórmula de adição trigonométrica                     │
-- │  ────────────────────────────────────────────────────                    │
-- │  Em vez de chamar sin/cos para CADA peça no loop:                       │
-- │    cos(α + step) = cos(α)·cos(step) - sin(α)·sin(step)                │
-- │    sin(α + step) = sin(α)·cos(step) + cos(α)·sin(step)                │
-- │                                                                        │
-- │  Resultado: sin/cos chamados 2-4x NO TOTAL por frame,                  │
-- │  independente do número de peças. Para 50 peças, a deriva              │
-- │  de ponto flutuante é ≈ 50 × 2.2e-16 ≈ 1.1e-14 (desprezível).       │
-- └──────────────────────────────────────────────────────────────────────────┘

--- ORBIT: Anel horizontal girando ao redor do alvo.
--- Todas as peças no mesmo plano Y, distribuídas uniformemente.
local function ComputeOrbit(count: number, time: number, speed: number, radius: number)
    local baseAngle = time * speed
    local angleStep = TWO_PI / count

    -- PRÉ-COMPUTAÇÃO: 4 chamadas sin/cos total (base + step)
    local stepSin = math.sin(angleStep)
    local stepCos = math.cos(angleStep)
    local curSin  = math.sin(baseAngle)
    local curCos  = math.cos(baseAngle)

    for i = 1, count do
        _targetBuf[i].Position = Vector3.new(
            curCos * radius,
            0,
            curSin * radius
        )

        -- Rotação incremental — ZERO sin/cos aqui
        local nextCos = curCos * stepCos - curSin * stepSin
        local nextSin = curSin * stepCos + curCos * stepSin
        curCos = nextCos
        curSin = nextSin
    end
end

--- SPIN: Tornado — rotação rápida com oscilação vertical por peça.
--- Cria efeito de "liquidificador" 3D ao redor do alvo.
local function ComputeSpin(count: number, time: number, speed: number, radius: number)
    local baseAngle = time * speed
    local angleStep = TWO_PI / count
    local vertAmp   = radius * Config.SpinVerticalAmplitude

    -- Trig para rotação XZ
    local stepSin = math.sin(angleStep)
    local stepCos = math.cos(angleStep)
    local curSin  = math.sin(baseAngle)
    local curCos  = math.cos(baseAngle)

    -- Trig para oscilação vertical
    -- Cada peça tem fase = heightBase + i * 1.0 rad (distribuição espiral)
    local heightBase      = time * speed * 0.5
    local heightPhaseStep = 1.0  -- 1 radiano de separação entre peças
    local hStepSin = math.sin(heightPhaseStep)
    local hStepCos = math.cos(heightPhaseStep)
    local hCurSin  = math.sin(heightBase + heightPhaseStep) -- começa em i=1
    local hCurCos  = math.cos(heightBase + heightPhaseStep)

    for i = 1, count do
        _targetBuf[i].Position = Vector3.new(
            curCos * radius,
            hCurSin * vertAmp,   -- Altura oscila por peça
            curSin * radius
        )

        -- Rotação XZ incremental
        local nextCos = curCos * stepCos - curSin * stepSin
        local nextSin = curSin * stepCos + curCos * stepSin
        curCos = nextCos
        curSin = nextSin

        -- Fase vertical incremental
        local nextHCos = hCurCos * hStepCos - hCurSin * hStepSin
        local nextHSin = hCurSin * hStepCos + hCurCos * hStepSin
        hCurCos = nextHCos
        hCurSin = nextHSin
    end
end

--- CAGE: Esfera de Fibonacci — distribui peças uniformemente
--- na superfície de uma esfera que gira lentamente.
local function ComputeCage(count: number, time: number, speed: number, radius: number)
    local timeOffset = time * speed
    local countMax   = math.max(count - 1, 1)
    local countInv   = 1 / countMax  -- Pré-computa divisão (fora do loop)

    -- Rotação theta incremental via golden angle
    local gSin = math.sin(GOLDEN_ANGLE)
    local gCos = math.cos(GOLDEN_ANGLE)

    -- Ângulo inicial (i=1): GOLDEN_ANGLE * 1 + timeOffset
    local theta0  = GOLDEN_ANGLE + timeOffset
    local curTSin = math.sin(theta0)
    local curTCos = math.cos(theta0)

    for i = 1, count do
        -- Distribuição vertical uniforme: y ∈ [1, -1]
        local y = 1 - 2 * (i - 1) * countInv

        -- Raio no plano XZ (projeção na esfera)
        -- sqrt é inevitável mas muito mais barato que sin/cos
        local r = math.sqrt(math.max(0, 1 - y * y))

        _targetBuf[i].Position = Vector3.new(
            r * curTCos * radius,
            y * radius,
            r * curTSin * radius
        )

        -- Rotação theta incremental
        local nextTCos = curTCos * gCos - curTSin * gSin
        local nextTSin = curTSin * gCos + curTCos * gSin
        curTCos = nextTCos
        curTSin = nextTSin
    end
end

--- MAGNET: Todas as peças convergem diretamente para o centro do alvo.
--- Efeito de "esmagamento" — todas as peças colidem no mesmo ponto.
local function ComputeMagnet(count: number)
    local offset = Config.MagnetOffset
    for i = 1, count do
        _targetBuf[i].Position = offset
    end
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  DISPATCH TABLE                                                         │
-- │                                                                        │
-- │  Elimina a cadeia if/elseif no hot path. Lookup O(1) por string.       │
-- │  Cada entrada é uma closure leve que mapeia parâmetros para o          │
-- │  calculador correto, aplicando os multiplicadores de Sudden Death.     │
-- └──────────────────────────────────────────────────────────────────────────┘
local ModeCompute = {
    Orbit = function(n: number, t: number, sm: number, rm: number)
        ComputeOrbit(n, t, Config.OrbitSpeed * sm, Config.OrbitRadius * rm)
    end,

    Spin = function(n: number, t: number, sm: number, rm: number)
        ComputeSpin(n, t, Config.SpinSpeed * sm, Config.SpinRadius * rm)
    end,

    Cage = function(n: number, t: number, sm: number, rm: number)
        ComputeCage(n, t, Config.CageSpeed * sm, Config.CageRadius * rm)
    end,

    Magnet = function(n: number, t: number, sm: number, rm: number)
        ComputeMagnet(n)
    end,
}

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  MOTION LOOP (O ÚNICO HEARTBEAT)                                        │
-- │                                                                        │
-- │  Este é o coração do engine. Roda uma vez por frame de física.          │
-- │  Fluxo:                                                                │
-- │    1. Validar estado                                                    │
-- │    2. Prever posição do alvo                                            │
-- │    3. Sincronizar attachments                                           │
-- │    4. Detectar Sudden Death                                             │
-- │    5. Dispatch para calculador do modo ativo                            │
-- └──────────────────────────────────────────────────────────────────────────┘

local function MotionLoop(deltaTime: number)
    -- ════════ EARLY EXIT ════════
    if CurrentMode == "None" or not TargetPlayer then
        return
    end

    -- ════════ 1. PREVER POSIÇÃO DO ALVO ════════
    local targetPos = GetPredictedTarget(TargetPlayer)
    if not targetPos then
        return
    end

    -- ════════ 2. SINCRONIZAR TARGET ATTACHMENTS ════════
    -- Garante que parts novas recebam attachment e parts removidas devolvam
    SyncTargetAttachments()

    -- ════════ 3. COLETAR PARTS NOS BUFFERS ════════
    local count = CollectActiveParts()
    if count == 0 then
        return
    end

    -- ════════ 4. MOVER MOTION ANCHOR PARA O ALVO ════════
    -- Todos os target attachments são filhos do MotionAnchor.
    -- Mover o MotionAnchor = reposicionar o centro da formação.
    MotionAnchor.CFrame = CFrame.new(targetPos)

    -- ════════ 5. ACUMULAR RELÓGIO ════════
    _motionClock += deltaTime

    -- ════════ 6. SUDDEN DEATH DETECTION ════════
    -- Quando LocalPlayer está a menos de SuddenDeathDistance do alvo:
    --   • Velocidade de rotação é multiplicada (ataque mais letal)
    --   • Raio da formação é reduzido (cerco mais apertado)
    local speedMult  = 1
    local radiusMult = 1

    local localCharacter = LocalPlayer.Character
    if localCharacter then
        local localRoot = localCharacter:FindFirstChild("HumanoidRootPart")
        if localRoot then
            -- (targetPos - localRoot.Position).Magnitude sem criar vetor intermediário
            local dx = targetPos.X - localRoot.Position.X
            local dy = targetPos.Y - localRoot.Position.Y
            local dz = targetPos.Z - localRoot.Position.Z
            local distSq = dx * dx + dy * dy + dz * dz
            local thresholdSq = Config.SuddenDeathDistance * Config.SuddenDeathDistance

            if distSq < thresholdSq then
                speedMult  = Config.SuddenDeathSpeedMult
                radiusMult = Config.SuddenDeathRadiusMult
            end
        end
    end

    -- ════════ 7. DISPATCH PARA O CALCULADOR ════════
    local compute = ModeCompute[CurrentMode]
    if compute then
        compute(count, _motionClock, speedMult, radiusMult)
    end
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  INICIALIZAÇÃO DO MOTION ENGINE                                         │
-- └──────────────────────────────────────────────────────────────────────────┘

--- Inicializa o Motion Engine. Chamar UMA VEZ, após SetupNetworkControl().
--- Cria o MotionAnchor (separado do AnchorPart) e conecta o loop.
local function InitMotionEngine()
    -- Cleanup de inicialização anterior
    if MotionAnchor then
        pcall(function() MotionAnchor:Destroy() end)
        MotionAnchor = nil
    end
    if MotionConnection then
        MotionConnection:Disconnect()
        MotionConnection = nil
    end

    -- ── Criar MotionAnchor ──
    -- Separado do AnchorPart para não interferir no modo "segurar" (hold)
    MotionAnchor = Instance.new("Part")
    MotionAnchor.Name       = "_NDSMotionAnchor"
    MotionAnchor.Size        = ANCHOR_SIZE
    MotionAnchor.Transparency = 1
    MotionAnchor.CanCollide  = false
    MotionAnchor.CanQuery    = false
    MotionAnchor.CanTouch    = false
    MotionAnchor.Anchored    = true
    MotionAnchor.CFrame      = ANCHOR_CFRAME
    MotionAnchor.Parent      = Workspace
    table.insert(CreatedObjects, MotionAnchor)

    -- ── Pré-aquecer pool de target attachments ──
    for _ = 1, 30 do
        local a = Instance.new("Attachment")
        a.Name = "_NDSTarget"
        table.insert(TargetAttachmentPool, a)
    end

    -- ── Conectar o ÚNICO loop ──
    MotionConnection = RunService.Heartbeat:Connect(MotionLoop)
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  SHUTDOWN DO MOTION ENGINE                                              │
-- └──────────────────────────────────────────────────────────────────────────┘

--- Desliga o Motion Engine. Restaura todas as parts para MainAttachment.
--- Destrói pools e desconecta o loop.
local function ShutdownMotionEngine()
    -- Desconectar loop
    if MotionConnection then
        MotionConnection:Disconnect()
        MotionConnection = nil
    end

    -- Restaurar todas as parts para MainAttachment
    ReleaseAllTargetAttachments()

    -- Resetar estado
    CurrentMode  = "None"
    TargetPlayer = nil
    _motionClock = 0

    -- Destruir attachments nas pools (liberação real)
    for _, a in TargetAttachmentPool do
        pcall(a.Destroy, a)
    end
    table.clear(TargetAttachmentPool)

    -- Destruir MotionAnchor
    if MotionAnchor then
        pcall(function() MotionAnchor:Destroy() end)
        MotionAnchor = nil
    end
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  CONTROLE DE MODO — SetMode (núcleo dos Toggles)                       │
-- │                                                                        │
-- │  Lógica de Toggle:                                                      │
-- │    • Mesmo modo ativo → DESATIVA (volta para "None")                   │
-- │    • Modo diferente → TROCA instantaneamente (sem cleanup/rebuild)     │
-- │    • "None" → ATIVA modo com target fornecido                          │
-- └──────────────────────────────────────────────────────────────────────────┘

--- @param mode string — "Orbit" | "Spin" | "Cage" | "Magnet"
--- @param target Player? — Jogador alvo (obrigatório na primeira ativação)
local function SetMode(mode: string, target: Player?)
    -- ── Toggle OFF: mesmo modo → desativa ──
    if CurrentMode == mode then
        ReleaseAllTargetAttachments()

        CurrentMode  = "None"
        TargetPlayer = nil
        _motionClock = 0

        -- Reposicionar MotionAnchor para fora da área de jogo
        if MotionAnchor then
            MotionAnchor.CFrame = ANCHOR_CFRAME
        end
        return
    end

    -- ── Validar target ──
    local resolvedTarget = target or TargetPlayer
    if not resolvedTarget then
        warn("[NDS Motion] SetMode('" .. mode .. "') requer um TargetPlayer.")
        return
    end

    -- ── Ativar / Trocar modo ──
    -- Se já havia um modo ativo, a troca é instantânea:
    --   - Target attachments são MANTIDOS (sem release/re-acquire)
    --   - Apenas o calculador muda via dispatch table
    --   - Relógio reseta para transição limpa
    CurrentMode  = mode
    TargetPlayer = resolvedTarget
    _motionClock = 0   -- Reset para evitar "salto" visual na transição
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  TOGGLE FUNCTIONS (CORRIGIDAS PARA A UI FICAR VERDE)                   │
-- └──────────────────────────────────────────────────────────────────────────┘

function ToggleOrbit(target: Player?)
    SetMode("Orbit", target)
    return CurrentMode == "Orbit", CurrentMode == "Orbit" and "Orbit ON" or "Orbit OFF"
end

function ToggleSpin(target: Player?)
    SetMode("Spin", target)
    return CurrentMode == "Spin", CurrentMode == "Spin" and "Spin ON" or "Spin OFF"
end

function ToggleCage(target: Player?)
    SetMode("Cage", target)
    return CurrentMode == "Cage", CurrentMode == "Cage" and "Cage ON" or "Cage OFF"
end

function ToggleMagnet(target: Player?)
    SetMode("Magnet", target)
    return CurrentMode == "Magnet", CurrentMode == "Magnet" and "Magnet ON" or "Magnet OFF"
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  UTILIDADES PÚBLICAS                                                    │
-- └──────────────────────────────────────────────────────────────────────────┘

--- Define o jogador alvo sem alterar o modo.
--- @param target Player
function SetTarget(target: Player)
    TargetPlayer = target
end

--- Retorna o estado atual do Motion Engine.
--- @return string currentMode, Player? targetPlayer
function GetMotionState(): (string, Player?)
    return CurrentMode, TargetPlayer
end

--- Verifica se algum modo de ataque está ativo.
--- @return boolean
function IsMotionActive(): boolean
    return CurrentMode ~= "None"
end

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │  AUTO-INICIALIZAÇÃO                                                     │
-- └──────────────────────────────────────────────────────────────────────────┘
InitMotionEngine()
--[[ ═══════════════════════════════════════════════════════════════════════
     CORREÇÃO DE DEPENDÊNCIAS & SERVER MAGNET (PASSO 3)
     Cola isso ABAIXO de InitMotionEngine() e ANTES de ToggleHatFling()
     ═══════════════════════════════════════════════════════════════════════ ]]

-- 1. RECUPERANDO VARIÁVEIS E FUNÇÕES PERDIDAS
local Connections = {} -- Tabela essencial para guardar loops antigos

local function GetCharacter()
    return LocalPlayer.Character
end

local function GetHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function GetHumanoid()
    local char = LocalPlayer.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Função para pegar peças disponíveis (usada pelo Launch antigo)
local function GetAvailableParts()
    local parts = {}
    for _, part in pairs(Workspace:GetDescendants()) do
        if part:IsA("BasePart") and not part.Anchored and not part.Parent:FindFirstChild("Humanoid") then
            table.insert(parts, part)
        end
    end
    return parts
end

-- Função Notify (Sistema de Notificação Visual)
local function Notify(title, text, duration)
    task.spawn(function()
        local sg = Instance.new("ScreenGui")
        sg.Parent = game:GetService("CoreGui")
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 200, 0, 50)
        frame.Position = UDim2.new(0.5, -100, 0.8, 0)
        frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        frame.BorderSizePixel = 0
        frame.Parent = sg
        
        local uic = Instance.new("UICorner"); uic.Parent = frame
        
        local tLabel = Instance.new("TextLabel")
        tLabel.Size = UDim2.new(1, 0, 0.5, 0)
        tLabel.BackgroundTransparency = 1
        tLabel.Text = title
        tLabel.TextColor3 = Color3.fromRGB(138, 43, 226) -- Roxo
        tLabel.Font = Enum.Font.GothamBold
        tLabel.Parent = frame
        
        local cLabel = Instance.new("TextLabel")
        cLabel.Size = UDim2.new(1, 0, 0.5, 0)
        cLabel.Position = UDim2.new(0, 0, 0.5, 0)
        cLabel.BackgroundTransparency = 1
        cLabel.Text = text
        cLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        cLabel.Font = Enum.Font.Gotham
        cLabel.Parent = frame
        
        task.wait(duration or 2)
        sg:Destroy()
    end)
end

local function ClearConnections(name)
    if name then
        -- Limpa conexão específica
        for key, conn in pairs(Connections) do
            if string.find(key, name) then
                conn:Disconnect()
                Connections[key] = nil
            end
        end
    end
end

local function DisableAllFunctions()
    -- Desativa Motion Engine
    SetMode("None", nil)
    
    -- Desativa Server Magnet
    State.ServerMagnet = false
    ClearConnections("ServerMagnet")
    
    -- Desativa funções antigas
    State.HatFling = false
    State.BodyFling = false
    State.Launch = false
    State.GodMode = false
    ClearConnections("HatFling")
    ClearConnections("BodyFling")
    ClearConnections("Launch")
    ClearConnections("GodMode")
end

-- Substitua a função ToggleServerMagnet antiga por esta:
function ToggleServerMagnet()
    State.ServerMagnet = not State.ServerMagnet
    
    if State.ServerMagnet then
        -- Desativa o Motion Engine normal para não conflitar
        SetMode("None", nil)
        
        -- AUTO-CAPTURA: Se não tiver peças, rouba do mapa
        local partCount = 0
        for _ in pairs(ActiveControls) do partCount = partCount + 1 end
        
        if partCount == 0 then
            Notify("Server Magnet", "Capturando munição...", 1)
            for _, part in pairs(GetAvailableParts()) do
                -- Pega até 50 peças próximas para não lagar
                if partCount < 50 and (part.Position - GetHRP().Position).Magnitude < 150 then
                    SetupPartControl(part, MainAttachment)
                    partCount = partCount + 1
                end
            end
        end
        
        local radius = 500 -- Alcance de detecção
        
        Connections.ServerMagnetLoop = RunService.Heartbeat:Connect(function()
            local enemies = {}
            
            -- Lista inimigos vivos e próximos
            for _, plr in pairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character then
                    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                    local hum = plr.Character:FindFirstChild("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        -- Verifica distância
                        local myHRP = GetHRP()
                        if myHRP and (hrp.Position - myHRP.Position).Magnitude < radius then
                            table.insert(enemies, hrp)
                        end
                    end
                end
            end
            
            if #enemies == 0 then return end
            
            -- Distribui as peças controladas entre os inimigos
            local enemyIndex = 1
            for part, control in pairs(ActiveControls) do
                if control.align and control.align.Enabled then
                    local targetHRP = enemies[enemyIndex]
                    
                    if targetHRP then
                         -- SUPER FORÇA: Teleporta a peça na cara do inimigo com velocidade
                         -- Isso ignora a física suave para garantir o dano
                         part.AssemblyLinearVelocity = (targetHRP.Position - part.Position).Unit * 800
                         part.CFrame = CFrame.new(targetHRP.Position)
                         part.RotVelocity = Vector3.new(100, 100, 100) -- Rotação para causar mais dano de toque
                    end
                    
                    enemyIndex = enemyIndex + 1
                    if enemyIndex > #enemies then enemyIndex = 1 end
                end
            end
        end)
        
        return true, "Server Magnet: MASSACRE!"
    else
        ClearConnections("ServerMagnet")
        -- Opcional: Soltar as peças quando desligar
        -- for part in pairs(ActiveControls) do CleanPartControl(part) end
        return false, "Server Magnet: OFF"
    end
end

-- 3. FUNÇÃO SKYLIFT (Faltava também)
function ToggleSkyLift()
    State.SkyLift = not State.SkyLift
    if State.SkyLift then
        if not State.SelectedPlayer then State.SkyLift = false return false, "Selecione alguém!" end
        
        Connections.SkyLiftLoop = RunService.Heartbeat:Connect(function()
            if State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.new(0, 5, 0) -- Sobe infinito
                    hrp.AssemblyLinearVelocity = Vector3.new(0, 100, 0)
                end
            end
        end)
        return true, "SkyLift Ativado!"
    else
        ClearConnections("SkyLift")
        return false, "SkyLift OFF"
    end
end

local function ToggleHatFling()
    State.HatFling = not State.HatFling
    
    if State.HatFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.HatFling = false
            return false, "Selecione um player!"
        end
        
        local angle = 0
        
        Connections.HatFlingUpdate = RunService.Heartbeat:Connect(function(dt)
            if State.HatFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myHRP = GetHRP()
                if tHRP and myHRP then
                    angle = angle + dt * 30
                    local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
                    myHRP.CFrame = CFrame.new(tHRP.Position + offset)
                    myHRP.Velocity = Vector3.new(9e5, 9e5, 9e5)
                    myHRP.RotVelocity = Vector3.new(9e5, 9e5, 9e5)
                end
            end
        end)
        
        return true, "Hat Fling ativado!"
    else
        ClearConnections("HatFling")
        local hrp = GetHRP()
        if hrp then
            hrp.Velocity = Vector3.new(0, 0, 0)
            hrp.RotVelocity = Vector3.new(0, 0, 0)
        end
        return false, "Hat Fling desativado"
    end
end

local function ToggleBodyFling()
    State.BodyFling = not State.BodyFling
    
    if State.BodyFling then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.BodyFling = false
            return false, "Selecione um player!"
        end
        
        Connections.BodyFlingUpdate = RunService.Heartbeat:Connect(function()
            if State.BodyFling and State.SelectedPlayer and State.SelectedPlayer.Character then
                local tHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myHRP = GetHRP()
                if tHRP and myHRP then
                    myHRP.CFrame = tHRP.CFrame
                    myHRP.Velocity = Vector3.new(9e7, 9e7, 9e7)
                end
            end
        end)
        
        return true, "Body Fling ativado!"
    else
        ClearConnections("BodyFling")
        local hrp = GetHRP()
        if hrp then
            hrp.Velocity = Vector3.new(0, 0, 0)
        end
        return false, "Body Fling desativado"
    end
end

local function ToggleLaunch()
    State.Launch = not State.Launch
    
    if State.Launch then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.Launch = false
            return false, "Selecione um player!"
        end
        
        for _, part in pairs(GetAvailableParts()) do
            SetupPartControl(part, MainAttachment)
        end
        
        Connections.LaunchUpdate = RunService.Heartbeat:Connect(function()
            if State.Launch and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp and AnchorPart then
                    AnchorPart.CFrame = CFrame.new(hrp.Position + Vector3.new(0, -3, 0))
                end
            end
        end)
        
        return true, "Launch ativado!"
    else
        ClearConnections("Launch")
        for _, part in pairs(Workspace:GetDescendants()) do
            if part:IsA("BasePart") then
                CleanPartControl(part)
            end
        end
        return false, "Launch desativado"
    end
end

local function ToggleSlowPlayer()
    State.SlowPlayer = not State.SlowPlayer
    
    if State.SlowPlayer then
        if not State.SelectedPlayer or not State.SelectedPlayer.Character then
            State.SlowPlayer = false
            return false, "Selecione um player!"
        end
        
        local slowParts = {}
        for i = 1, 6 do
            local part = Instance.new("Part")
            part.Name = "_NDSSlowPart"
            part.Size = Vector3.new(3, 3, 3)
            part.Transparency = 0.9
            part.CanCollide = true
            part.Anchored = false
            part.Massless = false
            part.CustomPhysicalProperties = PhysicalProperties.new(100, 1, 0, 1, 1)
            part.Parent = Workspace
            table.insert(slowParts, part)
            table.insert(CreatedObjects, part)
        end
        
        Connections.SlowUpdate = RunService.Heartbeat:Connect(function()
            if State.SlowPlayer and State.SelectedPlayer and State.SelectedPlayer.Character then
                local hrp = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for i, part in pairs(slowParts) do
                        if part and part.Parent then
                            local angle = (i / #slowParts) * math.pi * 2
                            local offset = Vector3.new(math.cos(angle) * 2, 0, math.sin(angle) * 2)
                            part.CFrame = CFrame.new(hrp.Position + offset)
                        end
                    end
                end
            end
        end)
        
        return true, "Slow ativado!"
    else
        ClearConnections("Slow")
        for _, obj in pairs(CreatedObjects) do
            if obj and obj.Name == "_NDSSlowPart" then
                pcall(function() obj:Destroy() end)
            end
        end
        return false, "Slow desativado"
    end
end

-- UTILIDADES

local function ToggleGodMode()
    State.GodMode = not State.GodMode
    
    if State.GodMode then
        local char = GetCharacter()
        local humanoid = GetHumanoid()
        
        if not char or not humanoid then
            State.GodMode = false
            return false, "Erro!"
        end
        
        local ff = Instance.new("ForceField")
        ff.Name = "_NDSForceField"
        ff.Visible = false
        ff.Parent = char
        table.insert(CreatedObjects, ff)
        
        Connections.GodModeHealth = humanoid.HealthChanged:Connect(function()
            if State.GodMode then
                humanoid.Health = humanoid.MaxHealth
            end
        end)
        
        Connections.GodModeHeartbeat = RunService.Heartbeat:Connect(function()
            if State.GodMode then
                local hum = GetHumanoid()
                if hum then
                    hum.Health = hum.MaxHealth
                end
                local c = GetCharacter()
                if c and not c:FindFirstChild("_NDSForceField") then
                    local newFF = Instance.new("ForceField")
                    newFF.Name = "_NDSForceField"
                    newFF.Visible = false
                    newFF.Parent = c
                end
            end
        end)
        
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        end)
        
        return true, "God Mode ativado!"
    else
        ClearConnections("GodMode")
        local char = GetCharacter()
        if char then
            local ff = char:FindFirstChild("_NDSForceField")
            if ff then ff:Destroy() end
        end
        local humanoid = GetHumanoid()
        if humanoid then
            pcall(function()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
            end)
        end
        return false, "God Mode desativado"
    end
end

-- FLY GUI V3 - Sistema completo
local FlyV3 = {
    GUI = nil,
    Loaded = false,
    Flying = false,
    Speed = 1,
    TpWalking = false,
    Ctrl = {f = 0, b = 0, l = 0, r = 0}
}

local function CreateFlyGuiV3()
    if FlyV3.GUI then FlyV3.GUI:Destroy() end
    FlyV3.Loaded = true
    
    local main = Instance.new("ScreenGui")
    local Frame = Instance.new("Frame")
    local up = Instance.new("TextButton")
    local down = Instance.new("TextButton")
    local onof = Instance.new("TextButton")
    local TextLabel = Instance.new("TextLabel")
    local plus = Instance.new("TextButton")
    local speedLabel = Instance.new("TextLabel")
    local mine = Instance.new("TextButton")
    local closebutton = Instance.new("TextButton")
    local mini = Instance.new("TextButton")
    local mini2 = Instance.new("TextButton")
    
    main.Name = "NDSFlyGuiV3"
    main.Parent = LocalPlayer:WaitForChild("PlayerGui")
    main.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    main.ResetOnSpawn = false
    FlyV3.GUI = main
    
    Frame.Parent = main
    Frame.BackgroundColor3 = Color3.fromRGB(163, 255, 137)
    Frame.BorderColor3 = Color3.fromRGB(103, 221, 213)
    Frame.Position = UDim2.new(0.1, 0, 0.38, 0)
    Frame.Size = UDim2.new(0, 190, 0, 57)
    Frame.Active = true
    Frame.Draggable = true
    
    up.Name = "up"
    up.Parent = Frame
    up.BackgroundColor3 = Color3.fromRGB(79, 255, 152)
    up.Size = UDim2.new(0, 44, 0, 28)
    up.Font = Enum.Font.SourceSans
    up.Text = "UP"
    up.TextColor3 = Color3.fromRGB(0, 0, 0)
    up.TextSize = 14
    
    down.Name = "down"
    down.Parent = Frame
    down.BackgroundColor3 = Color3.fromRGB(215, 255, 121)
    down.Position = UDim2.new(0, 0, 0.491, 0)
    down.Size = UDim2.new(0, 44, 0, 28)
    down.Font = Enum.Font.SourceSans
    down.Text = "DOWN"
    down.TextColor3 = Color3.fromRGB(0, 0, 0)
    down.TextSize = 14
    
    onof.Name = "onof"
    onof.Parent = Frame
    onof.BackgroundColor3 = Color3.fromRGB(255, 249, 74)
    onof.Position = UDim2.new(0.703, 0, 0.491, 0)
    onof.Size = UDim2.new(0, 56, 0, 28)
    onof.Font = Enum.Font.SourceSans
    onof.Text = "fly"
    onof.TextColor3 = Color3.fromRGB(0, 0, 0)
    onof.TextSize = 14
    
    TextLabel.Parent = Frame
    TextLabel.BackgroundColor3 = Color3.fromRGB(242, 60, 255)
    TextLabel.Position = UDim2.new(0.469, 0, 0, 0)
    TextLabel.Size = UDim2.new(0, 100, 0, 28)
    TextLabel.Font = Enum.Font.SourceSans
    TextLabel.Text = "FLY GUI V3"
    TextLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    TextLabel.TextScaled = true
    
    plus.Name = "plus"
    plus.Parent = Frame
    plus.BackgroundColor3 = Color3.fromRGB(133, 145, 255)
    plus.Position = UDim2.new(0.232, 0, 0, 0)
    plus.Size = UDim2.new(0, 45, 0, 28)
    plus.Font = Enum.Font.SourceSans
    plus.Text = "+"
    plus.TextColor3 = Color3.fromRGB(0, 0, 0)
    plus.TextScaled = true
    
    speedLabel.Name = "speed"
    speedLabel.Parent = Frame
    speedLabel.BackgroundColor3 = Color3.fromRGB(255, 85, 0)
    speedLabel.Position = UDim2.new(0.468, 0, 0.491, 0)
    speedLabel.Size = UDim2.new(0, 44, 0, 28)
    speedLabel.Font = Enum.Font.SourceSans
    speedLabel.Text = "1"
    speedLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
    speedLabel.TextScaled = true
    
    mine.Name = "mine"
    mine.Parent = Frame
    mine.BackgroundColor3 = Color3.fromRGB(123, 255, 247)
    mine.Position = UDim2.new(0.232, 0, 0.491, 0)
    mine.Size = UDim2.new(0, 45, 0, 29)
    mine.Font = Enum.Font.SourceSans
    mine.Text = "-"
    mine.TextColor3 = Color3.fromRGB(0, 0, 0)
    mine.TextScaled = true
    
    closebutton.Name = "Close"
    closebutton.Parent = Frame
    closebutton.BackgroundColor3 = Color3.fromRGB(225, 25, 0)
    closebutton.Font = Enum.Font.SourceSans
    closebutton.Size = UDim2.new(0, 45, 0, 28)
    closebutton.Text = "X"
    closebutton.TextSize = 30
    closebutton.Position = UDim2.new(0, 0, -1, 27)
    closebutton.TextColor3 = Color3.fromRGB(255, 255, 255)
    
    mini.Name = "minimize"
    mini.Parent = Frame
    mini.BackgroundColor3 = Color3.fromRGB(192, 150, 230)
    mini.Font = Enum.Font.SourceSans
    mini.Size = UDim2.new(0, 45, 0, 28)
    mini.Text = "-"
    mini.TextSize = 40
    mini.Position = UDim2.new(0, 44, -1, 27)
    mini.TextColor3 = Color3.fromRGB(0, 0, 0)
    
    mini2.Name = "minimize2"
    mini2.Parent = Frame
    mini2.BackgroundColor3 = Color3.fromRGB(192, 150, 230)
    mini2.Font = Enum.Font.SourceSans
    mini2.Size = UDim2.new(0, 45, 0, 28)
    mini2.Text = "+"
    mini2.TextSize = 40
    mini2.Position = UDim2.new(0, 44, -1, 57)
    mini2.Visible = false
    mini2.TextColor3 = Color3.fromRGB(0, 0, 0)
    
    -- Variáveis locais
    local speeds = 1
    local nowe = false
    local tpwalking = false
    local ctrl = {f = 0, b = 0, l = 0, r = 0}
    local lastctrl = {f = 0, b = 0, l = 0, r = 0}
    local bg, bv
    
    -- Função para iniciar TP Walking
    local function startTpWalking()
        for i = 1, speeds do
            task.spawn(function()
                local hb = RunService.Heartbeat
                tpwalking = true
                local chr = GetCharacter()
                local hum = GetHumanoid()
                while tpwalking and chr and hum and hum.Parent do
                    hb:Wait()
                    if hum.MoveDirection.Magnitude > 0 then
                        chr:TranslateBy(hum.MoveDirection)
                    end
                end
            end)
        end
    end
    
    -- Função para habilitar/desabilitar estados do Humanoid
    local function setHumanoidStates(enabled)
        local hum = GetHumanoid()
        if not hum then return end
        hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Flying, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Landed, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Running, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.StrafingNoPhysics, enabled)
        hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, enabled)
        if enabled then
            hum:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
        else
            hum:ChangeState(Enum.HumanoidStateType.Swimming)
        end
    end
    
    -- Botão Fly ON/OFF
    onof.MouseButton1Down:Connect(function()
        local char = GetCharacter()
        local hum = GetHumanoid()
        if not char or not hum then return end
        
        if nowe == true then
            -- Desligar fly
            nowe = false
            FlyV3.Flying = false
            State.Fly = false
            setHumanoidStates(true)
            tpwalking = false
            ctrl = {f = 0, b = 0, l = 0, r = 0}
            lastctrl = {f = 0, b = 0, l = 0, r = 0}
            if bg then bg:Destroy() bg = nil end
            if bv then bv:Destroy() bv = nil end
            hum.PlatformStand = false
            local animate = char:FindFirstChild("Animate")
            if animate then animate.Disabled = false end
            ClearConnections("FlyV3")
            return
        else
            -- Ligar fly
            nowe = true
            FlyV3.Flying = true
            State.Fly = true
            startTpWalking()
            local animate = char:FindFirstChild("Animate")
            if animate then animate.Disabled = true end
            
            -- Parar animações
            for _, v in pairs(hum:GetPlayingAnimationTracks()) do
                v:AdjustSpeed(0)
            end
            setHumanoidStates(false)
        end
        
        -- Detectar tipo de rig (R6 ou R15)
        local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
        if not torso then return end
        
        local maxspeed = 50
        local speed = 0
        
        bg = Instance.new("BodyGyro", torso)
        bg.P = 9e4
        bg.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        bg.CFrame = torso.CFrame
        
        bv = Instance.new("BodyVelocity", torso)
        bv.Velocity = Vector3.new(0, 0.1, 0)
        bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        
        hum.PlatformStand = true
        
        -- Keybinds
        Connections.FlyV3KeyDown = UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then return end
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 1 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = -1 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = -1 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 1 end
        end)
        
        Connections.FlyV3KeyUp = UserInputService.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.W then ctrl.f = 0 end
            if input.KeyCode == Enum.KeyCode.S then ctrl.b = 0 end
            if input.KeyCode == Enum.KeyCode.A then ctrl.l = 0 end
            if input.KeyCode == Enum.KeyCode.D then ctrl.r = 0 end
        end)
        
        -- Loop de voo
        Connections.FlyV3Loop = RunService.RenderStepped:Connect(function()
            if not nowe or not bv or not bg or hum.Health == 0 then return end
            
            if ctrl.l + ctrl.r ~= 0 or ctrl.f + ctrl.b ~= 0 then
                speed = speed + 0.5 + (speed / maxspeed)
                if speed > maxspeed then speed = maxspeed end
            elseif speed ~= 0 then
                speed = speed - 1
                if speed < 0 then speed = 0 end
            end
            
            local cam = workspace.CurrentCamera
            if (ctrl.l + ctrl.r) ~= 0 or (ctrl.f + ctrl.b) ~= 0 then
                bv.Velocity = ((cam.CFrame.LookVector * (ctrl.f + ctrl.b)) + ((cam.CFrame * CFrame.new(ctrl.l + ctrl.r, (ctrl.f + ctrl.b) * 0.2, 0).Position) - cam.CFrame.Position)) * speed
                lastctrl = {f = ctrl.f, b = ctrl.b, l = ctrl.l, r = ctrl.r}
            elseif (ctrl.l + ctrl.r) == 0 and (ctrl.f + ctrl.b) == 0 and speed ~= 0 then
                bv.Velocity = ((cam.CFrame.LookVector * (lastctrl.f + lastctrl.b)) + ((cam.CFrame * CFrame.new(lastctrl.l + lastctrl.r, (lastctrl.f + lastctrl.b) * 0.2, 0).Position) - cam.CFrame.Position)) * speed
            else
                bv.Velocity = Vector3.new(0, 0, 0)
            end
            
            bg.CFrame = cam.CFrame * CFrame.Angles(-math.rad((ctrl.f + ctrl.b) * 50 * speed / maxspeed), 0, 0)
        end)
    end)
    
    -- Botões UP/DOWN
    local upConnection, downConnection
    
    up.MouseButton1Down:Connect(function()
        upConnection = up.MouseEnter:Connect(function()
            while upConnection do
                task.wait()
                local hrp = GetHRP()
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.new(0, 1, 0)
                end
            end
        end)
    end)
    
    up.MouseLeave:Connect(function()
        if upConnection then
            upConnection:Disconnect()
            upConnection = nil
        end
    end)
    
    down.MouseButton1Down:Connect(function()
        downConnection = down.MouseEnter:Connect(function()
            while downConnection do
                task.wait()
                local hrp = GetHRP()
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.new(0, -1, 0)
                end
            end
        end)
    end)
    
    down.MouseLeave:Connect(function()
        if downConnection then
            downConnection:Disconnect()
            downConnection = nil
        end
    end)
    
    -- Botões de velocidade
    plus.MouseButton1Down:Connect(function()
        speeds = speeds + 1
        speedLabel.Text = tostring(speeds)
        if nowe then
            tpwalking = false
            task.wait(0.1)
            startTpWalking()
        end
    end)
    
    mine.MouseButton1Down:Connect(function()
        if speeds == 1 then
            speedLabel.Text = "min!"
            task.wait(1)
            speedLabel.Text = tostring(speeds)
        else
            speeds = speeds - 1
            speedLabel.Text = tostring(speeds)
            if nowe then
                tpwalking = false
                task.wait(0.1)
                startTpWalking()
            end
        end
    end)
    
    -- Botão fechar
    closebutton.MouseButton1Click:Connect(function()
        if nowe then
            nowe = false
            FlyV3.Flying = false
            State.Fly = false
            tpwalking = false
            local hum = GetHumanoid()
            local char = GetCharacter()
            if hum then
                hum.PlatformStand = false
                setHumanoidStates(true)
            end
            if char then
                local animate = char:FindFirstChild("Animate")
                if animate then animate.Disabled = false end
            end
            if bg then bg:Destroy() end
            if bv then bv:Destroy() end
            ClearConnections("FlyV3")
        end
        FlyV3.Loaded = false
        FlyV3.GUI = nil
        main:Destroy()
    end)
    
    -- Botões minimizar
    mini.MouseButton1Click:Connect(function()
        up.Visible = false
        down.Visible = false
        onof.Visible = false
        plus.Visible = false
        speedLabel.Visible = false
        mine.Visible = false
        mini.Visible = false
        mini2.Visible = true
        Frame.BackgroundTransparency = 1
        closebutton.Position = UDim2.new(0, 0, -1, 57)
    end)
    
    mini2.MouseButton1Click:Connect(function()
        up.Visible = true
        down.Visible = true
        onof.Visible = true
        plus.Visible = true
        speedLabel.Visible = true
        mine.Visible = true
        mini.Visible = true
        mini2.Visible = false
        Frame.BackgroundTransparency = 0
        closebutton.Position = UDim2.new(0, 0, -1, 27)
    end)
    
    -- Handler de respawn
    LocalPlayer.CharacterAdded:Connect(function(newChar)
        task.wait(0.7)
        local hum = newChar:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
        local animate = newChar:FindFirstChild("Animate")
        if animate then animate.Disabled = false end
        nowe = false
        FlyV3.Flying = false
        State.Fly = false
        tpwalking = false
    end)
    
    return main
end

local function ToggleFly()
    if not FlyV3.Loaded then
        CreateFlyGuiV3()
        return true, "Fly GUI V3 aberto!"
    else
        if FlyV3.GUI then
            FlyV3.GUI:Destroy()
        end
        FlyV3.Loaded = false
        FlyV3.GUI = nil
        State.Fly = false
        return false, "Fly GUI V3 fechado"
    end
end

-- FUNÇÃO VIEW: Ver player selecionado (atualiza quando morre/respawna)
local function ToggleView()
    State.View = not State.View
    
    if State.View then
        if not State.SelectedPlayer then
            State.View = false
            return false, "Selecione um player!"
        end
        
        local targetPlayer = State.SelectedPlayer
        local originalCameraSubject = Camera.CameraSubject
        
        -- Função para atualizar a câmera para o personagem atual do player
        local function UpdateCameraTarget()
            if not State.View then return end
            if not targetPlayer or not targetPlayer.Parent then
                -- Player saiu do jogo
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConnections("View")
                Notify("View", "Player saiu do jogo", 2)
                return
            end
            
            local targetChar = targetPlayer.Character
            if targetChar then
                local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
                if targetHumanoid then
                    Camera.CameraSubject = targetHumanoid
                end
            end
        end
        
        -- Atualizar câmera inicial
        UpdateCameraTarget()
        
        -- Monitorar quando o player respawna (CharacterAdded)
        Connections.ViewCharacterAdded = targetPlayer.CharacterAdded:Connect(function(newChar)
            task.wait(0.1)  -- Pequeno delay para o Humanoid carregar
            UpdateCameraTarget()
        end)
        
        -- Monitorar se o player sai do jogo
        Connections.ViewPlayerRemoving = Players.PlayerRemoving:Connect(function(player)
            if player == targetPlayer then
                State.View = false
                Camera.CameraSubject = GetHumanoid()
                ClearConnections("View")
                Notify("View", "Player saiu do jogo", 2)
            end
        end)
        
        -- Loop de segurança para garantir que a câmera está sempre no alvo
        task.spawn(function()
            while State.View do
                task.wait(0.5)
                if State.View and targetPlayer and targetPlayer.Parent then
                    UpdateCameraTarget()
                end
            end
        end)
        
        return true, "View ativado em " .. targetPlayer.Name
    else
        ClearConnections("View")
        -- Voltar câmera para o próprio player
        local myHumanoid = GetHumanoid()
        if myHumanoid then
            Camera.CameraSubject = myHumanoid
        end
        return false, "View desativado"
    end
end

local function ToggleNoclip()
    State.Noclip = not State.Noclip
    
    if State.Noclip then
        Connections.NoclipUpdate = RunService.Stepped:Connect(function()
            if State.Noclip then
                local char = GetCharacter()
                if char then
                    for _, part in pairs(char:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end)
        return true, "Noclip ativado!"
    else
        ClearConnections("Noclip")
        return false, "Noclip desativado"
    end
end

local originalSpeed = 16

local function ToggleSpeed()
    State.Speed = not State.Speed
    
    if State.Speed then
        local humanoid = GetHumanoid()
        if humanoid then
            originalSpeed = humanoid.WalkSpeed
            humanoid.WalkSpeed = originalSpeed * Config.SpeedMultiplier
        end
        
        Connections.SpeedUpdate = RunService.Heartbeat:Connect(function()
            if State.Speed then
                local h = GetHumanoid()
                if h and h.WalkSpeed < originalSpeed * Config.SpeedMultiplier then
                    h.WalkSpeed = originalSpeed * Config.SpeedMultiplier
                end
            end
        end)
        
        return true, "Speed ativado!"
    else
        ClearConnections("Speed")
        local humanoid = GetHumanoid()
        if humanoid then
            humanoid.WalkSpeed = originalSpeed
        end
        return false, "Speed desativado"
    end
end

local espObjects = {}

local function ToggleESP()
    State.ESP = not State.ESP
    
    if State.ESP then
        local function createESP(player)
            if player == LocalPlayer then return end
            if not player.Character then return end
            
            local highlight = Instance.new("Highlight")
            highlight.Name = "_NDSESP"
            highlight.FillColor = Color3.fromRGB(255, 0, 0)
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.FillTransparency = 0.5
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = player.Character
            highlight.Parent = player.Character
            espObjects[player] = highlight
        end
        
        for _, player in pairs(Players:GetPlayers()) do
            if player.Character then createESP(player) end
            Connections["ESPChar_" .. player.Name] = player.CharacterAdded:Connect(function()
                if State.ESP then
                    task.wait(0.5)
                    createESP(player)
                end
            end)
        end
        
        Connections.ESPPlayerAdded = Players.PlayerAdded:Connect(function(player)
            player.CharacterAdded:Connect(function()
                if State.ESP then
                    task.wait(0.5)
                    createESP(player)
                end
            end)
        end)
        
        return true, "ESP ativado!"
    else
        for _, highlight in pairs(espObjects) do
            pcall(function() highlight:Destroy() end)
        end
        espObjects = {}
        ClearConnections("ESP")
        return false, "ESP desativado"
    end
end

local function TeleportToPlayer()
    if not State.SelectedPlayer or not State.SelectedPlayer.Character then
        return false, "Selecione um player!"
    end
    
    local hrp = GetHRP()
    local targetHRP = State.SelectedPlayer.Character:FindFirstChild("HumanoidRootPart")
    
    if hrp and targetHRP then
        hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 3)
        return true, "Teleportado!"
    end
    
    return false, "Erro!"
end

local function ToggleTelekinesis()
    State.Telekinesis = not State.Telekinesis
    
    if State.Telekinesis then
        local indicator = Instance.new("Part")
        indicator.Name = "_NDSTelekIndicator"
        indicator.Size = Vector3.new(0.5, 0.5, 0.5)
        indicator.Shape = Enum.PartType.Ball
        indicator.Material = Enum.Material.Neon
        indicator.Color = Color3.fromRGB(138, 43, 226)
        indicator.Transparency = 0.3
        indicator.CanCollide = false
        indicator.Anchored = true
        indicator.Parent = Workspace
        table.insert(CreatedObjects, indicator)
        
        Connections.TelekSelect = UserInputService.InputBegan:Connect(function(input)
            if not State.Telekinesis then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                local ray = Camera:ScreenPointToRay(input.Position.X, input.Position.Y)
                local raycastParams = RaycastParams.new()
                raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                raycastParams.FilterDescendantsInstances = {GetCharacter()}
                
                local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
                if result and result.Instance then
                    local part = result.Instance
                    if part:IsA("BasePart") then
                        TelekinesisTarget = part
                        TelekinesisDistance = (part.Position - Camera.CFrame.Position).Magnitude
                        pcall(function() part.Anchored = false end)
                        SetupPartControl(part, MainAttachment)
                        Notify("Telecinese", "Objeto: " .. part.Name, 2)
                    end
                end
            end
        end)
        
        Connections.TelekMove = RunService.RenderStepped:Connect(function()
            if State.Telekinesis and TelekinesisTarget and TelekinesisTarget.Parent then
                local mousePos = UserInputService:GetMouseLocation()
                local ray = Camera:ScreenPointToRay(mousePos.X, mousePos.Y)
                local targetPos = ray.Origin + ray.Direction * TelekinesisDistance
                if AnchorPart then
                    AnchorPart.CFrame = CFrame.new(targetPos)
                end
                if indicator and indicator.Parent then
                    indicator.CFrame = CFrame.new(targetPos)
                end
            end
        end)
        
        Connections.TelekScroll = UserInputService.InputChanged:Connect(function(input)
            if State.Telekinesis and input.UserInputType == Enum.UserInputType.MouseWheel then
                TelekinesisDistance = math.clamp(TelekinesisDistance + input.Position.Z * 5, 5, 100)
            end
        end)
        
        Connections.TelekRelease = UserInputService.InputBegan:Connect(function(input)
            if State.Telekinesis and input.UserInputType == Enum.UserInputType.MouseButton2 then
                if TelekinesisTarget then
                    CleanPartControl(TelekinesisTarget)
                    TelekinesisTarget = nil
                    Notify("Telecinese", "Solto!", 1)
                end
            end
        end)
        
        return true, "Telecinese ativada!"
    else
        ClearConnections("Telek")
        if TelekinesisTarget then
            CleanPartControl(TelekinesisTarget)
            TelekinesisTarget = nil
        end
        return false, "Telecinese desativada"
    end
end

-- RECONEXÃO AO RESPAWNAR
LocalPlayer.CharacterAdded:Connect(function()
    DisableAllFunctions()
    task.wait(1)
    SetupNetworkControl()
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- INTERFACE DO USUÁRIO (REESCRITA COMPLETAMENTE)
-- ═══════════════════════════════════════════════════════════════════════════

local function CreateUI()
    -- Remover UI existente
    pcall(function() game:GetService("CoreGui"):FindFirstChild("NDSTrollHub"):Destroy() end)
    pcall(function() LocalPlayer.PlayerGui:FindFirstChild("NDSTrollHub"):Destroy() end)
    
    -- ScreenGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "NDSTrollHub"
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn = false
    
    pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
    if not ScreenGui.Parent then
        ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
    
    -- Cores
    local BgColor = Color3.fromRGB(20, 20, 25)
    local SecondaryColor = Color3.fromRGB(30, 30, 38)
    local AccentColor = Color3.fromRGB(138, 43, 226)
    local TextColor = Color3.fromRGB(255, 255, 255)
    local DimColor = Color3.fromRGB(120, 120, 120)
    local SuccessColor = Color3.fromRGB(50, 205, 50)
    
    -- Frame Principal
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 320, 0, 450)
    MainFrame.Position = UDim2.new(0.5, -160, 0.5, -225)
    MainFrame.BackgroundColor3 = BgColor
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Parent = ScreenGui
    
    local MainCorner = Instance.new("UICorner")
    MainCorner.CornerRadius = UDim.new(0, 10)
    MainCorner.Parent = MainFrame
    
    local MainStroke = Instance.new("UIStroke")
    MainStroke.Color = AccentColor
    MainStroke.Thickness = 2
    MainStroke.Parent = MainFrame
    
    -- Header
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 40)
    Header.BackgroundColor3 = SecondaryColor
    Header.BorderSizePixel = 0
    Header.Parent = MainFrame
    
    local HeaderCorner = Instance.new("UICorner")
    HeaderCorner.CornerRadius = UDim.new(0, 10)
    HeaderCorner.Parent = Header
    
    -- Fix para cantos do header
    local HeaderFix = Instance.new("Frame")
    HeaderFix.Size = UDim2.new(1, 0, 0, 10)
    HeaderFix.Position = UDim2.new(0, 0, 1, -10)
    HeaderFix.BackgroundColor3 = SecondaryColor
    HeaderFix.BorderSizePixel = 0
    HeaderFix.Parent = Header
    
    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -100, 1, 0)
    Title.Position = UDim2.new(0, 10, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "NDS Troll Hub v7.5 SERVER MAGNET"
    Title.TextColor3 = TextColor
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 14
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header
    
    -- Botão Minimizar
    local MinimizeBtn = Instance.new("TextButton")
    MinimizeBtn.Name = "MinimizeBtn"
    MinimizeBtn.Size = UDim2.new(0, 30, 0, 30)
    MinimizeBtn.Position = UDim2.new(1, -70, 0, 5)
    MinimizeBtn.BackgroundColor3 = AccentColor
    MinimizeBtn.Text = "-"
    MinimizeBtn.TextColor3 = TextColor
    MinimizeBtn.Font = Enum.Font.GothamBold
    MinimizeBtn.TextSize = 18
    MinimizeBtn.Parent = Header
    
    local MinBtnCorner = Instance.new("UICorner")
    MinBtnCorner.CornerRadius = UDim.new(0, 6)
    MinBtnCorner.Parent = MinimizeBtn
    
    -- Botão Fechar
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.new(0, 30, 0, 30)
    CloseBtn.Position = UDim2.new(1, -35, 0, 5)
    CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    CloseBtn.Text = "X"
    CloseBtn.TextColor3 = TextColor
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.TextSize = 14
    CloseBtn.Parent = Header
    
    local CloseBtnCorner = Instance.new("UICorner")
    CloseBtnCorner.CornerRadius = UDim.new(0, 6)
    CloseBtnCorner.Parent = CloseBtn
    
    -- Container de Conteúdo
    local ContentFrame = Instance.new("Frame")
    ContentFrame.Name = "ContentFrame"
    ContentFrame.Size = UDim2.new(1, -20, 1, -50)
    ContentFrame.Position = UDim2.new(0, 10, 0, 45)
    ContentFrame.BackgroundTransparency = 1
    ContentFrame.Parent = MainFrame
    
    -- Seção de Seleção de Player
    local PlayerSection = Instance.new("Frame")
    PlayerSection.Name = "PlayerSection"
    PlayerSection.Size = UDim2.new(1, 0, 0, 100)
    PlayerSection.BackgroundColor3 = SecondaryColor
    PlayerSection.BorderSizePixel = 0
    PlayerSection.Parent = ContentFrame
    
    local PlayerSectionCorner = Instance.new("UICorner")
    PlayerSectionCorner.CornerRadius = UDim.new(0, 8)
    PlayerSectionCorner.Parent = PlayerSection
    
    local PlayerLabel = Instance.new("TextLabel")
    PlayerLabel.Size = UDim2.new(1, -10, 0, 20)
    PlayerLabel.Position = UDim2.new(0, 5, 0, 5)
    PlayerLabel.BackgroundTransparency = 1
    PlayerLabel.Text = "Selecionar Player:"
    PlayerLabel.TextColor3 = DimColor
    PlayerLabel.Font = Enum.Font.Gotham
    PlayerLabel.TextSize = 11
    PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
    PlayerLabel.Parent = PlayerSection
    
    -- ScrollingFrame para lista de players
    local PlayerList = Instance.new("ScrollingFrame")
    PlayerList.Name = "PlayerList"
    PlayerList.Size = UDim2.new(1, -10, 0, 50)
    PlayerList.Position = UDim2.new(0, 5, 0, 25)
    PlayerList.BackgroundColor3 = BgColor
    PlayerList.BorderSizePixel = 0
    PlayerList.ScrollBarThickness = 4
    PlayerList.ScrollBarImageColor3 = AccentColor
    PlayerList.CanvasSize = UDim2.new(0, 0, 0, 0)
    PlayerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    PlayerList.Parent = PlayerSection
    
    local PlayerListCorner = Instance.new("UICorner")
    PlayerListCorner.CornerRadius = UDim.new(0, 6)
    PlayerListCorner.Parent = PlayerList
    
    local PlayerListLayout = Instance.new("UIListLayout")
    PlayerListLayout.SortOrder = Enum.SortOrder.Name
    PlayerListLayout.Padding = UDim.new(0, 3)
    PlayerListLayout.Parent = PlayerList
    
    local PlayerListPadding = Instance.new("UIPadding")
    PlayerListPadding.PaddingTop = UDim.new(0, 3)
    PlayerListPadding.PaddingBottom = UDim.new(0, 3)
    PlayerListPadding.PaddingLeft = UDim.new(0, 3)
    PlayerListPadding.PaddingRight = UDim.new(0, 3)
    PlayerListPadding.Parent = PlayerList
    
    -- Status do player selecionado
    local SelectedStatus = Instance.new("TextLabel")
    SelectedStatus.Name = "SelectedStatus"
    SelectedStatus.Size = UDim2.new(1, -10, 0, 18)
    SelectedStatus.Position = UDim2.new(0, 5, 1, -22)
    SelectedStatus.BackgroundTransparency = 1
    SelectedStatus.Text = "Nenhum selecionado"
    SelectedStatus.TextColor3 = DimColor
    SelectedStatus.Font = Enum.Font.Gotham
    SelectedStatus.TextSize = 10
    SelectedStatus.TextXAlignment = Enum.TextXAlignment.Left
    SelectedStatus.Parent = PlayerSection
    
    -- Função para atualizar lista de players
    local function UpdatePlayerList()
        for _, child in pairs(PlayerList:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        
        for _, player in pairs(Players:GetPlayers()) do
            local btn = Instance.new("TextButton")
            btn.Name = player.Name
            btn.Size = UDim2.new(1, -6, 0, 22)
            btn.BackgroundColor3 = State.SelectedPlayer == player and AccentColor or SecondaryColor
            btn.Text = player.DisplayName
            btn.TextColor3 = TextColor
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 10
            btn.TextTruncate = Enum.TextTruncate.AtEnd
            btn.Parent = PlayerList
            
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 4)
            btnCorner.Parent = btn
            
-- CÓDIGO NOVO (NA UI)
btn.MouseButton1Click:Connect(function()
    State.SelectedPlayer = player
    SetTarget(player)  -- <--- ADICIONE ESTA LINHA!!!
    SelectedStatus.Text = "Selecionado: " .. player.DisplayName
    SelectedStatus.TextColor3 = SuccessColor
    UpdatePlayerList()
    Notify("Player", player.DisplayName, 1)
end)
        end
    end
    
    UpdatePlayerList()
    Players.PlayerAdded:Connect(UpdatePlayerList)
    Players.PlayerRemoving:Connect(UpdatePlayerList)
    
    -- ScrollFrame para botões
    local ButtonsScroll = Instance.new("ScrollingFrame")
    ButtonsScroll.Name = "ButtonsScroll"
    ButtonsScroll.Size = UDim2.new(1, 0, 1, -110)
    ButtonsScroll.Position = UDim2.new(0, 0, 0, 105)
    ButtonsScroll.BackgroundTransparency = 1
    ButtonsScroll.BorderSizePixel = 0
    ButtonsScroll.ScrollBarThickness = 4
    ButtonsScroll.ScrollBarImageColor3 = AccentColor
    ButtonsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    ButtonsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ButtonsScroll.Parent = ContentFrame
    
    local ButtonsLayout = Instance.new("UIListLayout")
    ButtonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    ButtonsLayout.Padding = UDim.new(0, 5)
    ButtonsLayout.Parent = ButtonsScroll
    
    -- Tabela para armazenar indicadores de status
    local StatusIndicators = {}
    
    -- Função para criar categoria
    local function CreateCategory(name, order)
        local cat = Instance.new("Frame")
        cat.Size = UDim2.new(1, 0, 0, 18)
        cat.BackgroundTransparency = 1
        cat.LayoutOrder = order
        cat.Parent = ButtonsScroll
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "-- " .. name .. " --"
        label.TextColor3 = AccentColor
        label.Font = Enum.Font.GothamBold
        label.TextSize = 10
        label.Parent = cat
    end
    
    -- Função para criar botão toggle
    local function CreateToggle(name, callback, order, stateKey)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = SecondaryColor
        btn.Text = ""
        btn.LayoutOrder = order
        btn.Parent = ButtonsScroll
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -40, 1, 0)
        label.Position = UDim2.new(0, 10, 0, 0)
        label.BackgroundTransparency = 1
        label.Text = name
        label.TextColor3 = TextColor
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = btn
        
        local status = Instance.new("Frame")
        status.Size = UDim2.new(0, 10, 0, 10)
        status.Position = UDim2.new(1, -22, 0.5, -5)
        status.BackgroundColor3 = DimColor
        status.Parent = btn
        
        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(1, 0)
        statusCorner.Parent = status
        
        if stateKey then
            StatusIndicators[stateKey] = status
        end
        
        btn.MouseButton1Click:Connect(function()
            local success, msg = callback()
            status.BackgroundColor3 = success and SuccessColor or DimColor
            if msg then Notify(name, msg, 2) end
        end)
        
        return btn
    end
    
    -- Função para criar botão simples
    local function CreateButton(name, callback, order)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 32)
        btn.BackgroundColor3 = SecondaryColor
        btn.Text = name
        btn.TextColor3 = TextColor
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.LayoutOrder = order
        btn.Parent = ButtonsScroll
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            local success, msg = callback()
            if msg then Notify(name, msg, 2) end
        end)
        
        return btn
    end
    
    -- Criar botões - LISTA COMPLETA (Substitua a seção antiga por esta)
    CreateCategory("ATAQUES FÍSICOS", 1)
    CreateToggle("Ima de Objetos", ToggleMagnet, 2, "Magnet")
    CreateToggle("Orbit Attack", ToggleOrbit, 3, "Orbit")
    CreateToggle("Spin Tornado", ToggleSpin, 4, "Spin") -- Faltava
    CreateToggle("Cage Sphere", ToggleCage, 5, "Cage") -- Faltava
    CreateToggle("Server Magnet", ToggleServerMagnet, 6, "ServerMagnet")
    
    CreateCategory("TROLL PLAYER", 10)
    CreateToggle("Sky Lift", ToggleSkyLift, 11, "SkyLift")
    CreateToggle("Hat Fling", ToggleHatFling, 12, "HatFling") -- Faltava
    CreateToggle("Body Fling", ToggleBodyFling, 13, "BodyFling") -- Faltava
    CreateToggle("Launch", ToggleLaunch, 14, "Launch") -- Faltava
    CreateToggle("Telecinese (PC/Touch)", ToggleTelekinesis, 15, "Telekinesis") -- Faltava
    
    CreateCategory("PERSONAGEM", 20)
    CreateToggle("God Mode", ToggleGodMode, 21, "GodMode") -- Faltava
    CreateToggle("Speed 3x", ToggleSpeed, 22, "Speed")
    CreateToggle("Noclip", ToggleNoclip, 23, "Noclip") -- Faltava
    CreateButton("Fly GUI V3", ToggleFly, 24)
    
    CreateCategory("VISUAL", 30)
    CreateToggle("View Player", ToggleView, 31, "View")
    CreateToggle("ESP", ToggleESP, 32, "ESP") -- Faltava

    -- Botão flutuante para reabrir
    local FloatBtn = Instance.new("TextButton")
    FloatBtn.Name = "FloatBtn"
    FloatBtn.Size = UDim2.new(0, 50, 0, 50)
    FloatBtn.Position = UDim2.new(0, 10, 0.5, -25)
    FloatBtn.BackgroundColor3 = AccentColor
    FloatBtn.Text = "NDS"
    FloatBtn.TextColor3 = TextColor
    FloatBtn.Font = Enum.Font.GothamBold
    FloatBtn.TextSize = 12
    FloatBtn.Visible = false
    FloatBtn.Parent = ScreenGui
    
    local FloatBtnCorner = Instance.new("UICorner")
    FloatBtnCorner.CornerRadius = UDim.new(1, 0)
    FloatBtnCorner.Parent = FloatBtn
    
    -- Minimizar
    local minimized = false
    MinimizeBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        if minimized then
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {Size = UDim2.new(0, 320, 0, 40)}):Play()
            MinimizeBtn.Text = "+"
            ContentFrame.Visible = false
        else
            TweenService:Create(MainFrame, TweenInfo.new(0.2), {Size = UDim2.new(0, 320, 0, 450)}):Play()
            MinimizeBtn.Text = "-"
            task.wait(0.2)
            ContentFrame.Visible = true
        end
    end)
    
    -- Fechar/Esconder
    CloseBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = false
        FloatBtn.Visible = true
    end)
    
    FloatBtn.MouseButton1Click:Connect(function()
        MainFrame.Visible = true
        FloatBtn.Visible = false
    end)
    
    -- Arrastar
    local dragging = false
    local dragStart, startPos
    
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    
    Header.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    
    -- Arrastar botão flutuante
    local draggingFloat = false
    local floatDragStart, floatStartPos
    
    FloatBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingFloat = true
            floatDragStart = input.Position
            floatStartPos = FloatBtn.Position
        end
    end)
    
    FloatBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingFloat = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if draggingFloat and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - floatDragStart
            FloatBtn.Position = UDim2.new(floatStartPos.X.Scale, floatStartPos.X.Offset + delta.X, floatStartPos.Y.Scale, floatStartPos.Y.Offset + delta.Y)
        end
    end)
    
    return ScreenGui
end

-- INICIALIZAÇÃO
print("Iniciando Core Refatorado...")

-- Pré-aquece 50 peças na memória para evitar lag no primeiro uso
WarmUpPools(50) 

-- Inicia o controle de rede
SetupNetworkControl()

local UI = CreateUI()

task.spawn(function()
    task.wait(1)
    Notify("NDS Troll Hub v8.0", "Core: OTIMIZADO & FORTE", 3)
end)

-- Garante limpeza se o script for fechado/reiniciado
game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child.Name == "NDSTrollHub" then
        FlushAll()
    end
end)

print("NDS Troll Hub v8.0 - Pronto para destruir!")