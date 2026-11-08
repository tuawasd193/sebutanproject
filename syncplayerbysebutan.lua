local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local lp = Players.LocalPlayer

local TITLE = "SYNC PLAYER BY SEBUTAN"
local SMOOTH = 30
local S = {Target = nil, Side = "Behind", Dist = 4, On = false}
local offsets = {
    Right  = function(d) return CFrame.new(d, 0, 0) end,
    Left   = function(d) return CFrame.new(-d, 0, 0) end,
    Behind = function(d) return CFrame.new(0, 0, d) end,
}

local onState = function() end
local conn
local mirrored = {}
local saved = {}
local myParts, lastT, lastM, lastA
local heading, myLook, curPos

local function findPlayer(name)
    name = name:lower()
    if name == "" then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and (p.Name:lower():find(name, 1, true) or p.DisplayName:lower():find(name, 1, true)) then
            return p
        end
    end
end

local function getParts(char)
    if not char then return end
    return char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function getAnimator(hum)
    local a = hum:FindFirstChildOfClass("Animator")
    if not a then
        a = Instance.new("Animator")
        a.Parent = hum
    end
    return a
end

local function flat(v)
    local f = Vector3.new(v.X, 0, v.Z)
    if f.Magnitude < 0.01 then return nil end
    return f.Unit
end

local function syncAnims(tHum, mHum)
    local tA, mA = getAnimator(tHum), getAnimator(mHum)
    local keep = {}

    for _, t in ipairs(tA:GetPlayingAnimationTracks()) do
        local anim = t.Animation
        local id = anim and anim.AnimationId
        if id and id ~= "" then
            local m = mirrored[id]
            if not m then
                local a = Instance.new("Animation")
                a.AnimationId = id
                local ok, res = pcall(function() return mA:LoadAnimation(a) end)
                if ok and res then
                    m = res
                    mirrored[id] = m
                end
            end
            if m then
                keep[m] = true
                local w = math.max(t.WeightCurrent, 0.01)
                m.Priority = t.Priority
                m.Looped = t.Looped
                if not m.IsPlaying then
                    m:Play(0, w, t.Speed)
                    m.TimePosition = t.TimePosition
                end
                m:AdjustWeight(w, 0)
                m:AdjustSpeed(t.Speed)
                if math.abs(m.TimePosition - t.TimePosition) > 0.15 then
                    m.TimePosition = t.TimePosition
                end
            end
        end
    end

    for id, m in pairs(mirrored) do
        if not keep[m] and m.IsPlaying then m:Stop(0) end
    end
    for _, track in ipairs(mA:GetPlayingAnimationTracks()) do
        if not keep[track] then track:Stop(0) end
    end
end

local function cacheParts(char)
    myParts = {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then table.insert(myParts, p) end
    end
end

local function stop()
    S.On = false
    if conn then conn:Disconnect() conn = nil end
    for _, m in pairs(mirrored) do pcall(function() m:Stop(0) end) end
    mirrored = {}
    lastT, lastM, lastA, heading, myLook, curPos = nil, nil, nil, nil, nil, nil
    local c = lp.Character
    if c then
        local a = c:FindFirstChild("Animate")
        if a then a.Disabled = false end
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then
            h.PlatformStand = saved.ps or false
            h.AutoRotate = true
        end
        local r = c:FindFirstChild("HumanoidRootPart")
        if r then r.AssemblyLinearVelocity = Vector3.zero end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and (p.Name == "HumanoidRootPart" or p.Name == "Head" or p.Name == "Torso" or p.Name == "UpperTorso" or p.Name == "LowerTorso") then
                p.CanCollide = true
            end
        end
    end
    onState()
end

local function start()
    stop()
    if not S.Target then return end
    S.On = true

    local c = lp.Character
    local h0 = c and c:FindFirstChildOfClass("Humanoid")
    if h0 then
        saved.ps = h0.PlatformStand
        h0.PlatformStand = true
        h0.AutoRotate = false
    end
    local an0 = c and c:FindFirstChild("Animate")
    if an0 then an0.Disabled = true end

    conn = RunService.RenderStepped:Connect(function(dt)
        if not S.Target or not S.Target.Parent then stop() return end
        dt = math.min(dt, 0.1)
        local tChar, mChar = S.Target.Character, lp.Character
        local tHum, tRoot = getParts(tChar)
        local mHum, mRoot = getParts(mChar)
        if not (tHum and tRoot and mHum and mRoot) then return end

        if mHum.Health <= 0 then return end

        local mAnimator = mHum:FindFirstChildOfClass("Animator")
        if not mAnimator then return end
        if mAnimator ~= lastA then
            lastA = mAnimator
            for _, m in pairs(mirrored) do pcall(function() m:Stop(0) end) end
            mirrored = {}
        end

        local an = mChar:FindFirstChild("Animate")
        if an and not an.Disabled then an.Disabled = true end

        if tChar ~= lastT or mChar ~= lastM then
            lastT, lastM = tChar, mChar
            for _, m in pairs(mirrored) do pcall(function() m:Stop(0) end) end
            mirrored = {}
            mHum.PlatformStand = true
            mHum.AutoRotate = false
            cacheParts(mChar)
            heading = flat(tRoot.CFrame.LookVector) or Vector3.new(0, 0, -1)
            myLook = heading
            curPos = nil
        end

        local desired = flat(tRoot.CFrame.LookVector) or heading
        heading = heading:Lerp(desired, 1 - math.exp(-8 * dt))
        heading = flat(heading) or desired

        local tPos = tRoot.Position
        local basis = CFrame.lookAt(tPos, tPos + heading)
        local tVel = tRoot.AssemblyLinearVelocity
        local goal = (basis * offsets[S.Side](S.Dist)).Position
        goal = goal + Vector3.new(tVel.X, 0, tVel.Z) * (0.5 / SMOOTH)

        if not curPos then curPos = mRoot.Position end

        local newPos
        if (curPos - goal).Magnitude > 50 then
            newPos = goal
        else
            newPos = curPos:Lerp(goal, 1 - math.exp(-SMOOTH * dt))
        end

        newPos = Vector3.new(newPos.X, goal.Y, newPos.Z)

        myLook = myLook:Lerp(heading, 1 - math.exp(-10 * dt))
        myLook = flat(myLook) or heading

        local vel = (newPos - curPos) / math.max(dt, 1e-3)
        curPos = newPos

        mRoot.CFrame = CFrame.lookAt(newPos, newPos + myLook)
        mRoot.AssemblyLinearVelocity = Vector3.new(vel.X, tVel.Y, vel.Z)
        mRoot.AssemblyAngularVelocity = Vector3.zero

        if myParts then
            for _, p in ipairs(myParts) do
                if p.Parent and p.CanCollide then p.CanCollide = false end
            end
        end

        syncAnims(tHum, mHum)
    end)
    onState()
end

lp.CharacterAdded:Connect(function(char)
    mirrored = {}
    lastT, lastM, lastA = nil, nil, nil
    if not S.On then return end
    if conn then conn:Disconnect() conn = nil end
    local hum = char:WaitForChild("Humanoid", 10)
    char:WaitForChild("HumanoidRootPart", 10)
    if hum then hum:WaitForChild("Animator", 5) end
    task.wait(1)
    if S.On and S.Target then start() end
end)

-- =====================================================
-- GUI : liquid glass
-- =====================================================
local parentGui
pcall(function() parentGui = (gethui and gethui()) or game:GetService("CoreGui") end)
if not parentGui then parentGui = lp:WaitForChild("PlayerGui") end
local old = parentGui:FindFirstChild("FollowGui")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "FollowGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = parentGui

local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WHITE = Color3.new(1, 1, 1)
local GREEN, RED = Color3.fromRGB(52, 199, 89), Color3.fromRGB(255, 69, 58)
local GREY = Color3.fromRGB(140, 145, 160)
local SUB = Color3.fromRGB(190, 196, 212)
local quick = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local smooth = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function corner(o, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = r or UDim.new(0, 12)
    c.Parent = o
    return c
end

local function glassEdge(o, thickness, alpha)
    local s = Instance.new("UIStroke")
    s.Color = WHITE
    s.Thickness = thickness or 1.2
    s.Transparency = alpha or 0.35
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = o
    local g = Instance.new("UIGradient")
    g.Rotation = 45
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.45, 0.75),
        NumberSequenceKeypoint.new(0.7, 0.9),
        NumberSequenceKeypoint.new(1, 0.35),
    })
    g.Parent = s
    return s
end

local function glassBody(o, base)
    o.BackgroundColor3 = WHITE
    o.BackgroundTransparency = base or 0.3
    local g = Instance.new("UIGradient")
    g.Rotation = 60
    g.Color = ColorSequence.new(Color3.fromRGB(88, 100, 140), Color3.fromRGB(18, 20, 30))
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.12),
        NumberSequenceKeypoint.new(1, 0.38),
    })
    g.Parent = o
end

local function label(parent, props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Font = FONT
    l.TextColor3 = WHITE
    l.TextSize = 13
    for k, v in pairs(props) do l[k] = v end
    l.Parent = parent
    return l
end

local function softBox(parent, props)
    local f = Instance.new("Frame")
    f.BackgroundColor3 = WHITE
    f.BackgroundTransparency = 0.88
    f.BorderSizePixel = 0
    for k, v in pairs(props) do f[k] = v end
    f.Parent = parent
    corner(f, UDim.new(0, 12))
    local s = Instance.new("UIStroke")
    s.Color = WHITE
    s.Transparency = 0.85
    s.Thickness = 1
    s.Parent = f
    return f
end

local function btn(parent, props)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.BackgroundTransparency = 1
    b.Font = FONT_B
    b.TextColor3 = WHITE
    b.TextSize = 14
    b.Text = ""
    for k, v in pairs(props) do b[k] = v end
    b.Parent = parent
    return b
end

local function pressFx(b, target)
    local base = target.BackgroundTransparency
    b.MouseButton1Down:Connect(function()
        TweenService:Create(target, quick, {BackgroundTransparency = math.max(base - 0.12, 0)}):Play()
    end)
    local function up() TweenService:Create(target, quick, {BackgroundTransparency = base}):Play() end
    b.MouseButton1Up:Connect(up)
    b.MouseLeave:Connect(up)
end

local function makeDraggable(handle, target, onTap)
    local dragging, moved = false, false
    local activeInput, startIn, startPos

    handle.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1
            and i.UserInputType ~= Enum.UserInputType.Touch then return end
        local p = i.Position
        local ap, as = handle.AbsolutePosition, handle.AbsoluteSize
        if p.X < ap.X or p.X > ap.X + as.X or p.Y < ap.Y or p.Y > ap.Y + as.Y then return end
        dragging, moved = true, false
        activeInput = i
        startIn = Vector2.new(p.X, p.Y)
        startPos = target.Position
    end)

    UIS.InputChanged:Connect(function(i)
        if not dragging then return end
        if i.UserInputType == Enum.UserInputType.MouseMovement or i == activeInput then
            local d = Vector2.new(i.Position.X, i.Position.Y) - startIn
            if d.Magnitude > 8 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)

    UIS.InputEnded:Connect(function(i)
        if dragging and i == activeInput then
            dragging = false
            activeInput = nil
            if not moved and onTap then onTap() end
        end
    end)
end

-- ============ panel utama ============
local PAD = 16
local panel = Instance.new("CanvasGroup")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(300, 362)
panel.Position = UDim2.fromOffset(20, 90)
panel.BorderSizePixel = 0
panel.GroupTransparency = 1
panel.Visible = false
panel.Parent = gui
glassBody(panel, 0.3)
corner(panel, UDim.new(0, 26))
glassEdge(panel, 1.4, 0.3)
local pScale = Instance.new("UIScale", panel)
pScale.Scale = 0.88

-- header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 54)
header.BackgroundTransparency = 1
header.Parent = panel

local dot = Instance.new("Frame")
dot.Size = UDim2.fromOffset(9, 9)
dot.Position = UDim2.fromOffset(PAD, 23)
dot.BackgroundColor3 = GREY
dot.BorderSizePixel = 0
dot.Parent = header
corner(dot, UDim.new(1, 0))

label(header, {Text = TITLE, Font = FONT_B, TextSize = 12, Size = UDim2.new(1, -140, 0, 20),
    Position = UDim2.fromOffset(PAD + 18, 9), TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd})
label(header, {Text = "Ikuti gerakan & animasi player", TextSize = 10, TextColor3 = SUB,
    Size = UDim2.new(1, -140, 0, 14), Position = UDim2.fromOffset(PAD + 18, 28),
    TextXAlignment = Enum.TextXAlignment.Left})

local function headBtn(txt, xOff)
    local bg = softBox(header, {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, xOff, 0, 13)})
    corner(bg, UDim.new(1, 0))
    local b = btn(bg, {Size = UDim2.fromScale(1, 1), Text = txt, TextSize = 15})
    pressFx(b, bg)
    return b
end
local hideBtn = headBtn("–", -78)
local closeBtn = headBtn("✕", -44)
closeBtn.TextSize = 12

local function caption(text, y)
    label(panel, {Text = text, Font = FONT_B, TextSize = 10, TextColor3 = SUB,
        Size = UDim2.new(1, -PAD * 2, 0, 14), Position = UDim2.fromOffset(PAD, y),
        TextXAlignment = Enum.TextXAlignment.Left})
end

-- TARGET
caption("TARGET", 60)
local boxBg = softBox(panel, {Size = UDim2.new(1, -PAD * 2, 0, 34), Position = UDim2.fromOffset(PAD, 76)})
local box = Instance.new("TextBox")
box.Size = UDim2.new(1, -20, 1, 0)
box.Position = UDim2.fromOffset(10, 0)
box.BackgroundTransparency = 1
box.Font = FONT
box.TextSize = 13
box.TextColor3 = WHITE
box.PlaceholderText = "Nama / display name player"
box.PlaceholderColor3 = Color3.fromRGB(170, 176, 195)
box.Text = ""
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.Parent = boxBg

local pickBg = softBox(panel, {Size = UDim2.new(1, -PAD * 2, 0, 30), Position = UDim2.fromOffset(PAD, 116)})
local pick = btn(pickBg, {Size = UDim2.fromScale(1, 1), Text = "Pilih player berikutnya  ›", Font = FONT, TextSize = 12})
pressFx(pick, pickBg)

-- ARAH
caption("ARAH", 158)
local segBg = softBox(panel, {Size = UDim2.new(1, -PAD * 2, 0, 36), Position = UDim2.fromOffset(PAD, 174)})
local selector = Instance.new("Frame")
selector.Size = UDim2.new(1 / 3, -4, 1, -6)
selector.BackgroundColor3 = WHITE
selector.BackgroundTransparency = 0.7
selector.BorderSizePixel = 0
selector.Parent = segBg
corner(selector, UDim.new(0, 10))
glassEdge(selector, 1, 0.4)

local sides = {{"Left", "Kiri"}, {"Right", "Kanan"}, {"Behind", "Belakang"}}
local function sideIndex()
    for i, s in ipairs(sides) do if s[1] == S.Side then return i end end
    return 3
end
local segLabels = {}
for i, s in ipairs(sides) do
    local b = btn(segBg, {Size = UDim2.new(1 / 3, 0, 1, 0), Position = UDim2.new((i - 1) / 3, 0, 0, 0),
        Text = s[2], Font = FONT_B, TextSize = 12, ZIndex = 3})
    segLabels[i] = b
    b.MouseButton1Click:Connect(function() S.Side = s[1] onState() end)
end
selector.Position = UDim2.new((sideIndex() - 1) / 3, 2, 0, 3)

-- JARAK
caption("JARAK", 220)
local stepBg = softBox(panel, {Size = UDim2.new(1, -PAD * 2, 0, 36), Position = UDim2.fromOffset(PAD, 236)})
local minus = btn(stepBg, {Size = UDim2.fromOffset(44, 36), Text = "−", TextSize = 20})
local plus = btn(stepBg, {Size = UDim2.fromOffset(44, 36), Position = UDim2.new(1, -44, 0, 0), Text = "+", TextSize = 20})
local distLabel = label(stepBg, {Size = UDim2.new(1, -88, 1, 0), Position = UDim2.fromOffset(44, 0), Text = "", TextSize = 13})
minus.MouseButton1Click:Connect(function() S.Dist = math.clamp(S.Dist - 1, 1, 30) onState() end)
plus.MouseButton1Click:Connect(function() S.Dist = math.clamp(S.Dist + 1, 1, 30) onState() end)

-- tombol mulai
local startBg = Instance.new("Frame")
startBg.Size = UDim2.new(1, -PAD * 2, 0, 42)
startBg.Position = UDim2.fromOffset(PAD, 286)
startBg.BackgroundColor3 = GREEN
startBg.BackgroundTransparency = 0.15
startBg.BorderSizePixel = 0
startBg.Parent = panel
corner(startBg, UDim.new(0, 16))
glassEdge(startBg, 1.2, 0.4)
local startBtn = btn(startBg, {Size = UDim2.fromScale(1, 1), Text = "Mulai", TextSize = 15})
pressFx(startBtn, startBg)

local status = label(panel, {Size = UDim2.new(1, -PAD * 2, 0, 18), Position = UDim2.fromOffset(PAD, 336),
    Text = "", TextSize = 11, TextColor3 = SUB, TextTruncate = Enum.TextTruncate.AtEnd})

-- ============ bubble hide/show ============
local bubble = Instance.new("Frame")
bubble.Size = UDim2.fromOffset(46, 46)
bubble.Position = UDim2.fromOffset(20, 36)
bubble.BorderSizePixel = 0
bubble.Visible = false
bubble.Parent = gui
glassBody(bubble, 0.25)
corner(bubble, UDim.new(1, 0))
local bubbleEdge = glassEdge(bubble, 1.4, 0.25)
label(bubble, {Size = UDim2.fromScale(1, 1), Text = "S", Font = FONT_B, TextSize = 18})

local open = false
local function setOpen(v)
    open = v
    if v then
        panel.Visible = true
        TweenService:Create(panel, smooth, {GroupTransparency = 0}):Play()
        TweenService:Create(pScale, smooth, {Scale = 1}):Play()
    else
        local t = TweenService:Create(panel, smooth, {GroupTransparency = 1})
        TweenService:Create(pScale, smooth, {Scale = 0.88}):Play()
        t.Completed:Connect(function() if not open then panel.Visible = false end end)
        t:Play()
    end
end

hideBtn.MouseButton1Click:Connect(function() setOpen(false) end)
makeDraggable(bubble, bubble, function() setOpen(not open) end)
makeDraggable(header, panel)

UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift and bubble.Visible then setOpen(not open) end
end)

closeBtn.MouseButton1Click:Connect(function() stop() gui:Destroy() end)

-- ============ state ============
onState = function()
    local t = S.Target and S.Target.DisplayName or "-"
    distLabel.Text = S.Dist .. " stud"
    status.Text = (S.On and "Mengikuti: " or "Target: ") .. t
    TweenService:Create(selector, quick, {Position = UDim2.new((sideIndex() - 1) / 3, 2, 0, 3)}):Play()
    for i in ipairs(sides) do
        segLabels[i].TextTransparency = (i == sideIndex()) and 0 or 0.35
    end
    startBtn.Text = S.On and "Berhenti" or "Mulai"
    TweenService:Create(startBg, quick, {BackgroundColor3 = S.On and RED or GREEN}):Play()
    TweenService:Create(dot, quick, {BackgroundColor3 = S.On and GREEN or GREY}):Play()
    bubbleEdge.Color = S.On and GREEN or WHITE
end

local idx = 0
pick.MouseButton1Click:Connect(function()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do if p ~= lp then table.insert(list, p) end end
    if #list == 0 then status.Text = "Gak ada player lain" return end
    idx = idx % #list + 1
    box.Text = list[idx].Name
    S.Target = list[idx]
    onState()
end)

startBtn.MouseButton1Click:Connect(function()
    if S.On then
        stop()
    else
        local p = findPlayer(box.Text) or S.Target
        if p then
            S.Target = p
            start()
        else
            status.Text = "Player gak ketemu"
        end
    end
end)

onState()

-- =====================================================
-- LOADING SCREEN
-- =====================================================
local loader = Instance.new("CanvasGroup")
loader.AnchorPoint = Vector2.new(0.5, 0.5)
loader.Size = UDim2.fromOffset(320, 150)
loader.Position = UDim2.fromScale(0.5, 0.5)
loader.BorderSizePixel = 0
loader.GroupTransparency = 1
loader.Parent = gui
glassBody(loader, 0.25)
corner(loader, UDim.new(0, 28))
glassEdge(loader, 1.4, 0.25)
local lScale = Instance.new("UIScale", loader)
lScale.Scale = 0.9

label(loader, {Text = TITLE, Font = FONT_B, TextSize = 16, Size = UDim2.new(1, -24, 0, 24),
    Position = UDim2.fromOffset(12, 28)})
local lStatus = label(loader, {Text = "Memulai...", TextSize = 12, TextColor3 = SUB,
    Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 58)})

local barBg = softBox(loader, {Size = UDim2.new(1, -56, 0, 8), Position = UDim2.fromOffset(28, 94)})
corner(barBg, UDim.new(1, 0))
local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = GREEN
barFill.BorderSizePixel = 0
barFill.Parent = barBg
corner(barFill, UDim.new(1, 0))
local lPct = label(loader, {Text = "0%", Font = FONT_B, TextSize = 11, TextColor3 = SUB,
    Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 114)})

task.spawn(function()
    TweenService:Create(loader, smooth, {GroupTransparency = 0}):Play()
    TweenService:Create(lScale, smooth, {Scale = 1}):Play()
    task.wait(0.35)

    local steps = {
        {"Menyiapkan modul...", 0.25},
        {"Memuat sistem animasi...", 0.55},
        {"Menyiapkan tampilan...", 0.85},
        {"Selesai!", 1},
    }
    for _, st in ipairs(steps) do
        lStatus.Text = st[1]
        TweenService:Create(barFill, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {Size = UDim2.fromScale(st[2], 1)}):Play()
        lPct.Text = math.floor(st[2] * 100) .. "%"
        task.wait(0.55)
    end
    task.wait(0.2)

    TweenService:Create(loader, smooth, {GroupTransparency = 1}):Play()
    TweenService:Create(lScale, smooth, {Scale = 1.06}):Play()
    task.wait(0.35)
    loader:Destroy()

    bubble.Visible = true
    setOpen(true)
end)
