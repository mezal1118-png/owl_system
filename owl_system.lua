--[[
	CapriUtil.client.lua
	LocalScript -> StarterPlayer > StarterPlayerScripts
	(replaces DeadWeight.client.lua; delete the old one)

	Utilities:
	  HEAVY   - max density + extra gravity force, slower walk/jump (physics-based)
	  TPWALK  - moves you by nudging your CFrame each frame (bypasses physics)

	Controls:
	  G = toggle HEAVY   |   T = toggle TPWALK   |   H = hide/show panel
	  Drag the slider to change TPWalk speed.

	HOW TPWALK WORKS (and why it ignores HEAVY):
	  Normal walking: the Humanoid applies forces to reach WalkSpeed, so mass,
	  friction and gravity all matter. TPWalk skips that. Every Heartbeat it
	  reads Humanoid.MoveDirection (the direction you're holding, already
	  camera-relative and flat on the ground) and adds
	      MoveDirection * speed * deltaTime
	  straight onto the HumanoidRootPart's CFrame. That's a teleport, not a
	  force, so density 100 doesn't slow it down at all. Vertical motion is
	  still physics, so with HEAVY on you zip sideways but drop like a rock.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local rng = Random.new()

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------
local CONFIG = {
	HeavyKey = Enum.KeyCode.G,
	TPWalkKey = Enum.KeyCode.T,
	HideKey = Enum.KeyCode.H,

	-- heavy
	Density = 100,
	Friction = 0.5,
	Elasticity = 0,
	ExtraGravity = 2,          -- extra pull in multiples of normal gravity
	WalkSpeedMultiplier = 0.5,
	JumpMultiplier = 0.5,

	-- tpwalk
	TPSpeedMin = 0.15,         -- studs per second added on top of normal walking
	TPSpeedMax = 1,
	TPSpeedDefault = 0.5,
	TPSpeedStep = 0.01,        -- slider snaps to this
	TPPerFrame = false,        -- true = speed is studs per FRAME (~60x faster, classic tpwalk feel)
	TPWallCheck = true,        -- raycast ahead so you don't phase through walls
	TPWallPadding = 1.5,
}

local COLORS = {
	Black = Color3.fromRGB(10, 10, 12),
	Card = Color3.fromRGB(22, 18, 28),
	CardHover = Color3.fromRGB(34, 26, 44),
	Bar = Color3.fromRGB(45, 32, 60),
	Red = Color3.fromRGB(235, 45, 80),
	Green = Color3.fromRGB(90, 245, 90),
	Purple = Color3.fromRGB(140, 70, 255),
	Lilac = Color3.fromRGB(190, 150, 255),
	White = Color3.fromRGB(255, 240, 250),
	Speck = Color3.fromRGB(255, 200, 225),
}

--------------------------------------------------------------------------------
-- HEAVY
--------------------------------------------------------------------------------
local Heavy = { Enabled = false }
local heavyState

local HEAVY_PROPS = PhysicalProperties.new(CONFIG.Density, CONFIG.Friction, CONFIG.Elasticity, 1, 1)

local function applyPart(state, inst)
	if not inst:IsA("BasePart") then
		return
	end
	if state.original[inst] == nil then
		state.original[inst] = inst.CustomPhysicalProperties or false
	end
	inst.CustomPhysicalProperties = HEAVY_PROPS
end

local function releaseHeavy(state)
	if not state then
		return
	end
	state.active = false
	for _, conn in ipairs(state.conns) do
		conn:Disconnect()
	end
	for part, orig in pairs(state.original) do
		if part.Parent then
			part.CustomPhysicalProperties = orig or nil
		end
	end
	if state.force then
		state.force:Destroy()
	end
	if state.attachment then
		state.attachment:Destroy()
	end
	local h = state.humanoid
	if h and h.Parent then
		h.WalkSpeed = state.walkSpeed
		h.JumpPower = state.jumpPower
		h.JumpHeight = state.jumpHeight
	end
end

local function enableHeavy(char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not (humanoid and root) or not Heavy.Enabled or player.Character ~= char then
		return
	end

	releaseHeavy(heavyState)

	local state = {
		active = true,
		humanoid = humanoid,
		root = root,
		original = {},
		conns = {},
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}

	for _, inst in ipairs(char:GetDescendants()) do
		applyPart(state, inst)
	end
	table.insert(state.conns, char.DescendantAdded:Connect(function(inst)
		if state.active then
			applyPart(state, inst)
		end
	end))

	humanoid.WalkSpeed = state.walkSpeed * CONFIG.WalkSpeedMultiplier
	humanoid.JumpPower = state.jumpPower * CONFIG.JumpMultiplier
	humanoid.JumpHeight = state.jumpHeight * CONFIG.JumpMultiplier

	local attachment = Instance.new("Attachment")
	attachment.Name = "CapriHeavyAttachment"
	attachment.Parent = root

	local force = Instance.new("VectorForce")
	force.Name = "CapriHeavyForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root

	state.attachment = attachment
	state.force = force
	heavyState = state
end

function Heavy.set(on)
	if Heavy.Enabled == on then
		return
	end
	Heavy.Enabled = on
	if on then
		if player.Character then
			task.spawn(enableHeavy, player.Character)
		end
	else
		releaseHeavy(heavyState)
		heavyState = nil
	end
end

--------------------------------------------------------------------------------
-- TPWALK
--------------------------------------------------------------------------------
local TPWalk = { Enabled = false, Speed = CONFIG.TPSpeedDefault }

function TPWalk.set(on)
	TPWalk.Enabled = on
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function stepTPWalk(dt)
	local char = player.Character
	if not char then
		return
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 or humanoid.SeatPart then
		return
	end

	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.01 then
		return
	end

	local step = CONFIG.TPPerFrame and 1 or dt
	local offset = moveDir * (TPWalk.Speed * step)

	if CONFIG.TPWallCheck then
		rayParams.FilterDescendantsInstances = { char }
		local reach = offset.Magnitude + CONFIG.TPWallPadding
		local hit = workspace:Raycast(root.Position, offset.Unit * reach, rayParams)
		if hit then
			local allowed = math.max(0, hit.Distance - CONFIG.TPWallPadding)
			offset = offset.Unit * math.min(offset.Magnitude, allowed)
		end
	end

	root.CFrame = root.CFrame + offset -- position only; rotation untouched
end

--------------------------------------------------------------------------------
-- PER-FRAME
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function(dt)
	local s = heavyState
	if s and s.active and s.force and s.root.Parent then
		s.force.Force = Vector3.new(0, -s.root.AssemblyMass * workspace.Gravity * CONFIG.ExtraGravity, 0)
	end
	if TPWalk.Enabled then
		stepTPWalk(dt)
	end
end)

player.CharacterAdded:Connect(function(char)
	releaseHeavy(heavyState)
	heavyState = nil
	if Heavy.Enabled then
		enableHeavy(char)
	end
end)

local function getMass()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.AssemblyMass or 0
end

--------------------------------------------------------------------------------
-- GUI HELPERS
--------------------------------------------------------------------------------
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(inst, duration, goal, style, direction, delay)
	local t = TweenService:Create(inst, TweenInfo.new(
		duration,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out,
		0, false, delay or 0
	), goal)
	t:Play()
	return t
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function ripple(button)
	local mouse = UserInputService:GetMouseLocation()
	local rel = mouse - button.AbsolutePosition
	local size = button.AbsoluteSize
	rel = Vector2.new(math.clamp(rel.X, 0, size.X), math.clamp(rel.Y, 0, size.Y))

	local r = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(rel.X, rel.Y),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = COLORS.White,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, button)
	corner(r)
	local d = math.max(size.X, size.Y) * 2.2
	tween(r, 0.5, { Size = UDim2.fromOffset(d, d), BackgroundTransparency = 1 })
	Debris:AddItem(r, 0.55)
end

--------------------------------------------------------------------------------
-- GUI: SHELL
--------------------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")
for _, name in ipairs({ "DeadWeightGui", "CapriUtilGui" }) do
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local gui = make("ScreenGui", {
	Name = "CapriUtilGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local PANEL_W, PANEL_H = 320, 304
local SHOWN = UDim2.new(0, 24, 0.5, 0)
local HIDDEN = UDim2.new(0, -PANEL_W - 40, 0.5, 0)
local TAB_SHOWN = UDim2.new(0, 0, 0.5, 0)
local TAB_HIDDEN = UDim2.new(0, -34, 0.5, 0)

local panel = make("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = HIDDEN,
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundColor3 = COLORS.Black,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, gui)
make("UIStroke", { Color = COLORS.Purple, Thickness = 2 }, panel)

-- purple notch on the bottom-right corner
make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, 0, 1, 0),
	Size = UDim2.fromOffset(40, 40),
	Rotation = 45,
	BackgroundColor3 = COLORS.Purple,
	BorderSizePixel = 0,
	ZIndex = 4,
}, panel)

-- red shards with speckles ---------------------------------------------------
local shards = {}
local function makeShard(rest, size, rot, speckCount)
	local s = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = rest,
		Size = size,
		Rotation = rot,
		BackgroundColor3 = COLORS.Red,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, panel)
	make("Frame", {
		Position = UDim2.new(0, 0, 0, -3),
		Size = UDim2.new(1, 0, 0, 3),
		BackgroundColor3 = COLORS.Purple,
		BorderSizePixel = 0,
	}, s)
	for _ = 1, speckCount do
		local px = rng:NextInteger(2, 5)
		local dot = make("Frame", {
			Size = UDim2.fromOffset(px, px),
			Position = UDim2.fromScale(rng:NextNumber(0.02, 0.97), rng:NextNumber(0.05, 0.93)),
			BackgroundColor3 = COLORS.Speck,
			BackgroundTransparency = rng:NextNumber(0.1, 0.6),
			BorderSizePixel = 0,
		}, s)
		corner(dot)
		TweenService:Create(dot, TweenInfo.new(
			rng:NextNumber(0.8, 2.5), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true
		), { BackgroundTransparency = 0.95 }):Play()
	end
	table.insert(shards, { frame = s, rest = rest, rot = rot })
	return s
end

local bigShard = makeShard(UDim2.new(0.78, 0, 0.82, 0), UDim2.fromOffset(300, 150), -16, 40)
makeShard(UDim2.new(1.02, 0, 0.18, 0), UDim2.fromOffset(120, 50), 28, 10)

-- spikes -----------------------------------------------------------------------
local spikes = {}
for _, d in ipairs({
	{ x = 0.70, w = 8, h = 58, rot = -12 },
	{ x = 0.82, w = 12, h = 88, rot = 16 },
	{ x = 0.93, w = 9, h = 64, rot = -26 },
}) do
	local f = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(d.x, 0, 0, -6),
		Size = UDim2.fromOffset(d.w, d.h),
		Rotation = d.rot,
		BackgroundColor3 = COLORS.Black,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, panel)
	make("UIStroke", { Color = COLORS.Purple, Thickness = 1 }, f)
	table.insert(spikes, { frame = f, w = d.w, h = d.h })
end

-- header -------------------------------------------------------------------------
local HEADER_SIZE = UDim2.fromOffset(232, 40)
local header = make("Frame", {
	Position = UDim2.fromOffset(-14, 14),
	Size = HEADER_SIZE,
	Rotation = -3,
	BackgroundColor3 = COLORS.Green,
	BorderSizePixel = 0,
	ZIndex = 3,
}, panel)
make("Frame", { -- black slash through the header
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.86, 0, 0.5, 0),
	Size = UDim2.fromOffset(10, 60),
	Rotation = 24,
	BackgroundColor3 = COLORS.Black,
	BorderSizePixel = 0,
}, header)

local TITLE_POS = UDim2.fromOffset(28, 0)
local title = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = TITLE_POS,
	Size = UDim2.new(1, -60, 1, 0),
	Font = Enum.Font.GothamBlack,
	Text = "CAPRI//UTIL",
	TextColor3 = COLORS.Black,
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local subtitle = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 60),
	Size = UDim2.fromOffset(220, 14),
	Font = Enum.Font.Code,
	Text = "> client mods // local only",
	TextColor3 = COLORS.Lilac,
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
}, panel)

local closeBtn = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(26, 26),
	BackgroundColor3 = COLORS.Black,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "X",
	TextColor3 = COLORS.Red,
	TextSize = 14,
	ZIndex = 6,
}, panel)
make("UIStroke", { Color = COLORS.Purple, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, closeBtn)

--------------------------------------------------------------------------------
-- GUI: TOGGLE CARD WITH ANIMATED SWITCH
--------------------------------------------------------------------------------
local entranceItems = {}

local function makeToggleCard(labelText, subText, y, onToggle)
	local rest = UDim2.fromOffset(16, y)
	local card = make("TextButton", {
		Position = rest,
		Size = UDim2.fromOffset(PANEL_W - 32, 56),
		BackgroundColor3 = COLORS.Card,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		ZIndex = 5,
	}, panel)
	local stroke = make("UIStroke", { Color = COLORS.Bar, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	local scale = make("UIScale", { Scale = 1 }, card)

	local accent = make("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = COLORS.Green,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, card)

	local label = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 8),
		Size = UDim2.fromOffset(170, 24),
		Font = Enum.Font.GothamBlack,
		Text = labelText,
		TextColor3 = COLORS.White,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, card)

	make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 32),
		Size = UDim2.fromOffset(180, 14),
		Font = Enum.Font.Code,
		Text = subText,
		TextColor3 = COLORS.Lilac,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, card)

	local track = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(66, 30),
		BackgroundColor3 = COLORS.Black,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, card)
	corner(track)
	local trackStroke = make("UIStroke", { Color = COLORS.Green, Thickness = 2 }, track)

	local stateText = make("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		Font = Enum.Font.GothamBlack,
		Text = "OFF",
		TextColor3 = COLORS.Green,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, track)

	local KNOB_OFF = UDim2.new(0, 4, 0.5, 0)
	local KNOB_ON = UDim2.new(1, -26, 0.5, 0)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = KNOB_OFF,
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = COLORS.Green,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	corner(knob)

	local self = { card = card, on = false, toggle = onToggle }
	local hovered = false

	function self.render(on, animate)
		self.on = on
		local d = animate and 1 or 0

		-- knob slides with overshoot and squashes
		tween(knob, 0.35 * d, { Position = on and KNOB_ON or KNOB_OFF, BackgroundColor3 = on and COLORS.Black or COLORS.Green },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if animate then
			knob.Size = UDim2.fromOffset(34, 16)
			tween(knob, 0.45, { Size = UDim2.fromOffset(22, 22) }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		end

		tween(track, 0.25 * d, { BackgroundColor3 = on and COLORS.Red or COLORS.Black })
		tween(trackStroke, 0.25 * d, { Color = on and COLORS.White or COLORS.Green })
		tween(accent, 0.3 * d, { Size = UDim2.new(0, on and 8 or 4, 1, 0), BackgroundColor3 = on and COLORS.Red or COLORS.Green },
			Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(label, 0.25 * d, { TextColor3 = on and COLORS.Red or COLORS.White })

		stateText.Text = on and "ON" or "OFF"
		stateText.TextXAlignment = on and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
		stateText.TextColor3 = on and COLORS.Black or COLORS.Green
		if animate then
			stateText.TextTransparency = 1
			tween(stateText, 0.2, { TextTransparency = 0 }, nil, nil, 0.12)
			-- label kick
			label.Position = UDim2.fromOffset(26, 8)
			tween(label, 0.3, { Position = UDim2.fromOffset(20, 8) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end

	card.MouseEnter:Connect(function()
		hovered = true
		tween(card, 0.15, { BackgroundColor3 = COLORS.CardHover })
		tween(stroke, 0.15, { Color = COLORS.Purple })
	end)
	card.MouseLeave:Connect(function()
		hovered = false
		tween(card, 0.15, { BackgroundColor3 = COLORS.Card })
		tween(stroke, 0.15, { Color = COLORS.Bar })
		tween(scale, 0.12, { Scale = 1 })
	end)
	card.MouseButton1Down:Connect(function()
		tween(scale, 0.07, { Scale = 0.96 })
	end)
	card.MouseButton1Up:Connect(function()
		tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
	card.Activated:Connect(function()
		ripple(card)
		onToggle()
	end)

	table.insert(entranceItems, { inst = card, rest = rest })
	return self
end

--------------------------------------------------------------------------------
-- GUI: SPEED SLIDER
--------------------------------------------------------------------------------
local SLIDER_Y = 214
local sliderLabel = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, SLIDER_Y),
	Size = UDim2.fromOffset(140, 16),
	Font = Enum.Font.GothamBlack,
	Text = "TP SPEED",
	TextColor3 = COLORS.White,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 5,
}, panel)

local sliderValue = make("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, SLIDER_Y),
	Size = UDim2.fromOffset(100, 16),
	Font = Enum.Font.Code,
	Text = "",
	TextColor3 = COLORS.Green,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 5,
}, panel)

local SLIDER_REST = UDim2.fromOffset(16, SLIDER_Y + 20)
local hit = make("Frame", {
	Position = SLIDER_REST,
	Size = UDim2.fromOffset(PANEL_W - 32, 26),
	BackgroundTransparency = 1,
	Active = true,
	ZIndex = 5,
}, panel)

local bar = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = COLORS.Bar,
	BorderSizePixel = 0,
}, hit)
corner(bar)

local fill = make("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = COLORS.Green,
	BorderSizePixel = 0,
}, bar)
corner(fill)

local sKnob = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromOffset(16, 16),
	Rotation = 45,
	BackgroundColor3 = COLORS.Green,
	BorderSizePixel = 0,
	ZIndex = 2,
}, hit)
make("UIStroke", { Color = COLORS.Black, Thickness = 2 }, sKnob)
local sKnobScale = make("UIScale", { Scale = 1 }, sKnob)

table.insert(entranceItems, { inst = hit, rest = SLIDER_REST })

local function setSpeed(value, animate)
	local stepSize = CONFIG.TPSpeedStep
	value = math.floor(value / stepSize + 0.5) * stepSize
	value = math.clamp(value, CONFIG.TPSpeedMin, CONFIG.TPSpeedMax)
	TPWalk.Speed = value
	local a = (value - CONFIG.TPSpeedMin) / (CONFIG.TPSpeedMax - CONFIG.TPSpeedMin)
	local d = animate and 0.08 or 0
	tween(fill, d, { Size = UDim2.fromScale(a, 1) })
	tween(sKnob, d, { Position = UDim2.fromScale(a, 0.5) })
	sliderValue.Text = string.format(CONFIG.TPPerFrame and "+%.2f st/f" or "+%.2f st/s", value)
end

local dragging = false
local function updateFromX(x)
	local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
	setSpeed(CONFIG.TPSpeedMin + a * (CONFIG.TPSpeedMax - CONFIG.TPSpeedMin), true)
end

hit.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		tween(sKnobScale, 0.15, { Scale = 1.4 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(sKnob, 0.15, { BackgroundColor3 = COLORS.Red })
		tween(fill, 0.15, { BackgroundColor3 = COLORS.Red })
		updateFromX(input.Position.X)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		updateFromX(input.Position.X)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
		dragging = false
		tween(sKnobScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(sKnob, 0.2, { BackgroundColor3 = COLORS.Green })
		tween(fill, 0.2, { BackgroundColor3 = COLORS.Green })
	end
end)

--------------------------------------------------------------------------------
-- GUI: READOUT, FX, TAB
--------------------------------------------------------------------------------
local readout = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(18, 272),
	Size = UDim2.new(1, -60, 0, 16),
	Font = Enum.Font.Code,
	Text = "",
	TextColor3 = COLORS.White,
	TextSize = 11,
	TextStrokeTransparency = 0.4,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 5,
}, panel)

local scan = make("Frame", {
	Position = UDim2.new(0, 0, 0, -4),
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 0.88,
	BorderSizePixel = 0,
	ZIndex = 9,
}, panel)
TweenService:Create(scan, TweenInfo.new(2.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	{ Position = UDim2.new(0, 0, 1, 4) }):Play()

local flash = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = COLORS.White,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 10,
}, panel)

local tab = make("TextButton", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = TAB_HIDDEN,
	Size = UDim2.fromOffset(28, 80),
	BackgroundColor3 = COLORS.Red,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = ">",
	TextColor3 = COLORS.Black,
	TextSize = 18,
}, gui)
make("UIStroke", { Color = COLORS.Purple, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tab)

--------------------------------------------------------------------------------
-- BEHAVIOUR
--------------------------------------------------------------------------------
local visible = false
local shakeId = 0

local function shake(strength, steps)
	shakeId = shakeId + 1
	local id = shakeId
	task.spawn(function()
		for i = 1, steps do
			if not visible or id ~= shakeId then
				return
			end
			local f = 1 - i / steps
			panel.Position = SHOWN + UDim2.fromOffset(
				rng:NextInteger(-strength, strength) * f,
				rng:NextInteger(-strength, strength) * f
			)
			task.wait(0.03)
		end
		if visible and id == shakeId then
			panel.Position = SHOWN
		end
	end)
end

local function pulse(color, transparency)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = transparency
	tween(flash, 0.35, { BackgroundTransparency = 1 })
end

local heavyCard, tpCard
local shardBreath

heavyCard = makeToggleCard("HEAVY", "density 100 // gravity x" .. (CONFIG.ExtraGravity + 1), 86, function()
	local on = not Heavy.Enabled
	Heavy.set(on)
	heavyCard.render(on, true)
	if on then
		pulse(COLORS.White, 0.5)
		shake(8, 12)
		shardBreath = TweenService:Create(bigShard, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Rotation = -19 })
		shardBreath:Play()
	else
		pulse(COLORS.Green, 0.8)
		if shardBreath then
			shardBreath:Cancel()
			shardBreath = nil
		end
		tween(bigShard, 0.3, { Rotation = -16 })
	end
end)

tpCard = makeToggleCard("TPWALK", "cframe nudge // ignores mass", 150, function()
	local on = not TPWalk.Enabled
	TPWalk.set(on)
	tpCard.render(on, true)
	pulse(on and COLORS.Purple or COLORS.Green, on and 0.6 or 0.8)
	-- sideways "zip" on the card
	if on then
		tpCard.card.Position = UDim2.fromOffset(28, 150)
		tween(tpCard.card, 0.3, { Position = UDim2.fromOffset(16, 150) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end
end)

local function playEntrance()
	for i, s in ipairs(shards) do
		s.frame.Position = s.rest + UDim2.fromScale(0.8, 0)
		s.frame.Rotation = s.rot + 20
		tween(s.frame, 0.9, { Position = s.rest, Rotation = s.rot }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.05 + 0.1 * i)
	end

	header.Size = UDim2.fromOffset(0, 40)
	tween(header, 0.45, { Size = HEADER_SIZE }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.15)
	title.TextTransparency = 1
	tween(title, 0.3, { TextTransparency = 0 }, nil, nil, 0.4)
	subtitle.TextTransparency = 1
	tween(subtitle, 0.3, { TextTransparency = 0 }, nil, nil, 0.5)

	for i, s in ipairs(spikes) do
		s.frame.Size = UDim2.fromOffset(s.w, 0)
		tween(s.frame, 0.4, { Size = UDim2.fromOffset(s.w, s.h) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.1 * i)
	end

	for i, item in ipairs(entranceItems) do
		item.inst.Position = item.rest + UDim2.fromOffset(-PANEL_W, 0)
		tween(item.inst, 0.55, { Position = item.rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.3 + 0.09 * i)
	end

	for i, lbl in ipairs({ sliderLabel, sliderValue, readout }) do
		lbl.TextTransparency = 1
		tween(lbl, 0.3, { TextTransparency = 0 }, nil, nil, 0.55 + 0.08 * i)
	end
end

local function setVisible(on)
	if visible == on then
		return
	end
	visible = on
	if on then
		tween(tab, 0.25, { Position = TAB_HIDDEN })
		tween(panel, 0.55, { Position = SHOWN }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		playEntrance()
	else
		tween(panel, 0.35, { Position = HIDDEN }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tween(tab, 0.3, { Position = TAB_SHOWN }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.25)
	end
end

closeBtn.MouseEnter:Connect(function()
	tween(closeBtn, 0.12, { BackgroundColor3 = COLORS.Red, TextColor3 = COLORS.Black, Rotation = 90 })
end)
closeBtn.MouseLeave:Connect(function()
	tween(closeBtn, 0.12, { BackgroundColor3 = COLORS.Black, TextColor3 = COLORS.Red, Rotation = 0 })
end)
closeBtn.Activated:Connect(function()
	setVisible(false)
end)

tab.MouseEnter:Connect(function()
	tween(tab, 0.15, { Size = UDim2.fromOffset(36, 80) })
end)
tab.MouseLeave:Connect(function()
	tween(tab, 0.15, { Size = UDim2.fromOffset(28, 80) })
end)
tab.Activated:Connect(function()
	setVisible(true)
end)

-- title glitch
task.spawn(function()
	while gui.Parent do
		task.wait(rng:NextNumber(3, 6))
		if visible then
			for _ = 1, 4 do
				title.Position = TITLE_POS + UDim2.fromOffset(rng:NextInteger(-4, 4), rng:NextInteger(-2, 2))
				title.TextColor3 = rng:NextNumber() < 0.5 and COLORS.Red or COLORS.Black
				task.wait(0.04)
			end
			title.Position = TITLE_POS
			title.TextColor3 = COLORS.Black
		end
	end
end)

-- live readout
local shownMass = 0
RunService.RenderStepped:Connect(function(dt)
	if not visible then
		return
	end
	shownMass = shownMass + (getMass() - shownMass) * math.min(1, dt * 8)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local vel = root and root.AssemblyLinearVelocity or Vector3.zero
	readout.Text = string.format("MASS %.0f  FALL %.0f  |  G T H", shownMass, math.max(0, -vel.Y))
end)

--------------------------------------------------------------------------------
-- INPUT + START
--------------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == CONFIG.HeavyKey then
		heavyCard.toggle()
	elseif input.KeyCode == CONFIG.TPWalkKey then
		tpCard.toggle()
	elseif input.KeyCode == CONFIG.HideKey then
		setVisible(not visible)
	end
end)

heavyCard.render(false, false)
tpCard.render(false, false)
setSpeed(CONFIG.TPSpeedDefault, false)
setVisible(true)
