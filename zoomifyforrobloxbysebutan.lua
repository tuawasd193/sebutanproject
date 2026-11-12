-- Zoomify v5 (Roblox) - Liquid Glass UI
-- PC     : tahan C = zoom, scroll = atur level zoom, RightShift = hide/show menu
-- Mobile : tahan tombol zoom (kaca bulat), menu bisa di-hide jadi bubble "Z"
-- Kamera tetap kamera bawaan Roblox, gerakannya di-smooth pas zoom.

local env = (getgenv and getgenv()) or _G
if env.ZoomifyUnload then pcall(env.ZoomifyUnload) end -- cegah double execute

local UIS = game:GetService("UserInputService")
local RS = game:GetService("RunService")
local CAS = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local player = game:GetService("Players").LocalPlayer
local cam = workspace.CurrentCamera

------------------------------------------------------------------
-- CONFIG
------------------------------------------------------------------
local CFG = {
	key = Enum.KeyCode.C,            -- tombol zoom (PC)
	hideKey = Enum.KeyCode.RightShift, -- hide/show menu (PC)
	baseFov = cam.FieldOfView,
	minFov = 5,
	maxFov = 60,
	scrollStep = 4,
	zoomFov = 30,
	fovSmooth = 8,    -- kecepatan transisi zoom
	rotSmooth = 10,   -- smoothness kamera (kecil = lebih halus)
	sensScale = 0.5,  -- penurunan sensitivitas mouse pas zoom
	toggleMode = false,
	showButton = UIS.TouchEnabled,
}

local ui = {}
local conns = {}
local function keep(c) conns[#conns + 1] = c return c end

------------------------------------------------------------------
-- CORE
------------------------------------------------------------------
local zooming = false
local rawCF, smoothRot
local savedMin, savedMax, savedSens

local function setZooming(state)
	if state == zooming then return end
	zooming = state
	if state then
		savedSens = UIS.MouseDeltaSensitivity
		savedMin, savedMax = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
		local dist = math.max((cam.Focus.Position - cam.CFrame.Position).Magnitude, 0.5)
		player.CameraMinZoomDistance = dist
		player.CameraMaxZoomDistance = dist
	else
		UIS.MouseDeltaSensitivity = savedSens or 1
		if savedMin then
			player.CameraMinZoomDistance = savedMin
			player.CameraMaxZoomDistance = savedMax
		end
	end
	if ui.zoomActive then ui.zoomActive(zooming) end
end

local function pressZoom()
	if CFG.toggleMode then setZooming(not zooming) else setZooming(true) end
end

local function releaseZoom()
	if not CFG.toggleMode then setZooming(false) end
end

local function setZoomFov(v)
	CFG.zoomFov = math.clamp(v, CFG.minFov, CFG.maxFov)
	if ui.zoomSlider then ui.zoomSlider.set(CFG.zoomFov, true) end
end

local toggleMenu -- diisi pas UI dibangun

local function bindCore()
	-- scroll cuma ngatur FOV pas zoom, gak diterusin ke kamera bawaan
	CAS:BindActionAtPriority("ZoomifyScroll", function(_, state, input)
		if not zooming then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Change then
			setZoomFov(CFG.zoomFov - input.Position.Z * CFG.scrollStep)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.UserInputType.MouseWheel)

	-- sebelum kamera bawaan jalan: balikin CFrame mentah (anti feedback smoothing)
	RS:BindToRenderStep("ZoomifyPre", Enum.RenderPriority.Camera.Value - 1, function()
		if rawCF then cam.CFrame = rawCF end
	end)

	-- setelah kamera bawaan jalan: smooth rotasi buat ditampilin
	RS:BindToRenderStep("ZoomifyPost", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local target = zooming and CFG.zoomFov or CFG.baseFov
		cam.FieldOfView += (target - cam.FieldOfView) * (1 - math.exp(-dt * CFG.fovSmooth))
		if zooming then
			UIS.MouseDeltaSensitivity = (savedSens or 1) * (cam.FieldOfView / CFG.baseFov) ^ CFG.sensScale
		end

		local raw = cam.CFrame
		local active = zooming
			or math.abs(cam.FieldOfView - CFG.baseFov) > 0.5
			or (smoothRot ~= nil and smoothRot.LookVector:Dot(raw.LookVector) < 0.9999)
		if not active then
			rawCF, smoothRot = nil, nil
			return
		end

		rawCF = raw
		local rawRot = raw.Rotation
		smoothRot = smoothRot or rawRot
		smoothRot = smoothRot:Lerp(rawRot, 1 - math.exp(-dt * CFG.rotSmooth))

		local focus = cam.Focus.Position
		local pos = focus + (smoothRot * rawRot:Inverse()) * (raw.Position - focus)
		cam.CFrame = CFrame.new(pos) * smoothRot
	end)
end

local function bindInput()
	keep(UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == CFG.key then
			pressZoom()
		elseif input.KeyCode == CFG.hideKey then
			if toggleMenu then toggleMenu() end
		end
	end))
	keep(UIS.InputEnded:Connect(function(input)
		if input.KeyCode == CFG.key then releaseZoom() end
	end))
end

------------------------------------------------------------------
-- GUI HELPERS
------------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local ACCENT = Color3.fromRGB(10, 132, 255)
local GREEN = Color3.fromRGB(52, 199, 89)
local GRAY = Color3.fromRGB(120, 120, 128)
local GLASS_DARK = Color3.fromRGB(26, 28, 38)

local gui = Instance.new("ScreenGui")
gui.Name = "ZoomifyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 1000

local function mountGui(g)
	local ok = pcall(function()
		if gethui then g.Parent = gethui() else error("no gethui") end
	end)
	if ok and g.Parent then return end
	ok = pcall(function() g.Parent = game:GetService("CoreGui") end)
	if ok and g.Parent then return end
	g.Parent = player:WaitForChild("PlayerGui")
end

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(o, r)
	return new("UICorner", {CornerRadius = UDim.new(0, r)}, o)
end

local function tw(o, t, props)
	TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props):Play()
end

-- efek liquid glass: tint gelap transparan + sheen putih + stroke gradient
local function glass(o, radius, tint)
	o.BackgroundColor3 = GLASS_DARK
	o.BackgroundTransparency = tint or 0.4
	o.BorderSizePixel = 0
	corner(o, radius)
	local sheen = new("Frame", {
		BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), ZIndex = 0, Active = false,
	}, o)
	corner(sheen, radius)
	new("UIGradient", {
		Rotation = 55,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.84),
			NumberSequenceKeypoint.new(0.45, 0.95),
			NumberSequenceKeypoint.new(1, 0.98),
		}),
	}, sheen)
	local stroke = new("UIStroke", {
		Color = WHITE, Thickness = 1.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, o)
	new("UIGradient", {
		Rotation = 45,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
	}, stroke)
	return o
end

local function label(parent, text, size, opts)
	opts = opts or {}
	return new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = opts.font or Enum.Font.GothamMedium,
		TextColor3 = opts.color or WHITE,
		TextTransparency = opts.transp or 0,
		TextXAlignment = opts.align or Enum.TextXAlignment.Left,
		TextWrapped = opts.wrap or false,
		Size = opts.size or UDim2.new(1, 0, 0, size + 4),
		Position = opts.pos or UDim2.new(),
		AutomaticSize = opts.auto or Enum.AutomaticSize.None,
		LayoutOrder = opts.order or 0,
		ZIndex = 2,
	}, parent)
end

local function makeDraggable(handle, target, onTap)
	local dragging, moved, startPos, startMouse = false, false, nil, nil
	handle.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging, moved = true, false
			startMouse, startPos = input.Position, target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved and onTap then onTap() end
				end
			end)
		end
	end)
	keep(UIS.InputChanged:Connect(function(input)
		local t = input.UserInputType
		if dragging and (t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			if d.Magnitude > 6 then moved = true end
			if moved then
				target.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y
				)
			end
		end
	end))
end

local function slider(parent, order, title, min, max, init, step, fmt, onChange, scrollRef)
	local row = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 46), LayoutOrder = order, ZIndex = 2,
	}, parent)
	label(row, title, 13, {size = UDim2.new(0.6, 0, 0, 18)})
	local val = label(row, "", 13, {
		size = UDim2.new(0.4, 0, 0, 18), pos = UDim2.new(0.6, 0, 0, 0),
		align = Enum.TextXAlignment.Right, transp = 0.25,
	})
	local bar = new("Frame", {
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.78, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0, 28), ZIndex = 2,
	}, row)
	corner(bar, 3)
	local fill = new("Frame", {
		BackgroundColor3 = ACCENT, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 3,
	}, bar)
	corner(fill, 3)
	local knob = new("Frame", {
		BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(20, 20), Position = UDim2.fromScale(0, 0.5), ZIndex = 4,
	}, bar)
	corner(knob, 10)
	new("UIStroke", {Color = Color3.new(0, 0, 0), Transparency = 0.85, Thickness = 1}, knob)
	local hit = new("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 16), ZIndex = 5,
	}, row)

	local obj = {}
	function obj.set(v, silent)
		v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		val.Text = fmt(v)
		if not silent then onChange(v) end
	end

	local function fromX(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		obj.set(min + a * (max - min))
	end

	local dragging
	hit.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			if scrollRef.frame then scrollRef.frame.ScrollingEnabled = false end
			fromX(input.Position.X)
		end
	end)
	keep(UIS.InputChanged:Connect(function(input)
		if dragging and (input == dragging or input.UserInputType == Enum.UserInputType.MouseMovement) then
			fromX(input.Position.X)
		end
	end))
	keep(UIS.InputEnded:Connect(function(input)
		if dragging and input == dragging then
			dragging = nil
			if scrollRef.frame then scrollRef.frame.ScrollingEnabled = true end
		end
	end))

	obj.set(init, true)
	return obj
end

local function switch(parent, order, title, init, onChange)
	local row = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = order, ZIndex = 2,
	}, parent)
	label(row, title, 13, {size = UDim2.new(1, -60, 1, 0)})
	local sw = new("Frame", {
		BackgroundColor3 = init and GREEN or GRAY, BackgroundTransparency = init and 0 or 0.5,
		BorderSizePixel = 0, Size = UDim2.fromOffset(46, 28),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), ZIndex = 2,
	}, row)
	corner(sw, 14)
	local knob = new("Frame", {
		BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = init and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 2, 0.5, 0), ZIndex = 3,
	}, sw)
	corner(knob, 12)
	local btn = new("TextButton", {
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1), ZIndex = 5,
	}, row)

	local state = init
	local obj = {}
	function obj.set(s, silent)
		state = s
		tw(sw, 0.2, {BackgroundColor3 = s and GREEN or GRAY, BackgroundTransparency = s and 0 or 0.5})
		tw(knob, 0.2, {Position = s and UDim2.new(1, -26, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)})
		if not silent then onChange(s) end
	end
	btn.Activated:Connect(function() obj.set(not state) end)
	return obj
end

------------------------------------------------------------------
-- UI
------------------------------------------------------------------
local panel, bubble
local menuOpen = false

local function unload() end -- diisi di bawah

local function buildZoomButton()
	local b = new("TextButton", {
		Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(68, 68),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -110, 0.5, 0), Visible = false,
	}, gui)
	glass(b, 34, 0.45)
	local lens = new("Frame", {
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.46, 0.45), Size = UDim2.fromOffset(24, 24), ZIndex = 2,
	}, b)
	corner(lens, 12)
	new("UIStroke", {Color = WHITE, Thickness = 2.5}, lens)
	local handle = new("Frame", {
		BackgroundColor3 = WHITE, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.65, 0.64), Size = UDim2.fromOffset(3, 12), Rotation = -45, ZIndex = 2,
	}, b)
	corner(handle, 2)

	b.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			pressZoom()
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					c:Disconnect()
					releaseZoom()
				end
			end)
		end
	end)

	ui.zoomBtn = b
	ui.zoomActive = function(on)
		tw(b, 0.2, {
			BackgroundColor3 = on and ACCENT or GLASS_DARK,
			BackgroundTransparency = on and 0.25 or 0.45,
		})
	end
end

local function buildUI()
	local vp = cam.ViewportSize
	local W, headerH = 300, 50
	local bodyH = math.clamp(vp.Y - 150, 140, 340)
	local H = headerH + bodyH + 10

	panel = new("CanvasGroup", {
		Size = UDim2.fromOffset(W, H), Position = UDim2.new(0, 24, 0.5, -H / 2),
		GroupTransparency = 1, Visible = false, Active = true,
	}, gui)
	glass(panel, 26, 0.4)

	-- header
	local header = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, headerH), Active = true, ZIndex = 2,
	}, panel)
	label(header, "Zoomify", 18, {
		font = Enum.Font.GothamBold, size = UDim2.new(0.7, 0, 0, 22), pos = UDim2.new(0, 18, 0, 7),
	})
	label(header, "By Sebutan", 11, {
		size = UDim2.new(0.7, 0, 0, 14), pos = UDim2.new(0, 18, 0, 28), transp = 0.4,
	})
	local hideBtn = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = WHITE, BackgroundTransparency = 0.8,
		BorderSizePixel = 0, Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), ZIndex = 3,
	}, header)
	corner(hideBtn, 15)
	new("UIStroke", {Color = WHITE, Transparency = 0.7, Thickness = 1}, hideBtn)
	label(hideBtn, "–", 20, {
		font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center, size = UDim2.fromScale(1, 1),
	})
	hideBtn.Activated:Connect(function() toggleMenu(false) end)
	makeDraggable(header, panel)

	-- body
	local scrollRef = {}
	local body = new("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, headerH), Size = UDim2.new(1, 0, 0, bodyH),
		ScrollBarThickness = 2, ScrollBarImageColor3 = WHITE,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 2,
	}, panel)
	scrollRef.frame = body
	new("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, body)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12),
	}, body)

	ui.zoomSlider = slider(body, 1, "Zoom Level", CFG.minFov, CFG.maxFov, CFG.zoomFov, 1,
		function(v) return string.format("%.0f°", v) end,
		function(v) CFG.zoomFov = v end, scrollRef)

	slider(body, 2, "Zoom Speed", 2, 20, CFG.fovSmooth, 1,
		function(v) return string.format("%.0f", v) end,
		function(v) CFG.fovSmooth = v end, scrollRef)

	slider(body, 3, "Smoothness", 1, 10, math.floor((22 - CFG.rotSmooth) / 2 + 0.5), 1,
		function(v) return string.format("%.0f", v) end,
		function(v) CFG.rotSmooth = 22 - v * 2 end, scrollRef)

	slider(body, 4, "Sensitivity Drop", 0, 100, CFG.sensScale * 100, 5,
		function(v) return string.format("%.0f%%", v) end,
		function(v) CFG.sensScale = v / 100 end, scrollRef)

	switch(body, 5, "Toggle mode (tap to zoom)", CFG.toggleMode, function(s)
		CFG.toggleMode = s
		if not s then setZooming(false) end
	end)

	switch(body, 6, "Show zoom button", CFG.showButton, function(s)
		CFG.showButton = s
		if ui.zoomBtn then ui.zoomBtn.Visible = s end
	end)

	label(body, "PC: tahan C buat zoom, scroll buat atur level. RightShift buat hide menu. Mobile: tahan tombol zoom.", 11, {
		order = 7, wrap = true, transp = 0.45, auto = Enum.AutomaticSize.Y, size = UDim2.new(1, 0, 0, 14),
	})

	local unloadBtn = new("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(255, 69, 58),
		BackgroundTransparency = 0.7, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 38),
		LayoutOrder = 8, ZIndex = 2,
	}, body)
	corner(unloadBtn, 12)
	new("UIStroke", {Color = Color3.fromRGB(255, 69, 58), Transparency = 0.5, Thickness = 1}, unloadBtn)
	label(unloadBtn, "Unload Zoomify", 13, {
		font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center, size = UDim2.fromScale(1, 1),
	})
	unloadBtn.Activated:Connect(function() unload() end)

	-- bubble (kondisi menu di-hide)
	bubble = new("TextButton", {
		Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(0, 14, 0.35, 0), Visible = false,
	}, gui)
	glass(bubble, 26, 0.4)
	label(bubble, "Z", 20, {
		font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center, size = UDim2.fromScale(1, 1),
	})
	makeDraggable(bubble, bubble, function() toggleMenu(true) end)

	buildZoomButton()

	toggleMenu = function(force)
		if force == nil then force = not menuOpen end
		menuOpen = force
		if menuOpen then
			bubble.Visible = false
			panel.Visible = true
			tw(panel, 0.25, {GroupTransparency = 0})
		else
			bubble.Visible = true
			tw(panel, 0.2, {GroupTransparency = 1})
			task.delay(0.22, function()
				if not menuOpen and panel and panel.Parent then panel.Visible = false end
			end)
		end
	end
end

------------------------------------------------------------------
-- UNLOAD
------------------------------------------------------------------
unload = function()
	setZooming(false)
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() RS:UnbindFromRenderStep("ZoomifyPre") end)
	pcall(function() RS:UnbindFromRenderStep("ZoomifyPost") end)
	pcall(function() CAS:UnbindAction("ZoomifyScroll") end)
	rawCF, smoothRot = nil, nil
	cam.FieldOfView = CFG.baseFov
	gui:Destroy()
	env.ZoomifyUnload = nil
end
env.ZoomifyUnload = unload

------------------------------------------------------------------
-- LOADING SCREEN
------------------------------------------------------------------
mountGui(gui)

local card = new("CanvasGroup", {
	Size = UDim2.fromOffset(270, 140), AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 1,
}, gui)
glass(card, 28, 0.35)
label(card, "Zoomify By Sebutan", 22, {
	font = Enum.Font.GothamBold, align = Enum.TextXAlignment.Center,
	size = UDim2.new(1, 0, 0, 30), pos = UDim2.new(0, 0, 0, 18),
})
label(card, "Smooth camera zoom", 12, {
	align = Enum.TextXAlignment.Center, transp = 0.4,
	size = UDim2.new(1, 0, 0, 16), pos = UDim2.new(0, 0, 0, 50),
})
local status = label(card, "Starting…", 13, {
	align = Enum.TextXAlignment.Center, size = UDim2.new(1, 0, 0, 18), pos = UDim2.new(0, 0, 0, 82),
})
local barBg = new("Frame", {
	BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0,
	Size = UDim2.new(1, -60, 0, 6), Position = UDim2.new(0, 30, 0, 112), ZIndex = 2,
}, card)
corner(barBg, 3)
local barFill = new("Frame", {
	BackgroundColor3 = ACCENT, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), ZIndex = 3,
}, barBg)
corner(barFill, 3)
tw(card, 0.3, {GroupTransparency = 0})
task.wait(0.35)

local stages = {
	{"Loading camera core…", bindCore},
	{"Binding controls…", bindInput},
	{"Building interface…", buildUI},
	{"Ready", function() end},
}

for i, s in ipairs(stages) do
	status.Text = s[1]
	local ok, err = pcall(s[2])
	if not ok then
		status.Text = "Failed to load"
		warn("[Zoomify] " .. tostring(err))
		task.wait(2)
		unload()
		return
	end
	tw(barFill, 0.3, {Size = UDim2.fromScale(i / #stages, 1)})
	task.wait(0.4)
end

tw(card, 0.35, {GroupTransparency = 1})
task.wait(0.4)
card:Destroy()

if ui.zoomBtn then ui.zoomBtn.Visible = CFG.showButton end
toggleMenu(true)
