--[[
    Camera Spin - Liquid Glass UI (iOS style)
    - Pilih arah: Kiri / Kanan
    - Slider kecepatan
    - Start / Stop
    - Hide / Unhide (jadi bubble kecil)
    - GUI bisa di-drag (mouse & touch)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local lp = Players.LocalPlayer
local GUI_NAME = "GlassCamSpin"
local BIND_NAME = "GlassCamSpinStep"

----------------------------------------------------------------
-- Parent GUI (aman buat berbagai executor)
----------------------------------------------------------------
local function getContainer()
    local ok, res = pcall(function()
        return gethui and gethui()
    end)
    if ok and res then return res end
    ok, res = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and res then return res end
    return lp:WaitForChild("PlayerGui")
end

local container = getContainer()

-- hapus instance lama kalau script di-execute ulang
pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
for _, v in ipairs(container:GetChildren()) do
    if v.Name == GUI_NAME then v:Destroy() end
end

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local direction = 1       -- 1 = kiri, -1 = kanan
local speed = 60          -- derajat per detik
local MIN_SPEED, MAX_SPEED = 5, 300
local running = false

----------------------------------------------------------------
-- Helper UI
----------------------------------------------------------------
local function new(class, props, children)
    local o = Instance.new(class)
    local parent = props.Parent
    props.Parent = nil
    for k, v in pairs(props) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    if parent then o.Parent = parent end
    return o
end

local function corner(r)
    return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function stroke(transp, thickness)
    return new("UIStroke", {
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = transp,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function sheen()
    -- kilau kaca: terang di atas, memudar ke bawah
    return new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.55),
            NumberSequenceKeypoint.new(0.5, 0.82),
            NumberSequenceKeypoint.new(1, 0.7),
        }),
    })
end

local function tween(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

-- drag helper (mouse + touch).
-- onClick dipanggil kalau cuma tap tanpa geser
local function makeDraggable(handle, target, onClick)
    local dragging, moved = false, false
    local dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved and onClick then onClick() end
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local d = input.Position - dragStart
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end
    end)
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local gui = new("ScreenGui", {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999,
})
if not pcall(function() gui.Parent = container end) then
    gui.Parent = lp:WaitForChild("PlayerGui")
end

-- Root (yang di-drag). Main & bubble sama-sama nempel di sini,
-- jadi posisinya selalu sama waktu hide/unhide.
local root = new("Frame", {
    Name = "Root",
    Size = UDim2.fromOffset(0, 0),
    Position = UDim2.new(0.5, -130, 0.5, -127),
    BackgroundTransparency = 1,
    Parent = gui,
})

-- Window utama
local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(260, 254),
    Position = UDim2.fromOffset(0, 0),
    BackgroundColor3 = Color3.fromRGB(22, 24, 32),
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
    Parent = root,
}, { corner(26), stroke(0.55, 1.2) })

-- lapisan kilau kaca
new("Frame", {
    Name = "Sheen",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Active = false,
    Parent = main,
}, { corner(26), sheen() })

-- Header (area drag)
local header = new("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundTransparency = 1,
    Active = true,
    Parent = main,
})

new("TextLabel", {
    Size = UDim2.new(1, -70, 1, 0),
    Position = UDim2.fromOffset(18, 0),
    BackgroundTransparency = 1,
    Text = "Camera Spin",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 17,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

local hideBtn = new("TextButton", {
    Name = "Hide",
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -40, 0.5, -14),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.8,
    AutoButtonColor = false,
    Text = "–",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    Parent = header,
}, { corner(14), stroke(0.7, 1) })

-- Segmented control (Kiri / Kanan)
local seg = new("Frame", {
    Name = "Direction",
    Size = UDim2.new(1, -36, 0, 38),
    Position = UDim2.fromOffset(18, 52),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.85,
    BorderSizePixel = 0,
    Parent = main,
}, { corner(19), stroke(0.75, 1) })

local indicator = new("Frame", {
    Size = UDim2.new(0.5, -4, 1, -4),
    Position = UDim2.fromOffset(2, 2),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    Parent = seg,
}, { corner(17) })

local function segButton(text, xScale)
    return new("TextButton", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.fromScale(xScale, 0),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = text,
        TextSize = 15,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        ZIndex = 2,
        Parent = seg,
    })
end

local leftBtn = segButton("Kiri", 0)
local rightBtn = segButton("Kanan", 0.5)

local DARK = Color3.fromRGB(20, 22, 30)
local WHITE = Color3.fromRGB(255, 255, 255)

local function setDirection(dir)
    direction = dir
    if dir == 1 then
        tween(indicator, { Position = UDim2.fromOffset(2, 2) })
        tween(leftBtn, { TextColor3 = DARK })
        tween(rightBtn, { TextColor3 = WHITE })
    else
        tween(indicator, { Position = UDim2.new(0.5, 2, 0, 2) })
        tween(leftBtn, { TextColor3 = WHITE })
        tween(rightBtn, { TextColor3 = DARK })
    end
end

leftBtn.MouseButton1Click:Connect(function() setDirection(1) end)
rightBtn.MouseButton1Click:Connect(function() setDirection(-1) end)
leftBtn.TextColor3 = DARK -- default: kiri

-- Segmented control mode (CFrame / Mouse)
local modeSeg = new("Frame", {
    Name = "Mode",
    Size = UDim2.new(1, -36, 0, 34),
    Position = UDim2.fromOffset(18, 96),
    BackgroundColor3 = WHITE,
    BackgroundTransparency = 0.85,
    BorderSizePixel = 0,
    Parent = main,
}, { corner(17), stroke(0.75, 1) })

local modeInd = new("Frame", {
    Size = UDim2.new(0.5, -4, 1, -4),
    Position = UDim2.fromOffset(2, 2),
    BackgroundColor3 = WHITE,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    Parent = modeSeg,
}, { corner(15) })

local function modeButton(text, xScale)
    return new("TextButton", {
        Size = UDim2.new(0.5, 0, 1, 0),
        Position = UDim2.fromScale(xScale, 0),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = text,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextColor3 = WHITE,
        ZIndex = 2,
        Parent = modeSeg,
    })
end

local cframeBtn = modeButton("Mode CFrame", 0)
local mouseBtn = modeButton("Mode Mouse", 0.5)
cframeBtn.TextColor3 = DARK

-- Slider speed
local speedLabel = new("TextLabel", {
    Size = UDim2.new(1, -36, 0, 18),
    Position = UDim2.fromOffset(18, 142),
    BackgroundTransparency = 1,
    Text = "Kecepatan: " .. speed .. "°/s",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 13,
    Font = Enum.Font.GothamMedium,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = main,
})

local sliderHit = new("Frame", {
    Name = "SliderHit",
    Size = UDim2.new(1, -36, 0, 28),
    Position = UDim2.fromOffset(18, 162),
    BackgroundTransparency = 1,
    Active = true,
    Parent = main,
})

local track = new("Frame", {
    Size = UDim2.new(1, 0, 0, 6),
    Position = UDim2.new(0, 0, 0.5, -3),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.8,
    BorderSizePixel = 0,
    Parent = sliderHit,
}, { corner(3) })

local initRel = (speed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)

local fill = new("Frame", {
    Size = UDim2.new(initRel, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(10, 132, 255),
    BorderSizePixel = 0,
    Parent = track,
}, { corner(3) })

local knob = new("Frame", {
    Size = UDim2.fromOffset(24, 24),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(initRel, 0, 0.5, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    ZIndex = 3,
    Parent = track,
}, { corner(12), stroke(0.6, 1) })

local sliding = false

local function setFromX(x)
    local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
    speed = math.floor(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * rel + 0.5)
    fill.Size = UDim2.new(rel, 0, 1, 0)
    knob.Position = UDim2.new(rel, 0, 0.5, 0)
    speedLabel.Text = "Kecepatan: " .. speed .. "°/s"
end

sliderHit.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        sliding = true
        setFromX(input.Position.X)
        tween(knob, { Size = UDim2.fromOffset(28, 28) }, 0.12)
    end
end)

UIS.InputChanged:Connect(function(input)
    if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        setFromX(input.Position.X)
    end
end)

UIS.InputEnded:Connect(function(input)
    if sliding and (input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch) then
        sliding = false
        tween(knob, { Size = UDim2.fromOffset(24, 24) }, 0.12)
    end
end)

-- Tombol Start / Stop
local GREEN = Color3.fromRGB(48, 209, 88)
local RED = Color3.fromRGB(255, 69, 58)

local startBtn = new("TextButton", {
    Name = "StartStop",
    Size = UDim2.new(1, -36, 0, 40),
    Position = UDim2.fromOffset(18, 200),
    BackgroundColor3 = GREEN,
    BackgroundTransparency = 0.1,
    AutoButtonColor = false,
    Text = "Start",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 16,
    Font = Enum.Font.GothamBold,
    Parent = main,
}, { corner(20), stroke(0.6, 1) })

----------------------------------------------------------------
-- Logic kamera
----------------------------------------------------------------
local mode = "cframe"
local mmr, m2p, m2r = mousemoverel, mouse2press, mouse2release
local hasMouse = mmr ~= nil and m2p ~= nil and m2r ~= nil
local mouseAcc = 0

-- MODE CFRAME: kamera tetap di mode Custom (default Roblox), jadi tetap
-- ngikutin karakter. Tiap frame kamera diputar mengelilingi Focus.
local function stepCFrame(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end
    local focus = cam.Focus.Position
    local rot = CFrame.Angles(0, math.rad(speed * direction * dt), 0)
    cam.CFrame = CFrame.new(focus) * rot * CFrame.new(-focus) * cam.CFrame
end

-- MODE MOUSE: tahan klik kanan + geser mouse ke samping (simulasi input).
-- Konversi derajat -> pixel itu perkiraan (~0.25 derajat per pixel).
local function stepMouse(dt)
    local sens = 1
    pcall(function()
        sens = UserSettings():GetService("UserGameSettings").MouseSensitivity
    end)
    if sens <= 0 then sens = 1 end
    mouseAcc = mouseAcc + (-direction) * (speed * dt) / (0.25 * sens)
    local whole = mouseAcc >= 0 and math.floor(mouseAcc) or math.ceil(mouseAcc)
    if whole ~= 0 then
        pcall(mmr, whole, 0)
        mouseAcc = mouseAcc - whole
    end
end

local function runningText()
    return mode == "mouse" and "Stop (K)" or "Stop"
end

local function flash(text)
    startBtn.Text = text
    task.delay(1.6, function()
        if startBtn.Parent then
            startBtn.Text = running and runningText() or "Start"
        end
    end)
end

local function start()
    if running then return end
    if mode == "mouse" then
        if not hasMouse then flash("Mouse gak support") return end
        running = true
        mouseAcc = 0
        pcall(m2p)
        RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, stepMouse)
    else
        running = true
        RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, stepCFrame)
    end
    startBtn.Text = runningText()
    tween(startBtn, { BackgroundColor3 = RED })
end

local function stop()
    if not running then return end
    running = false
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    if mode == "mouse" and hasMouse then pcall(m2r) end
    startBtn.Text = "Start"
    tween(startBtn, { BackgroundColor3 = GREEN })
end

local function setMode(m)
    if m == "mouse" and not hasMouse then
        flash("Mouse gak support")
        return
    end
    if running then stop() end
    mode = m
    if m == "cframe" then
        tween(modeInd, { Position = UDim2.fromOffset(2, 2) })
        tween(cframeBtn, { TextColor3 = DARK })
        tween(mouseBtn, { TextColor3 = WHITE })
    else
        tween(modeInd, { Position = UDim2.new(0.5, 2, 0, 2) })
        tween(cframeBtn, { TextColor3 = WHITE })
        tween(mouseBtn, { TextColor3 = DARK })
    end
end

cframeBtn.MouseButton1Click:Connect(function() setMode("cframe") end)
mouseBtn.MouseButton1Click:Connect(function() setMode("mouse") end)

-- Hotkey K = start/stop (penting buat mode Mouse: pas klik kanan
-- ditahan, kursor kekunci jadi tombol Stop gak bisa diklik)
UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.K then
        if running then stop() else start() end
    end
end)

startBtn.MouseButton1Click:Connect(function()
    if running then stop() else start() end
end)

----------------------------------------------------------------
-- Bubble (mode hide)
----------------------------------------------------------------
local bubble = new("TextButton", {
    Name = "Bubble",
    Size = UDim2.fromOffset(52, 52),
    Position = UDim2.fromOffset(0, 0),
    BackgroundColor3 = Color3.fromRGB(22, 24, 32),
    BackgroundTransparency = 0.45,
    AutoButtonColor = false,
    Text = "CAM",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    Visible = false,
    Parent = root,
}, { corner(26), stroke(0.55, 1.2) })

new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BorderSizePixel = 0,
    Active = false,
    ZIndex = 0,
    Parent = bubble,
}, { corner(26), sheen() })

local function hideUI()
    main.Visible = false
    bubble.Visible = true
end

local function showUI()
    bubble.Visible = false
    main.Visible = true
end

hideBtn.MouseButton1Click:Connect(hideUI)

makeDraggable(header, root)
makeDraggable(bubble, root, showUI)

----------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------
gui.Destroying:Connect(function()
    stop()
end)
