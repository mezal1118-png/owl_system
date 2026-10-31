--[[
	CapriUtil - Executor Debug Safe Version
	If it doesn't open, press F9 in-game to check the console for errors.
]]

task.spawn(function()
	local success, err = pcall(function()
		local Players = game:GetService("Players")
		local RunService = game:GetService("RunService")
		local TweenService = game:GetService("TweenService")
		local UserInputService = game:GetService("UserInputService")
		local Debris = game:GetService("Debris")

		local player = Players.LocalPlayer
		local start = tick()
		while not player and (tick() - start < 10) do
			task.wait(0.1)
			player = Players.LocalPlayer
		end
		if not player then error("LocalPlayer not found.") end

		local playerGui = player:WaitForChild("PlayerGui", 10)
		if not playerGui then error("PlayerGui not found.") end

		local rng = Random.new()

		--------------------------------------------------------------------------------
		-- CONFIG
		--------------------------------------------------------------------------------
		local CONFIG = {
			HeavyKey = Enum.KeyCode.G,
			TPWalkKey = Enum.KeyCode.T,
			HideKey = Enum.KeyCode.H,

			Density = 100,
			Friction = 0.5,
			Elasticity = 0,
			ExtraGravity = 2,
			WalkSpeedMultiplier = 0.5,
			JumpMultiplier = 0.5,

			TPSpeedMin = 0.15,
			TPSpeedMax = 1,
			TPSpeedDefault = 0.5,
			TPSpeedStep = 0.01,
			TPPerFrame = false,
			TPWallCheck = true,
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
			if not inst:IsA("BasePart") then return end
			if state.original[inst] == nil then
				state.original[inst] = inst.CustomPhysicalProperties or false
			end
			inst.CustomPhysicalProperties = HEAVY_PROPS
		end

		local function releaseHeavy(state)
			if not state then return end
			state.active = false
			for _, conn in ipairs(state.conns) do conn:Disconnect() end
			for part, orig in pairs(state.original) do
				if part.Parent then part.CustomPhysicalProperties = orig or nil end
			end
			if state.force then state.force:Destroy() end
			if state.attachment then state.attachment:Destroy() end
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
			if not (humanoid and root) or not Heavy.Enabled or player.Character ~= char then return end

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

			for _, inst in ipairs(char:GetDescendants()) do applyPart(state, inst) end
			table.insert(state.conns, char.DescendantAdded:Connect(function(inst)
				if state.active then applyPart(state, inst) end
			end))

			humanoid.WalkSpeed = state.walkSpeed * CONFIG.WalkSpeedMultiplier
			humanoid.JumpPower = state.jumpPower * CONFIG.JumpMultiplier
			humanoid.JumpHeight = state.jumpHeight * CONFIG.JumpMultiplier

			local attachment = Instance.new("Attachment", root)
			attachment.Name = "CapriHeavyAttachment"

			local force = Instance.new("VectorForce", root)
			force.Name = "CapriHeavyForce"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Force = Vector3.zero

			state.attachment = attachment
			state.force = force
			heavyState = state
		end

		function Heavy.set(on)
			if Heavy.Enabled == on then return end
			Heavy.Enabled = on
			if on then
				if player.Character then task.spawn(enableHeavy, player.Character) end
			else
				releaseHeavy(heavyState)
				heavyState = nil
			end
		end

		--------------------------------------------------------------------------------
		-- TPWALK
		--------------------------------------------------------------------------------
		local TPWalk = { Enabled = false, Speed = CONFIG.TPSpeedDefault }
		function TPWalk.set(on) TPWalk.Enabled = on end

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local function stepTPWalk(dt)
			local char = player.Character
			if not char then return end
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart")
			if not (humanoid and root) or humanoid.Health <= 0 or humanoid.SeatPart then return end

			local moveDir = humanoid.MoveDirection
			if moveDir.Magnitude < 0.01 then return end

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

			root.CFrame = root.CFrame + offset
		end

		--------------------------------------------------------------------------------
		-- PER-FRAME LOOPS
		--------------------------------------------------------------------------------
		RunService.Heartbeat:Connect(function(dt)
			local s = heavyState
			if s and s.active and s.force and s.root.Parent then
				s.force.Force = Vector3.new(0, -s.root.AssemblyMass * workspace.Gravity * CONFIG.ExtraGravity, 0)
			end
			if TPWalk.Enabled then stepTPWalk(dt) end
		end)

		player.CharacterAdded:Connect(function(char)
			releaseHeavy(heavyState)
			heavyState = nil
			if Heavy.Enabled then enableHeavy(char) end
		end)

		local function getMass()
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			return root and root.AssemblyMass or 0
		end

		--------------------------------------------------------------------------------
		-- GUI HELPERS & CREATION
		--------------------------------------------------------------------------------
		local function make(class, props, parent)
			local inst = Instance.new(class)
			for k, v in pairs(props) do inst[k] = v end
			inst.Parent = parent
			return inst
		end

		local function tween(inst, duration, goal, style, direction, delay)
			local t = TweenService:Create(inst, TweenInfo.new(
				duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out, 0, false, delay or 0
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

		for _, name in ipairs({ "DeadWeightGui", "CapriUtilGui" }) do
			local old = playerGui:FindFirstChild(name)
			if old then old:Destroy() end
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

		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, 0, 1, 0),
			Size = UDim2.fromOffset(40, 40),
			Rotation = 45,
			BackgroundColor3 = COLORS.Purple,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, panel)

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

		local HEADER_SIZE = UDim2.fromOffset(232, 40)
		local header = make("Frame", {
			Position = UDim2.fromOffset(-14, 14),
			Size = HEADER_SIZE,
			Rotation = -3,
			BackgroundColor3 = COLORS.Green,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, panel)
		make("Frame", {
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

			function self.render(on, animate)
				self.on = on
				local d = animate and 1 or 0
				tween(knob, 0.35 * d, { Position = on and KNOB_ON or KNOB_OFF, BackgroundColor3 = on and COLORS.Black or COLORS.Green }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				if animate then
					knob.Size = UDim2.fromOffset(34, 16)
					tween(knob, 0.45, { Size = UDim2.fromOffset(22, 22) }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
				end
				tween(track, 0.25 * d, { BackgroundColor3 = on and COLORS.Red or COLORS.Black })
				tween(trackStroke, 0.25 * d, { Color = on and COLORS.White or COLORS.Green })
				tween(accent, 0.3 * d, { Size = UDim2.new(0, on and 8 or 4, 1, 0), BackgroundColor3 = on and COLORS.Red or COLORS.Green }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				tween(label, 0.25 * d, { TextColor3 = on and COLORS.Red or COLORS.White })
				stateText.Text = on and "ON" or "OFF"
				stateText.TextXAlignment = on and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
				stateText.TextColor3 = on and COLORS.Black or COLORS.Green
			end

			card.Activated:Connect(function()
				ripple(card)
				onToggle()
			end)

			table.insert(entranceItems, { inst = card, rest = rest })
			return self
		end

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
			sliderValue.Text = string.format("+%.2f st/s", value)
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

		local visible = false
		local function setVisible(on)
			if visible == on then return end
			visible = on
			if on then
				tween(tab, 0.25, { Position = TAB_HIDDEN })
				tween(panel, 0.55, { Position = SHOWN }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			else
				tween(panel, 0.35, { Position = HIDDEN }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
				tween(tab, 0.3, { Position = TAB_SHOWN }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.25)
			end
		end

		closeBtn.Activated:Connect(function() setVisible(false) end)
		tab.Activated:Connect(function() setVisible(true) end)

		local heavyCard, tpCard
		heavyCard = makeToggleCard("HEAVY", "density 100 // gravity x3", 86, function()
			local on = not Heavy.Enabled
			Heavy.set(on)
			heavyCard.render(on, true)
		end)

		tpCard = makeToggleCard("TPWALK", "cframe nudge // ignores mass", 150, function()
			local on = not TPWalk.Enabled
			TPWalk.set(on)
			tpCard.render(on, true)
		end)

		RunService.RenderStepped:Connect(function(dt)
			if not visible then return end
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local vel = root and root.AssemblyLinearVelocity or Vector3.zero
			readout.Text = string.format("MASS %.0f  FALL %.0f  |  G T H", getMass(), math.max(0, -vel.Y))
		end)

		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then return end
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
		print("CapriUtil successfully loaded via executor!")
	end)

	if not success then
		warn("CapriUtil failed to load: " .. tostring(err))
	end
end)
