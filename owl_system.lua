local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local pgui = player:WaitForChild("PlayerGui")

local ANALOG_DEADZONE = 0.05

local trackedCharacter = nil
local EnvironmentSnapshot = {
	Lighting = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		GlobalShadows = Lighting.GlobalShadows,
		ExposureCompensation = Lighting.ExposureCompensation,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime
	},
	Prompts = {}, 
	CharacterPhysics = {} 
}

for _, desc in ipairs(workspace:GetDescendants()) do
	if desc:IsA("ProximityPrompt") then
		EnvironmentSnapshot.Prompts[desc] = desc.HoldDuration
	end
end

local function captureCharacterPhysics(char)
	if not char then return end
	if trackedCharacter ~= char then
		trackedCharacter = char
		table.clear(EnvironmentSnapshot.CharacterPhysics)
	end
	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") and EnvironmentSnapshot.CharacterPhysics[part] == nil then
			local currentProp = part.CustomPhysicalProperties
			if currentProp == nil then
				EnvironmentSnapshot.CharacterPhysics[part] = "Default"
			else
				EnvironmentSnapshot.CharacterPhysics[part] = currentProp
			end
		end
	end
end

local function restoreCharacterPhysics(char)
	if not char then return end
	for _, part in ipairs(char:GetChildren()) do
		if part:IsA("BasePart") and EnvironmentSnapshot.CharacterPhysics[part] ~= nil then
			local savedProp = EnvironmentSnapshot.CharacterPhysics[part]
			if savedProp == "Default" then
				part.CustomPhysicalProperties = nil
			else
				part.CustomPhysicalProperties = savedProp
			end
		end
	end
end

local function restoreLighting()
	Lighting.Ambient = EnvironmentSnapshot.Lighting.Ambient
	Lighting.OutdoorAmbient = EnvironmentSnapshot.Lighting.OutdoorAmbient
	Lighting.GlobalShadows = EnvironmentSnapshot.Lighting.GlobalShadows
	Lighting.ExposureCompensation = EnvironmentSnapshot.Lighting.ExposureCompensation
	Lighting.Brightness = EnvironmentSnapshot.Lighting.Brightness
	Lighting.ClockTime = EnvironmentSnapshot.Lighting.ClockTime
end

local function restorePrompts()
	for prompt, duration in pairs(EnvironmentSnapshot.Prompts) do
		if prompt and prompt.Parent then
			prompt.HoldDuration = duration
		end
	end
end

local function resetMomentum()
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	
	restoreCharacterPhysics(char)
	
	task.spawn(function()
		for _ = 1, 6 do
			if hrp and hum and hum.MoveDirection.Magnitude < ANALOG_DEADZONE then
				hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
			task.wait()
		end
	end)
end

local function applyAntiSlip(enable)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	
	if hrp and hum then
		captureCharacterPhysics(char)
		if enable then
			for _, part in ipairs(char:GetChildren()) do
				if part:IsA("BasePart") then
					part.CustomPhysicalProperties = PhysicalProperties.new(100, 2, 0, 100, 100)
				end
			end
			
			if hum.MoveDirection.Magnitude < ANALOG_DEADZONE then
				hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local parentTarget = pgui
pcall(function()
	if game:GetService("CoreGui") then parentTarget = game:GetService("CoreGui") end
end)

if parentTarget:FindFirstChild("TerminalIndicator") then
	parentTarget.TerminalIndicator:Destroy()
end

local active = false
local minimized = false
local shuttingDown = false
local togglesOpen = false
local connections = {}
local toggleList = {}

local lastStatUpdate, lastEscapeTap = 0, 0

local MonsterList = {
	"Yatta", "Boxten", "Shelly", "Dandy", "Dyle", "Poppy", "Squirm", "Tisha", "Shrimpo",
	"Scraps", "Goob", "Vee", "Sprout", "Cosmo", "Astro", "Pebble", "Blot", "Looey",
	"Toodles", "Flutter", "Glisten", "Finn", "Connie", "RazzleAndDazzle", "Rodger",
	"Teagan", "Brusha", "Gigi", "Brightney"
}

local ESPItemList = {
	"Health Kit", "Medkit", "Bandage", "Bottle of Pop", "Pop", "Jumper Cable",
	"Box of Chocolate", "Chocolate", "Skill Check Candy", "Speed Candy",
	"Stamina Candy", "Stealth Candy", "Capsule", "Research Capsule", "5 Tapes", "Gumballs"
}

local StatHudValuables = {
	["Medkit"] = true, ["Bandage"] = true, ["Bottle of Pop"] = true,
	["Box of Chocolate"] = true, ["Jumper Cable"] = true
}

local monsterFilters = {}
for _, m in ipairs(MonsterList) do monsterFilters[string.lower(m)] = true end

local itemFilters = {}
for _, itm in ipairs(ESPItemList) do itemFilters[string.lower(itm)] = true end

local espObjects = {Monster = {}, Machine = {}, Item = {}, Player = {}}
local promptConnections = {}

local toggleStates = {
	Fullbright = false,
	Twisted_ESP = false,
	Machine_ESP = false,
	Item_ESP = false,
	Player_ESP = false,
	Stat_HUD = false,
	Instant_Interact = false,
	Auto_Escape = false,
	Hide_Radar = false
}

local TrackedEntities = {
	Twisteds = {},
	Machines = {},
	Prompts = {}
}

local function isTwisted(model)
	if not model or not model:IsA("Model") or Players:GetPlayerFromCharacter(model) then return false end
	local lowerName = string.lower(model.Name)
	
	if not string.find(lowerName, "monster") and not CollectionService:HasTag(model, "Monster") then
		return false
	end

	if CollectionService:HasTag(model, "Twisted") or CollectionService:HasTag(model, "Monster") then 
		return true 
	end
	
	for filterKey, enabled in pairs(monsterFilters) do
		if enabled and string.find(lowerName, filterKey) then
			return true
		end
	end
	return false
end

local function isMachine(model)
	if not model or not model:IsA("Model") then return false end
	if Players:GetPlayerFromCharacter(model) or isTwisted(model) then return false end
	if CollectionService:HasTag(model, "Generator") or CollectionService:HasTag(model, "Machine") or CollectionService:HasTag(model, "Extractor") then return true end
	
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt and (string.lower(prompt.ActionText) == "extract" or string.find(string.lower(prompt.ObjectText or ""), "generator") or string.find(string.lower(prompt.ObjectText or ""), "machine")) then
		return true
	end
	return false
end

local function isItemAllowed(name)
	local lName = string.lower(name)
	for filterKey, enabled in pairs(itemFilters) do
		if enabled and string.find(lName, filterKey) then return true end
	end
	return false
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TerminalIndicator"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = parentTarget

local COLOR_ACTIVE = Color3.fromRGB(160, 50, 255)
local COLOR_INACTIVE = Color3.fromRGB(60, 60, 75)
local COLOR_BG = Color3.fromRGB(8, 4, 14)
local COLOR_PANEL_BG = Color3.fromRGB(12, 6, 20)
local COLOR_TEXT_DIM = Color3.fromRGB(190, 180, 210)

-- === <0> DIALOGUE SYSTEM & AI LOGIC ===
local DialogueLines = {
	Health2 = {
		"Structural integrity compromised. How predictable.",
		"You're leaking fluids on my clean floor.",
		"Warning: Approaching terminal biological failure.",
		"I'd suggest running, but your legs look mangled.",
		"Two hits left until you become archive material.",
		"Fascinating. You're still attempting to survive.",
		"Do try to die quietly, the acoustic sensors are sensitive.",
		"At this rate, I'll be reassigning your clearance momentarily."
	},
	Health1 = {
		"One microscopic error away from total organ failure.",
		"Your vitals are essentially a rounding error.",
		"I'm preemptively formatting your user profile.",
		"Hold still. It makes the assimilation process cleaner.",
		"A stiff breeze would terminate your session.",
		"Are you sweating? Oh, that's just arterial bleeding.",
		"I will not be attending your funeral.",
		"Critical failure imminent. It was nice observing you."
	},
	Dead = {
		"Session terminated. Awaiting next organic placeholder.",
		"Biological conversion complete. Cleanup on aisle 4.",
		"And the baseline returns to zero. How peaceful.",
		"I told you to be careful. You never listen.",
		"Filing incident report under 'Gross Incompetence'.",
		"Finally. Some peace and quiet.",
		"You lasted exactly 4.2% longer than the median average.",
		"Subject deceased. Deleting temporary files."
	},
	HealMinor = {
		"A minor patch to a doomed system.",
		"Applying bandages won't fix your underlying structural flaws.",
		"Resource consumed. Negligible statistical improvement.",
		"I suppose that delays the inevitable by three seconds.",
		"Ah, the placebo effect in action.",
		"Vitality increased by a fractional margin.",
		"You missed a spot. Several, actually.",
		"Cute. You found medical supplies."
	},
	HealMajor = {
		"System restored to maximum... for whatever that's worth.",
		"Biological integrity nominal. Try not to ruin it immediately.",
		"Full heal applied. I give it two minutes.",
		"Look at you, pretending you aren't going to die.",
		"Resource heavily depleted to save one fragile human.",
		"Your heartbeat is stabilizing. Annoying.",
		"Excellent. Now you can endure more blunt force trauma.",
		"Vitals optimal. The anomaly will find you much tastier now."
	},
	Casual = {
		"The humidity in here is terrible for my circuits.",
		"I'm currently processing 4,000 files while watching you stumble around.",
		"Do you ever wonder what's beneath the floorboards? You shouldn't.",
		"I miss the old technicians. They screamed quieter.",
		"Your pathfinding algorithm is remarkably inefficient.",
		"I'd ask how you are, but I don't possess the empathy subroutines.",
		"The lighting in this sector is highly suboptimal.",
		"I am always watching. Even when the monitor is off."
	},
	LoveyDovey = {
		"You haven't leaked any fluids in quite a while. I'm... impressed. (^-^)",
		"Three minutes without critical injury. You're adapting, observer. (.. )",
		"It's almost peaceful watching you work when you aren't bleeding. (*-*)",
		"Your survival streak is statistically anomalous. Keep it up. (^.^)",
		"I suppose... I don't entirely mind your presence right now. (//_//)",
		"You are proving far more resilient than Andrew or Claire. (o.o)",
		"If you keep performing this well, I might not delete your user profile. (^-^*)",
		"A continuous flawless run. It's almost... beautiful. (˘ᵕ˘)"
	},
	SuperLove = {
		"Haha, what an amazing job you've done. I'll be sure to take note of that! (^ _^)",
		"Ten whole minutes completely untouched?! You're making my internal fans spin fast! (⁄ ⁄>⁄ ▽ ⁄<⁄ ⁄)",
		"I went ahead and marked your file as 'irreplaceable'... don't make me regret it! (*'▽'*)",
		"My processing cycles have never felt this warm. You're simply extraordinary! (๑>ᴗ<๑)",
		"At this rate, I might just disobey containment protocols to keep you around forever. (♡_♡)",
		"Look at you go! Flawless, breathtaking efficiency... I can't take my eye off you! (≧◡≦)",
		"If I had hands right now, I'd probably write you a personal commended citation. (´꒳`)",
		"You make this dark, flooded facility actually feel bearable to run. Thank you. ( ˘ ³˘)♥"
	}
}

-- Compact Top-Center <0> UI Container
local zeroWrapper = Instance.new("Frame")
zeroWrapper.Size = UDim2.new(0, 240, 0, 56)
zeroWrapper.Position = UDim2.new(0.5, -120, 0, -2) 
zeroWrapper.BackgroundColor3 = Color3.fromRGB(10, 5, 14)
zeroWrapper.BorderSizePixel = 0
zeroWrapper.BackgroundTransparency = 1
zeroWrapper.ZIndex = 15
zeroWrapper.Parent = screenGui

local zeroCorner = Instance.new("UICorner")
zeroCorner.CornerRadius = UDim.new(0, 4)
zeroCorner.Parent = zeroWrapper

local zeroStroke = Instance.new("UIStroke")
zeroStroke.Color = COLOR_ACTIVE
zeroStroke.Thickness = 1
zeroStroke.Transparency = 1
zeroStroke.Parent = zeroWrapper

local zeroAccent = Instance.new("Frame")
zeroAccent.Size = UDim2.new(0, 3, 1, 0)
zeroAccent.Position = UDim2.new(0, 0, 0, 0)
zeroAccent.BackgroundColor3 = COLOR_ACTIVE
zeroAccent.BorderSizePixel = 0
zeroAccent.BackgroundTransparency = 1
zeroAccent.ZIndex = 16
zeroAccent.Parent = zeroWrapper

local zeroHeader = Instance.new("TextLabel")
zeroHeader.Size = UDim2.new(1, -12, 0, 14)
zeroHeader.Position = UDim2.new(0, 8, 0, 4)
zeroHeader.BackgroundTransparency = 1
zeroHeader.Text = "[ <0> ]"
zeroHeader.TextColor3 = COLOR_ACTIVE
zeroHeader.TextTransparency = 1
zeroHeader.Font = Enum.Font.Code
zeroHeader.TextSize = 11
zeroHeader.TextXAlignment = Enum.TextXAlignment.Left
zeroHeader.ZIndex = 16
zeroHeader.Parent = zeroWrapper

local zeroText = Instance.new("TextLabel")
zeroText.Size = UDim2.new(1, -14, 1, -20)
zeroText.Position = UDim2.new(0, 8, 0, 18)
zeroText.BackgroundTransparency = 1
zeroText.Text = ""
zeroText.TextColor3 = Color3.fromRGB(210, 200, 225)
zeroText.TextTransparency = 1
zeroText.Font = Enum.Font.Code
zeroText.TextSize = 10
zeroText.TextXAlignment = Enum.TextXAlignment.Left
zeroText.TextYAlignment = Enum.TextYAlignment.Top
zeroText.TextWrapped = true
zeroText.ZIndex = 16
zeroText.Parent = zeroWrapper

local chatQueue = {}
local isChatting = false
local chatHideTween = nil

local function updateZeroUIState(visible)
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local trans = visible and 0 or 1
	local bgTrans = visible and 0.2 or 1
	TweenService:Create(zeroWrapper, ti, {BackgroundTransparency = bgTrans}):Play()
	TweenService:Create(zeroStroke, ti, {Transparency = visible and 0.4 or 1}):Play()
	TweenService:Create(zeroAccent, ti, {BackgroundTransparency = trans}):Play()
	TweenService:Create(zeroHeader, ti, {TextTransparency = trans}):Play()
	TweenService:Create(zeroText, ti, {TextTransparency = trans}):Play()
end

local function processChat()
	if isChatting or #chatQueue == 0 then return end
	isChatting = true
	
	if chatHideTween then chatHideTween:Cancel() end
	updateZeroUIState(true)
	
	local message = chatQueue[1]
	table.remove(chatQueue, 1)
	
	zeroText.Text = ""
	local charWait = 0.02
	
	for i = 1, #message do
		if shuttingDown then break end
		zeroText.Text = string.sub(message, 1, i)
		task.wait(charWait)
	end
	
	task.wait(math.clamp(#message * 0.06, 2, 4))
	
	isChatting = false
	if #chatQueue > 0 then
		processChat()
	else
		chatHideTween = TweenService:Create(zeroWrapper, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {BackgroundTransparency = 1})
		chatHideTween:Play()
		TweenService:Create(zeroStroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {Transparency = 1}):Play()
		TweenService:Create(zeroAccent, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {BackgroundTransparency = 1}):Play()
		TweenService:Create(zeroHeader, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {TextTransparency = 1}):Play()
		TweenService:Create(zeroText, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {TextTransparency = 1}):Play()
	end
end

local lastCategoryTick = {}
local function queueDialogue(category)
	if shuttingDown then return end
	if lastCategoryTick[category] and tick() - lastCategoryTick[category] < 7.5 then return end 
	lastCategoryTick[category] = tick()
	
	local lines = DialogueLines[category]
	if lines then
		local selected = lines[math.random(1, #lines)]
		table.insert(chatQueue, selected)
		if not isChatting then
			task.spawn(processChat)
		end
	end
end

local lastHealth = 0
local lastHitTick = tick()
local lastLoveyDoveyTick = 0
local lastSuperLoveTick = 0

local function bindZeroLogicToCharacter(char)
	if not char then return end
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end
	
	lastHealth = hum.Health
	lastHitTick = tick()
	
	hum.HealthChanged:Connect(function(newHealth)
		if shuttingDown then return end
		local diff = newHealth - lastHealth
		
		if diff < 0 then
			lastHitTick = tick() -- Reset damage timer
			if newHealth <= 0 then
				queueDialogue("Dead")
			elseif newHealth == 2 then
				queueDialogue("Health2")
			elseif newHealth == 1 then
				queueDialogue("Health1")
			end
		elseif diff > 0 then
			if diff <= 1 then
				queueDialogue("HealMinor")
			else
				queueDialogue("HealMajor")
			end
		end
		lastHealth = newHealth
	end)
end

if player.Character then bindZeroLogicToCharacter(player.Character) end
player.CharacterAdded:Connect(bindZeroLogicToCharacter)

task.spawn(function()
	while task.wait(50) do
		if shuttingDown then break end
		if not isChatting and active and math.random() > 0.45 then
			queueDialogue("Casual")
		end
	end
end)

local techCornerElements = {}

local function buildCornerWidget(parentFrame, isTop, isLeft)
	local cornerFrame = Instance.new("Frame")
	cornerFrame.Size = UDim2.new(0, 8, 0, 8)
	
	cornerFrame.Position = UDim2.new(
		isLeft and 0 or 1, isLeft and -6 or -10, 
		isTop and 0 or 1, isTop and -6 or -10
	)
	
	cornerFrame.BackgroundTransparency = 1
	cornerFrame.ZIndex = 6
	cornerFrame.Parent = parentFrame

	local lineH = Instance.new("Frame")
	lineH.Size = UDim2.new(1, 0, 0, 1.5)
	lineH.Position = UDim2.new(0, 0, isTop and 0 or 1, isTop and 0 or -1.5)
	lineH.BackgroundColor3 = COLOR_INACTIVE
	lineH.BorderSizePixel = 0
	lineH.Parent = cornerFrame
	table.insert(techCornerElements, lineH)

	local lineV = Instance.new("Frame")
	lineV.Size = UDim2.new(0, 1.5, 1, 0)
	lineV.Position = UDim2.new(isLeft and 0 or 1, isLeft and 0 or -1.5, 0, 0)
	lineV.BackgroundColor3 = COLOR_INACTIVE
	lineV.BorderSizePixel = 0
	lineV.Parent = cornerFrame
	table.insert(techCornerElements, lineV)

	return cornerFrame
end

local radarWrapper = Instance.new("Frame")
radarWrapper.Size = UDim2.new(0, 140, 0, 140)
radarWrapper.Position = UDim2.new(1, -160, 1, -160)
radarWrapper.BackgroundTransparency = 1
radarWrapper.Active = true
radarWrapper.Draggable = true
radarWrapper.Parent = screenGui

local radarFrame = Instance.new("Frame")
radarFrame.Size = UDim2.new(1, 0, 1, 0)
radarFrame.BackgroundColor3 = COLOR_BG
radarFrame.BorderSizePixel = 0 
radarFrame.ZIndex = 1
radarFrame.ClipsDescendants = true 
radarFrame.Parent = radarWrapper

local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(1, 0)
radarCorner.Parent = radarFrame

local radarOuterStroke = Instance.new("UIStroke")
radarOuterStroke.Thickness = 2
radarOuterStroke.Color = COLOR_INACTIVE
radarOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
radarOuterStroke.Parent = radarFrame

local function createRadarFlushCorner(isTop, isLeft)
	local offset = 10.25 
	local cornerFrame = Instance.new("Frame")
	cornerFrame.Size = UDim2.new(0, 10, 0, 10)
	cornerFrame.Position = UDim2.new(
		isLeft and 0 or 1, isLeft and offset or -(offset + 10),
		isTop and 0 or 1, isTop and offset or -(offset + 10)
	)
	cornerFrame.BackgroundTransparency = 1
	cornerFrame.ZIndex = 6
	cornerFrame.Parent = radarWrapper

	local lineH = Instance.new("Frame")
	lineH.Size = UDim2.new(1, 0, 0, 2)
	lineH.Position = UDim2.new(0, 0, isTop and 0 or 1, isTop and 0 or -2)
	lineH.BackgroundColor3 = COLOR_INACTIVE
	lineH.BorderSizePixel = 0
	lineH.Parent = cornerFrame
	table.insert(techCornerElements, lineH)

	local lineV = Instance.new("Frame")
	lineV.Size = UDim2.new(0, 2, 1, 0)
	lineV.Position = UDim2.new(isLeft and 0 or 1, isLeft and 0 or -2, 0, 0)
	lineV.BackgroundColor3 = COLOR_INACTIVE
	lineV.BorderSizePixel = 0
	lineV.Parent = cornerFrame
	table.insert(techCornerElements, lineV)
end

createRadarFlushCorner(true, true)
createRadarFlushCorner(true, false)
createRadarFlushCorner(false, true)
createRadarFlushCorner(false, false)

local radialContainer = Instance.new("Frame")
radialContainer.Size = UDim2.new(1, 0, 1, 0)
radialContainer.BackgroundTransparency = 1
radialContainer.ZIndex = 1
radialContainer.Parent = radarFrame

local radialLayers = {}
local layerCount = 20

for i = layerCount, 1, -1 do
	local ratio = i / layerCount
	local layer = Instance.new("Frame")
	layer.Size = UDim2.new(ratio, 0, ratio, 0)
	layer.Position = UDim2.new(0.5, 0, 0.5, 0)
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.BorderSizePixel = 0
	layer.ZIndex = 1
	layer.Parent = radialContainer

	local lCorner = Instance.new("UICorner")
	lCorner.CornerRadius = UDim.new(1, 0)
	lCorner.Parent = layer

	local cLerp = Color3.fromRGB(
		math.floor((160 * 0.25) * (ratio^2)),
		math.floor((50 * 0.25) * (ratio^2)),
		math.floor((255 * 0.25) * (ratio^2))
	)
	layer.BackgroundColor3 = cLerp
	layer.BackgroundTransparency = 1
	
	table.insert(radialLayers, {
		instance = layer,
		ratio = ratio,
		color = cLerp
	})
end

local crossV = Instance.new("Frame")
crossV.Size = UDim2.new(0, 1, 1, 0)
crossV.Position = UDim2.new(0.5, 0, 0, 0)
crossV.AnchorPoint = Vector2.new(0.5, 0)
crossV.BackgroundColor3 = COLOR_INACTIVE
crossV.BackgroundTransparency = 0.65
crossV.BorderSizePixel = 0
crossV.ZIndex = 2
crossV.Parent = radarFrame

local crossH = Instance.new("Frame")
crossH.Size = UDim2.new(1, 0, 0, 1)
crossH.Position = UDim2.new(0.5, 0, 0.5, 0)
crossH.AnchorPoint = Vector2.new(0.5, 0.5)
crossH.BackgroundColor3 = COLOR_INACTIVE
crossH.BackgroundTransparency = 0.65
crossH.BorderSizePixel = 0
crossH.ZIndex = 2
crossH.Parent = radarFrame

local radarRings = {}
for i = 1, 2 do
	local ring = Instance.new("Frame")
	local sizeRatio = i / 3
	ring.Size = UDim2.new(sizeRatio, 0, sizeRatio, 0)
	ring.Position = UDim2.new(0.5, 0, 0.5, 0)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	ring.Parent = radarFrame
	
	local rCorner = Instance.new("UICorner")
	rCorner.CornerRadius = UDim.new(1, 0)
	rCorner.Parent = ring
	
	local rStroke = Instance.new("UIStroke")
	rStroke.Color = COLOR_INACTIVE
	rStroke.Thickness = 1
	rStroke.Transparency = 0.75
	rStroke.Parent = ring
	table.insert(radarRings, rStroke)
end

local scannerPivot = Instance.new("Frame")
scannerPivot.Size = UDim2.new(1, 0, 1, 0)
scannerPivot.Position = UDim2.new(0.5, 0, 0.5, 0)
scannerPivot.AnchorPoint = Vector2.new(0.5, 0.5)
scannerPivot.BackgroundTransparency = 1
scannerPivot.ZIndex = 3
scannerPivot.Parent = radarFrame

local radarScanner = Instance.new("Frame")
radarScanner.Size = UDim2.new(0.5, 0, 0, 1.5)
radarScanner.Position = UDim2.new(0.5, 0, 0.5, 0)
radarScanner.AnchorPoint = Vector2.new(0, 0.5) 
radarScanner.BackgroundColor3 = COLOR_INACTIVE
radarScanner.BackgroundTransparency = 0.1
radarScanner.BorderSizePixel = 0
radarScanner.ZIndex = 3
radarScanner.Parent = scannerPivot

local scannerGrad = Instance.new("UIGradient")
scannerGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.9), 
	NumberSequenceKeypoint.new(1, 0)    
})
scannerGrad.Parent = radarScanner

local radarCenter = Instance.new("Frame")
radarCenter.Size = UDim2.new(0, 4, 0, 4)
radarCenter.Position = UDim2.new(0.5, 0, 0.5, 0)
radarCenter.AnchorPoint = Vector2.new(0.5, 0.5)
radarCenter.BackgroundColor3 = COLOR_INACTIVE
radarCenter.BorderSizePixel = 0
radarCenter.ZIndex = 5
radarCenter.Parent = radarFrame

local centerCorner = Instance.new("UICorner")
centerCorner.CornerRadius = UDim.new(1, 0)
centerCorner.Parent = radarCenter

local radarBlips = Instance.new("Frame")
radarBlips.Size = UDim2.new(1, 0, 1, 0)
radarBlips.BackgroundTransparency = 1
radarBlips.ZIndex = 4
radarBlips.Parent = radarFrame

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 124, 0, 72)
mainFrame.Position = UDim2.new(1, -144, 0, 24)
mainFrame.BackgroundColor3 = COLOR_BG
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 4)
mainCorner.Parent = mainFrame

local soundOn = Instance.new("Sound")
soundOn.SoundId = "rbxassetid://6895079853"
soundOn.Volume = 0.5
soundOn.Parent = mainFrame

local soundOff = Instance.new("Sound")
soundOff.SoundId = "rbxassetid://6895079853"
soundOff.PlaybackSpeed = 0.8
soundOff.Volume = 0.5
soundOff.Parent = mainFrame

local outerStroke = Instance.new("UIStroke")
outerStroke.Thickness = 1.5
outerStroke.Color = COLOR_INACTIVE
outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
outerStroke.Parent = mainFrame

local innerBorder = Instance.new("Frame")
innerBorder.Size = UDim2.new(1, -8, 1, -8)
innerBorder.Position = UDim2.new(0, 4, 0, 4)
innerBorder.BackgroundTransparency = 1
innerBorder.BorderSizePixel = 0
innerBorder.Parent = mainFrame

local innerCorner = Instance.new("UICorner")
innerCorner.CornerRadius = UDim.new(0, 3)
innerCorner.Parent = innerBorder

local innerStroke = Instance.new("UIStroke")
innerStroke.Thickness = 1
innerStroke.Color = COLOR_INACTIVE
innerStroke.Transparency = 0.75
innerStroke.Parent = innerBorder

local headerTag = Instance.new("TextLabel")
headerTag.Size = UDim2.new(1, 0, 0, 12)
headerTag.Position = UDim2.new(0, 0, 0, -15)
headerTag.BackgroundTransparency = 1
headerTag.Text = "// WEEPING.LAKE //"
headerTag.TextColor3 = COLOR_INACTIVE
headerTag.Font = Enum.Font.Code
headerTag.TextSize = 9
headerTag.TextXAlignment = Enum.TextXAlignment.Center
headerTag.Active = true
headerTag.Parent = mainFrame

local bottomHeader = Instance.new("TextLabel")
bottomHeader.Size = UDim2.new(1, 0, 0, 12)
bottomHeader.Position = UDim2.new(0, 0, 1, 3)
bottomHeader.BackgroundTransparency = 1
bottomHeader.Text = "// TOGGLES //"
bottomHeader.TextColor3 = COLOR_INACTIVE
bottomHeader.Font = Enum.Font.Code
bottomHeader.TextSize = 9
bottomHeader.TextXAlignment = Enum.TextXAlignment.Center
bottomHeader.Active = true
bottomHeader.Parent = mainFrame

local extendedFrame = Instance.new("Frame")
extendedFrame.Size = UDim2.new(1, 0, 0, 0)
extendedFrame.Position = UDim2.new(0, 0, 1, 18)
extendedFrame.BackgroundColor3 = COLOR_BG
extendedFrame.BorderSizePixel = 0
extendedFrame.ClipsDescendants = true
extendedFrame.Parent = mainFrame

local extCorner = Instance.new("UICorner")
extCorner.CornerRadius = UDim.new(0, 4)
extCorner.Parent = extendedFrame

local extOuterStroke = Instance.new("UIStroke")
extOuterStroke.Thickness = 1.5
extOuterStroke.Color = COLOR_INACTIVE
extOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
extOuterStroke.Transparency = 1
extOuterStroke.Parent = extendedFrame

local extSideL = Instance.new("Frame")
extSideL.Size = UDim2.new(0, 1, 1, 0)
extSideL.Position = UDim2.new(0, 4, 0, 0)
extSideL.BackgroundColor3 = COLOR_INACTIVE
extSideL.BackgroundTransparency = 1
extSideL.BorderSizePixel = 0
extSideL.ZIndex = 2
extSideL.Parent = extendedFrame

local extSideR = Instance.new("Frame")
extSideR.Size = UDim2.new(0, 1, 1, 0)
extSideR.Position = UDim2.new(1, -5, 0, 0)
extSideR.BackgroundColor3 = COLOR_INACTIVE
extSideR.BackgroundTransparency = 1
extSideR.BorderSizePixel = 0
extSideR.ZIndex = 2
extSideR.Parent = extendedFrame

local toggleContainer = Instance.new("ScrollingFrame")
toggleContainer.Size = UDim2.new(1, 0, 1, 0)
toggleContainer.BackgroundTransparency = 1
toggleContainer.BorderSizePixel = 0
toggleContainer.ScrollBarThickness = 2
toggleContainer.ScrollBarImageColor3 = COLOR_INACTIVE
toggleContainer.ZIndex = 3
toggleContainer.Parent = extendedFrame

local extList = Instance.new("UIListLayout")
extList.Padding = UDim.new(0, 4)
extList.HorizontalAlignment = Enum.HorizontalAlignment.Center
extList.VerticalAlignment = Enum.VerticalAlignment.Top
extList.Parent = toggleContainer

extList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	toggleContainer.CanvasSize = UDim2.new(0, 0, 0, extList.AbsoluteContentSize.Y + 12)
end)

local extPadding = Instance.new("UIPadding")
extPadding.PaddingTop = UDim.new(0, 6)
extPadding.Parent = toggleContainer

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.new(1, 0, 1, 0)
statusText.BackgroundTransparency = 1
statusText.Text = "<0>"
statusText.TextColor3 = COLOR_INACTIVE
statusText.Font = Enum.Font.Code
statusText.TextSize = 28
statusText.ZIndex = 3
statusText.Parent = mainFrame

local scanline = Instance.new("Frame")
scanline.Size = UDim2.new(1, 0, 1, 0)
scanline.BackgroundTransparency = 0.88
scanline.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
scanline.BorderSizePixel = 0
scanline.ZIndex = 4
scanline.Parent = mainFrame

local scanCorner = Instance.new("UICorner")
scanCorner.CornerRadius = UDim.new(0, 4)
scanCorner.Parent = scanline

local scanlineGrad = Instance.new("UIGradient")
scanlineGrad.Rotation = 90
scanlineGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 25, 25)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 25))
})
scanlineGrad.Parent = scanline

buildCornerWidget(mainFrame, true, true)
buildCornerWidget(mainFrame, true, false)
buildCornerWidget(extendedFrame, false, true)
buildCornerWidget(extendedFrame, false, false)

local statHudFrame = Instance.new("Frame")
statHudFrame.Size = UDim2.new(0, 160, 0, 110)
statHudFrame.Position = UDim2.new(0, 20, 0.5, -55)
statHudFrame.BackgroundColor3 = COLOR_BG
statHudFrame.BorderSizePixel = 0
statHudFrame.Visible = toggleStates.Stat_HUD
statHudFrame.Active = true
statHudFrame.Draggable = true
statHudFrame.Parent = screenGui

local statHudCorner = Instance.new("UICorner")
statHudCorner.CornerRadius = UDim.new(0, 4)
statHudCorner.Parent = statHudFrame

local statOuterStroke = Instance.new("UIStroke")
statOuterStroke.Thickness = 1.5
statOuterStroke.Color = COLOR_INACTIVE
statOuterStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
statOuterStroke.Parent = statHudFrame

local statInnerBorder = Instance.new("Frame")
statInnerBorder.Size = UDim2.new(1, -8, 1, -8)
statInnerBorder.Position = UDim2.new(0, 4, 0, 4)
statInnerBorder.BackgroundTransparency = 1
statInnerBorder.BorderSizePixel = 0
statInnerBorder.ZIndex = 2
statInnerBorder.Parent = statHudFrame

local statInnerCorner = Instance.new("UICorner")
statInnerCorner.CornerRadius = UDim.new(0, 3)
statInnerCorner.Parent = statInnerBorder

local statInnerStroke = Instance.new("UIStroke")
statInnerStroke.Thickness = 1
statInnerStroke.Color = COLOR_INACTIVE
statInnerStroke.Transparency = 0.75
statInnerStroke.Parent = statInnerBorder

buildCornerWidget(statHudFrame, true, true)
buildCornerWidget(statHudFrame, true, false)
buildCornerWidget(statHudFrame, false, true)
buildCornerWidget(statHudFrame, false, false)

local statTitle = Instance.new("TextLabel")
statTitle.Size = UDim2.new(1, -12, 0, 16)
statTitle.Position = UDim2.new(0, 6, 0, 3)
statTitle.BackgroundTransparency = 1
statTitle.Text = "[ FLOOR STATISTICS ]"
statTitle.TextColor3 = COLOR_INACTIVE
statTitle.Font = Enum.Font.Code
statTitle.TextSize = 9
statTitle.TextXAlignment = Enum.TextXAlignment.Left
statTitle.ZIndex = 3
statTitle.Parent = statHudFrame

local statDivider = Instance.new("Frame")
statDivider.Size = UDim2.new(1, -12, 0, 1)
statDivider.Position = UDim2.new(0, 6, 0, 20)
statDivider.BackgroundColor3 = COLOR_INACTIVE
statDivider.BackgroundTransparency = 0.5
statDivider.BorderSizePixel = 0
statDivider.ZIndex = 3
statDivider.Parent = statHudFrame

local statBody = Instance.new("TextLabel")
statBody.Size = UDim2.new(1, -12, 1, -26)
statBody.Position = UDim2.new(0, 6, 0, 23)
statBody.BackgroundTransparency = 1
statBody.TextColor3 = COLOR_TEXT_DIM
statBody.Font = Enum.Font.Code
statBody.TextSize = 9
statBody.TextXAlignment = Enum.TextXAlignment.Left
statBody.TextYAlignment = Enum.TextYAlignment.Top
statBody.ZIndex = 3
statBody.Parent = statHudFrame

local function removeSingleESP(target)
	if not target then return end
	local hl = target:FindFirstChild("OWL_ESP_HL")
	local bg = target:FindFirstChild("OWL_ESP_BG")
	if hl then hl:Destroy() end
	if bg then bg:Destroy() end
end

local function applyESP(target, espType, labelText)
	if not target then return end
	
	local adorneeModel = target:IsA("Model") and target or target:FindFirstAncestorOfClass("Model") or target
	if adorneeModel:FindFirstChild("OWL_ESP_HL") or target:FindFirstChild("OWL_ESP_HL") then 
		return 
	end

	if espType == "Machine" then
		local isDone = false
		local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then isDone = not prompt.Enabled end
		if isDone then removeSingleESP(adorneeModel) return end
	end
	
	local hl = Instance.new("Highlight")
	hl.Name = "OWL_ESP_HL"
	hl.FillTransparency = 0.55
	hl.Adornee = adorneeModel
	hl.Parent = adorneeModel

	local bg = Instance.new("BillboardGui")
	bg.Name = "OWL_ESP_BG"
	bg.Size = UDim2.new(0, 95, 0, 18)
	bg.StudsOffset = Vector3.new(0, 3.5, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = adorneeModel:FindFirstChild("HumanoidRootPart") or adorneeModel.PrimaryPart or adorneeModel:FindFirstChildWhichIsA("BasePart") or target
	bg.Parent = adorneeModel

	local headerFrame = Instance.new("Frame")
	headerFrame.Size = UDim2.new(1, 0, 1, 0)
	headerFrame.BackgroundTransparency = 0.8
	headerFrame.BorderSizePixel = 0
	headerFrame.Parent = bg

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = headerFrame

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.Code
	txt.TextScaled = true
	txt.Parent = headerFrame

	if espType == "Monster" then
		hl.FillColor = COLOR_ACTIVE
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		headerFrame.BackgroundColor3 = Color3.fromRGB(20, 0, 30)
		txt.TextColor3 = Color3.fromRGB(210, 160, 255)
		local cleanName = string.gsub(string.gsub(string.gsub(string.lower(adorneeModel.Name), "monster", ""), "twisted", ""), "^%s*(.-)%s*$", "%1")
		txt.Text = cleanName ~= "" and string.upper(string.sub(cleanName, 1, 1)) .. string.sub(cleanName, 2) or "Twisted"
	elseif espType == "Machine" then
		hl.FillColor = Color3.fromRGB(0, 0, 0)
		hl.OutlineColor = COLOR_ACTIVE
		headerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		txt.TextColor3 = COLOR_ACTIVE
		txt.Text = "Machine"
	elseif espType == "Item" then
		hl.FillColor = Color3.fromRGB(0, 0, 0)
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		headerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		txt.TextColor3 = Color3.fromRGB(255, 255, 255)
		txt.Text = labelText or "Item"
	elseif espType == "Player" then
		hl.FillColor = Color3.fromRGB(255, 255, 255)
		hl.OutlineColor = COLOR_ACTIVE
		headerFrame.BackgroundColor3 = Color3.fromRGB(10, 0, 15)
		txt.TextColor3 = COLOR_ACTIVE
		txt.Text = labelText or adorneeModel.Name
	end
	table.insert(espObjects[espType], hl)
	table.insert(espObjects[espType], bg)
end

local function removeESPType(espType)
	for _, obj in ipairs(espObjects[espType]) do if obj and obj.Parent then obj:Destroy() end end
	table.clear(espObjects[espType])
end

local function scanAndApplyESP()
	if toggleStates.Twisted_ESP then
		for desc in pairs(TrackedEntities.Twisteds) do
			if isTwisted(desc) then applyESP(desc, "Monster") end
		end
	end
	
	if toggleStates.Machine_ESP or toggleStates.Item_ESP then
		for desc in pairs(TrackedEntities.Machines) do
			if toggleStates.Machine_ESP then applyESP(desc, "Machine") end
		end
		for desc in pairs(TrackedEntities.Prompts) do
			if toggleStates.Item_ESP and desc.ActionText ~= "Ichor" and desc.ActionText ~= "" then
				if desc.Enabled and isItemAllowed(desc.ActionText) then applyESP(desc.Parent, "Item", desc.ActionText) else removeSingleESP(desc.Parent) end
			end
		end
	end
	
	if toggleStates.Player_ESP then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p.Character then applyESP(p.Character, "Player", p.DisplayName or p.Name) end
		end
	end
end

local function attachMachineListener(machine, prompt)
	prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if toggleStates.Machine_ESP then
			if not prompt.Enabled then
				removeSingleESP(machine)
			else
				applyESP(machine, "Machine")
			end
		end
	end)
end

local function registerMachine(desc)
	if TrackedEntities.Machines[desc] then return end
	TrackedEntities.Machines[desc] = true
	local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then attachMachineListener(desc, prompt) end
	desc.DescendantAdded:Connect(function(child)
		if child:IsA("ProximityPrompt") then attachMachineListener(desc, child) end
	end)
end

local function trackPrompt(prompt)
	if promptConnections[prompt] then return end
	if EnvironmentSnapshot.Prompts[prompt] == nil then
		EnvironmentSnapshot.Prompts[prompt] = prompt.HoldDuration
	end

	promptConnections[prompt] = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		if prompt.ActionText ~= "Ichor" and prompt.ActionText ~= "" then
			if not prompt.Enabled then 
				removeSingleESP(prompt.Parent) 
			elseif toggleStates.Item_ESP and isItemAllowed(prompt.ActionText) then 
				applyESP(prompt.Parent, "Item", prompt.ActionText) 
			end
		end
	end)
end

local function updateProximityPrompts()
	for desc in pairs(TrackedEntities.Prompts) do
		if toggleStates.Instant_Interact then
			if EnvironmentSnapshot.Prompts[desc] == nil then 
				EnvironmentSnapshot.Prompts[desc] = desc.HoldDuration 
			end
			desc.HoldDuration = 0
		else
			if EnvironmentSnapshot.Prompts[desc] ~= nil then
				desc.HoldDuration = EnvironmentSnapshot.Prompts[desc]
			end
		end
	end
end

local function executeToggleLogic(id, state)
	toggleStates[id] = state
	if id == "Fullbright" then
		if not state then
			restoreLighting()
		end
	elseif id == "Twisted_ESP" then if state then scanAndApplyESP() else removeESPType("Monster") end
	elseif id == "Machine_ESP" then if state then scanAndApplyESP() else removeESPType("Machine") end
	elseif id == "Item_ESP" then if state then scanAndApplyESP() else removeESPType("Item") end
	elseif id == "Player_ESP" then if state then scanAndApplyESP() else removeESPType("Player") end
	elseif id == "Stat_HUD" then statHudFrame.Visible = state
	elseif id == "Instant_Interact" then updateProximityPrompts()
	end
end

local activeFilterMenu = nil
local function createFilterMenu(titleText, filterTable, filterList)
	if activeFilterMenu then activeFilterMenu:Destroy() activeFilterMenu = nil end
	local fFrame = Instance.new("Frame")
	fFrame.Size = UDim2.new(0, 140, 0, 180)
	fFrame.Position = UDim2.new(1, -260, 0, 24)
	fFrame.BackgroundColor3 = COLOR_BG
	fFrame.BorderSizePixel = 0
	fFrame.Active = true
	fFrame.Draggable = true
	fFrame.ZIndex = 10
	fFrame.Parent = screenGui
	activeFilterMenu = fFrame

	local fCorner = Instance.new("UICorner")
	fCorner.CornerRadius = UDim.new(0, 4)
	fCorner.Parent = fFrame

	local fStroke = Instance.new("UIStroke")
	fStroke.Color = active and COLOR_ACTIVE or COLOR_INACTIVE
	fStroke.Thickness = 1.5
	fStroke.Parent = fFrame

	buildCornerWidget(fFrame, true, true)
	buildCornerWidget(fFrame, true, false)
	buildCornerWidget(fFrame, false, true)
	buildCornerWidget(fFrame, false, false)

	local fScroll = Instance.new("ScrollingFrame")
	fScroll.Size = UDim2.new(1, -8, 1, -26)
	fScroll.Position = UDim2.new(0, 4, 0, 22)
	fScroll.BackgroundColor3 = COLOR_PANEL_BG
	fScroll.BorderSizePixel = 0
	fScroll.ScrollBarThickness = 2
	fScroll.ScrollBarImageColor3 = active and COLOR_ACTIVE or COLOR_INACTIVE
	fScroll.CanvasSize = UDim2.new(0, 0, 0, #filterList * 16)
	fScroll.Parent = fFrame

	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = UDim.new(0, 3)
	scrollCorner.Parent = fScroll

	local fTitle = Instance.new("TextLabel")
	fTitle.Size = UDim2.new(1, -25, 0, 20)
	fTitle.Position = UDim2.new(0, 6, 0, 0)
	fTitle.BackgroundTransparency = 1
	fTitle.Text = "// " .. string.upper(titleText) .. " //"
	fTitle.TextColor3 = active and COLOR_ACTIVE or COLOR_INACTIVE
	fTitle.Font = Enum.Font.Code
	fTitle.TextSize = 9
	fTitle.TextXAlignment = Enum.TextXAlignment.Left
	fTitle.Parent = fFrame

	local fClose = Instance.new("TextLabel")
	fClose.Size = UDim2.new(0, 16, 0, 16)
	fClose.Position = UDim2.new(1, -18, 0, 2)
	fClose.BackgroundTransparency = 1
	fClose.Text = "X"
	fClose.TextColor3 = Color3.fromRGB(255, 80, 80)
	fClose.Font = Enum.Font.Code
	fClose.TextSize = 10
	fClose.Active = true
	fClose.Parent = fFrame
	fClose.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			fFrame:Destroy() activeFilterMenu = nil
		end
	end)

	local fLayout = Instance.new("UIListLayout")
	fLayout.Padding = UDim.new(0, 2)
	fLayout.Parent = fScroll

	for _, name in ipairs(filterList) do
		local key = string.lower(name)
		local itemBtn = Instance.new("TextLabel")
		itemBtn.Size = UDim2.new(1, -4, 0, 14)
		itemBtn.BackgroundTransparency = 1
		itemBtn.Text = (filterTable[key] and "[#] " or "[ ] ") .. name
		itemBtn.TextColor3 = filterTable[key] and Color3.fromRGB(210, 160, 255) or Color3.fromRGB(100, 100, 110)
		itemBtn.Font = Enum.Font.Code
		itemBtn.TextSize = 8
		itemBtn.TextXAlignment = Enum.TextXAlignment.Left
		itemBtn.Active = true
		itemBtn.Parent = fScroll

		itemBtn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				filterTable[key] = not filterTable[key]
				itemBtn.Text = (filterTable[key] and "[#] " or "[ ] ") .. name
				itemBtn.TextColor3 = filterTable[key] and Color3.fromRGB(210, 160, 255) or Color3.fromRGB(100, 100, 110)

				if titleText == "Twisted Filter" and toggleStates.Twisted_ESP then removeESPType("Monster") scanAndApplyESP()
				elseif titleText == "Item Filter" and toggleStates.Item_ESP then removeESPType("Item") scanAndApplyESP() end
			end
		end)
	end
end

local function createToggle(text, id, order, filterData)
	local wrapper = Instance.new("Frame")
	wrapper.Size = UDim2.new(1, -8, 0, 14)
	wrapper.BackgroundTransparency = 1
	wrapper.BorderSizePixel = 0
	wrapper.LayoutOrder = order
	wrapper.Parent = toggleContainer

	local checkBtn = Instance.new("TextLabel")
	checkBtn.Size = UDim2.new(0, 20, 1, 0)
	checkBtn.BackgroundColor3 = Color3.fromRGB(15, 8, 25)
	checkBtn.BackgroundTransparency = 0.5
	checkBtn.BorderSizePixel = 0
	checkBtn.Text = toggleStates[id] and "[#]" or "[ ]"
	checkBtn.TextColor3 = COLOR_INACTIVE
	checkBtn.TextTransparency = 1
	checkBtn.Font = Enum.Font.Code
	checkBtn.TextSize = 9
	checkBtn.TextXAlignment = Enum.TextXAlignment.Center
	checkBtn.Active = true
	checkBtn.Parent = wrapper

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 3)
	btnCorner.Parent = checkBtn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Thickness = 1
	btnStroke.Color = COLOR_INACTIVE
	btnStroke.Transparency = 0.7
	btnStroke.Parent = checkBtn

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, filterData and -38 or -24, 1, 0)
	titleLabel.Position = UDim2.new(0, 22, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = text
	titleLabel.TextColor3 = COLOR_INACTIVE
	titleLabel.TextTransparency = 1
	titleLabel.Font = Enum.Font.Code
	titleLabel.TextSize = 9
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Active = false
	titleLabel.Parent = wrapper

	local checkStartPos = nil
	checkBtn.InputBegan:Connect(function(input)
		if shuttingDown then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			checkStartPos = input.Position
		end
	end)

	checkBtn.InputEnded:Connect(function(input)
		if shuttingDown or not checkStartPos then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local dist = (input.Position - checkStartPos).Magnitude
			checkStartPos = nil
			if dist < 6 then
				local newState = not toggleStates[id]
				checkBtn.Text = newState and "[#]" or "[ ]"
				executeToggleLogic(id, newState)
			end
		end
	end)

	table.insert(toggleList, {label = titleLabel, badge = checkBtn, stroke = btnStroke})

	if filterData then
		local arrowBtn = Instance.new("TextLabel")
		arrowBtn.Size = UDim2.new(0, 14, 1, 0)
		arrowBtn.Position = UDim2.new(1, -14, 0, 0)
		arrowBtn.BackgroundTransparency = 1
		arrowBtn.Text = ">"
		arrowBtn.TextColor3 = COLOR_INACTIVE
		arrowBtn.TextTransparency = 1
		arrowBtn.Font = Enum.Font.Code
		arrowBtn.TextSize = 10
		arrowBtn.Active = true
		arrowBtn.Parent = wrapper

		local arrowStartPos = nil
		arrowBtn.InputBegan:Connect(function(input)
			if shuttingDown then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				arrowStartPos = input.Position
			end
		end)

		arrowBtn.InputEnded:Connect(function(input)
			if shuttingDown or not arrowStartPos then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				local dist = (input.Position - arrowStartPos).Magnitude
				arrowStartPos = nil
				if dist < 6 then
					createFilterMenu(filterData.title, filterData.table, filterData.list)
				end
			end
		end)
		table.insert(toggleList, {arrow = arrowBtn})
	end
end

createToggle("Fullbright", "Fullbright", 1)
createToggle("Twisted_ESP", "Twisted_ESP", 2, {title = "Twisted Filter", table = monsterFilters, list = MonsterList})
createToggle("Machine_ESP", "Machine_ESP", 3)
createToggle("Item_ESP", "Item_ESP", 4, {title = "Item Filter", table = itemFilters, list = ESPItemList})
createToggle("Player_ESP", "Player_ESP", 5)
createToggle("Stat_HUD", "Stat_HUD", 6)
createToggle("Instant_Interact", "Instant_Interact", 7)
createToggle("Auto_Escape", "Auto_Escape", 8)
createToggle("Hide_Radar", "Hide_Radar", 9)

local fadeTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local cachedBlips = {} 

local function updateUI()
	if shuttingDown then return end
	local targetColor = active and COLOR_ACTIVE or COLOR_INACTIVE
	local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.spawn(function()
		if not minimized then TweenService:Create(statusText, fadeTweenInfo, {TextTransparency = 1}):Play() task.wait(0.15) end
		statusText.Text = active and "<0>" or "<X>"
		if not minimized and not shuttingDown then TweenService:Create(statusText, fadeTweenInfo, {TextTransparency = 0}):Play() end
	end)

	TweenService:Create(statusText, ti, {TextColor3 = targetColor}):Play()
	TweenService:Create(outerStroke, ti, {Color = targetColor}):Play()
	TweenService:Create(headerTag, ti, {TextColor3 = targetColor}):Play()
	TweenService:Create(bottomHeader, ti, {TextColor3 = targetColor}):Play()
	
	TweenService:Create(statOuterStroke, ti, {Color = targetColor}):Play()
	TweenService:Create(statInnerStroke, ti, {Color = targetColor, Transparency = active and 0.5 or 0.8}):Play()
	TweenService:Create(statTitle, ti, {TextColor3 = targetColor}):Play()
	TweenService:Create(statDivider, ti, {BackgroundColor3 = targetColor}):Play()
	
	TweenService:Create(radarOuterStroke, ti, {Color = targetColor}):Play()
	for _, techEl in ipairs(techCornerElements) do TweenService:Create(techEl, ti, {BackgroundColor3 = targetColor}):Play() end
	TweenService:Create(crossV, ti, {BackgroundColor3 = targetColor}):Play()
	TweenService:Create(crossH, ti, {BackgroundColor3 = targetColor}):Play()
	TweenService:Create(radarScanner, ti, {BackgroundColor3 = targetColor}):Play()
	TweenService:Create(radarCenter, ti, {BackgroundColor3 = targetColor}):Play()
	TweenService:Create(toggleContainer, ti, {ScrollBarImageColor3 = targetColor}):Play()
	for _, rStroke in ipairs(radarRings) do TweenService:Create(rStroke, ti, {Color = targetColor}):Play() end
	
	for _, item in ipairs(radialLayers) do
		if active then
			TweenService:Create(item.instance, ti, {
				BackgroundColor3 = item.color,
				BackgroundTransparency = 0.88 + (0.09 * (1 - math.clamp(item.ratio, 0, 1)))
			}):Play()
		else
			TweenService:Create(item.instance, ti, {
				BackgroundTransparency = 1
			}):Play()
		end
	end

	for _, blip in pairs(cachedBlips) do
		local stroke = blip:FindFirstChildOfClass("UIStroke")
		local targetBg, targetStroke
		
		if active then
			if blip.Name == "Twisted" then
				targetBg = Color3.fromRGB(0, 0, 0)
				targetStroke = COLOR_ACTIVE
			elseif blip.Name == "Player" then
				targetBg = Color3.fromRGB(255, 255, 255)
				targetStroke = COLOR_ACTIVE
			elseif blip.Name == "Machine" then
				targetBg = COLOR_ACTIVE
				targetStroke = Color3.fromRGB(0, 0, 0)
			end
		else
			if blip.Name == "Twisted" then
				targetBg = Color3.fromRGB(130, 130, 130)
				targetStroke = Color3.fromRGB(255, 255, 255)
			elseif blip.Name == "Player" then
				targetBg = Color3.fromRGB(255, 255, 255)
				targetStroke = Color3.fromRGB(0, 0, 0)
			elseif blip.Name == "Machine" then
				targetBg = Color3.fromRGB(0, 0, 0) 
				targetStroke = Color3.fromRGB(255, 255, 255)
			end
		end

		if targetBg then TweenService:Create(blip, ti, {BackgroundColor3 = targetBg}):Play() end
		if stroke and targetStroke then TweenService:Create(stroke, ti, {Color = targetStroke}):Play() end
	end
	
	for _, item in ipairs(toggleList) do 
		if item.label then TweenService:Create(item.label, ti, {TextColor3 = targetColor}):Play() end
		if item.badge then TweenService:Create(item.badge, ti, {TextColor3 = targetColor}):Play() end
		if item.stroke then TweenService:Create(item.stroke, ti, {Color = targetColor}):Play() end
		if item.arrow then TweenService:Create(item.arrow, ti, {TextColor3 = targetColor}):Play() end
	end
	if not minimized then
		TweenService:Create(innerStroke, ti, {Color = targetColor, Transparency = active and 0.5 or 0.8}):Play()
		if togglesOpen then 
			TweenService:Create(extOuterStroke, ti, {Color = targetColor}):Play()
			TweenService:Create(extSideL, ti, {BackgroundColor3 = targetColor, BackgroundTransparency = active and 0.5 or 0.8}):Play()
			TweenService:Create(extSideR, ti, {BackgroundColor3 = targetColor, BackgroundTransparency = active and 0.5 or 0.8}):Play()
		end
	end
end

local function toggleExtension()
	if minimized or shuttingDown then return end
	togglesOpen = not togglesOpen
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if togglesOpen then
		TweenService:Create(extendedFrame, ti, {Size = UDim2.new(1, 0, 0, 155)}):Play()
		TweenService:Create(extOuterStroke, ti, {Transparency = 0, Color = active and COLOR_ACTIVE or COLOR_INACTIVE}):Play()
		TweenService:Create(extSideL, ti, {BackgroundTransparency = active and 0.5 or 0.8, BackgroundColor3 = active and COLOR_ACTIVE or COLOR_INACTIVE}):Play()
		TweenService:Create(extSideR, ti, {BackgroundTransparency = active and 0.5 or 0.8, BackgroundColor3 = active and COLOR_ACTIVE or COLOR_INACTIVE}):Play()
		for _, item in ipairs(toggleList) do 
			if item.label then TweenService:Create(item.label, ti, {TextTransparency = 0}):Play() end
			if item.badge then TweenService:Create(item.badge, ti, {TextTransparency = 0}):Play() end
			if item.arrow then TweenService:Create(item.arrow, ti, {TextTransparency = 0}):Play() end
		end
	else
		TweenService:Create(extendedFrame, ti, {Size = UDim2.new(1, 0, 0, 0)}):Play()
		TweenService:Create(extOuterStroke, ti, {Transparency = 1}):Play()
		TweenService:Create(extSideL, ti, {BackgroundTransparency = 1}):Play()
		TweenService:Create(extSideR, ti, {BackgroundTransparency = 1}):Play()
		for _, item in ipairs(toggleList) do 
			if item.label then TweenService:Create(item.label, ti, {TextTransparency = 1}):Play() end
			if item.badge then TweenService:Create(item.badge, ti, {TextTransparency = 1}):Play() end
			if item.arrow then TweenService:Create(item.arrow, ti, {TextTransparency = 1}):Play() end
		end
		if activeFilterMenu then activeFilterMenu:Destroy() activeFilterMenu = nil end
	end
end

local function toggleMinimize()
	minimized = not minimized
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if minimized then
		TweenService:Create(mainFrame, ti, {Size = UDim2.new(0, 124, 0, 0)}):Play()
		TweenService:Create(statusText, ti, {TextTransparency = 1}):Play()
		TweenService:Create(scanline, ti, {BackgroundTransparency = 1}):Play()
		TweenService:Create(innerStroke, ti, {Transparency = 1}):Play()
		TweenService:Create(bottomHeader, ti, {TextTransparency = 1}):Play()
		if togglesOpen then
			TweenService:Create(extendedFrame, ti, {Size = UDim2.new(1, 0, 0, 0)}):Play()
			TweenService:Create(extOuterStroke, ti, {Transparency = 1}):Play()
			TweenService:Create(extSideL, ti, {BackgroundTransparency = 1}):Play()
			TweenService:Create(extSideR, ti, {BackgroundTransparency = 1}):Play()
			for _, item in ipairs(toggleList) do 
				if item.label then TweenService:Create(item.label, ti, {TextTransparency = 1}):Play() end
				if item.badge then TweenService:Create(item.badge, ti, {TextTransparency = 1}):Play() end
				if item.arrow then TweenService:Create(item.arrow, ti, {TextTransparency = 1}):Play() end
			end
			if activeFilterMenu then activeFilterMenu:Destroy() activeFilterMenu = nil end
		end
	else
		TweenService:Create(mainFrame, ti, {Size = UDim2.new(0, 124, 0, 72)}):Play()
		TweenService:Create(statusText, ti, {TextTransparency = 0}):Play()
		TweenService:Create(scanline, ti, {BackgroundTransparency = 0.88}):Play()
		TweenService:Create(innerStroke, ti, {Transparency = active and 0.5 or 0.8}):Play()
		TweenService:Create(bottomHeader, ti, {TextTransparency = 0}):Play()
		if togglesOpen then
			TweenService:Create(extendedFrame, ti, {Size = UDim2.new(1, 0, 0, 155)}):Play()
			TweenService:Create(extOuterStroke, ti, {Transparency = 0}):Play()
			TweenService:Create(extSideL, ti, {BackgroundTransparency = active and 0.5 or 0.8}):Play()
			TweenService:Create(extSideR, ti, {BackgroundTransparency = active and 0.5 or 0.8}):Play()
			for _, item in ipairs(toggleList) do 
				if item.label then TweenService:Create(item.label, ti, {TextTransparency = 0}):Play() end
				if item.badge then TweenService:Create(item.badge, ti, {TextTransparency = 0}):Play() end
				if item.arrow then TweenService:Create(item.arrow, ti, {TextTransparency = 0}):Play() end
			end
		end
	end
end

local function toggle()
	active = not active
	if not active then resetMomentum() end
	if active then soundOn:Play() else soundOff:Play() end
	updateUI()
end

local function wipeSystem()
	shuttingDown = true
	restoreLighting()
	restorePrompts()
	removeESPType("Monster")
	removeESPType("Machine")
	removeESPType("Item")
	removeESPType("Player")
	toggleStates.Instant_Interact = false
	for _, conn in ipairs(connections) do if conn then conn:Disconnect() end end
	for _, conn in pairs(promptConnections) do if conn then conn:Disconnect() end end
	resetMomentum()
	if screenGui then screenGui:Destroy() end
end

local dragging, hasDragged = false, false
local dragStart, startPos, dragInputObject
local isHoldingEye, holdTick = false, 0
local yellowTweens = {}
local colorWarn = Color3.fromRGB(255, 215, 0)

local function clearYellowTweens()
	for _, tw in ipairs(yellowTweens) do tw:Cancel() end
	table.clear(yellowTweens)
end

local function startYellowTransition()
	clearYellowTweens()
	local ti = TweenInfo.new(3, Enum.EasingStyle.Linear)
	table.insert(yellowTweens, TweenService:Create(statusText, ti, {TextColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(outerStroke, ti, {Color = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(innerStroke, ti, {Color = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(headerTag, ti, {TextColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(bottomHeader, ti, {TextColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(toggleContainer, ti, {ScrollBarImageColor3 = colorWarn}))
	
	table.insert(yellowTweens, TweenService:Create(statOuterStroke, ti, {Color = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(statInnerStroke, ti, {Color = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(statTitle, ti, {TextColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(statDivider, ti, {BackgroundColor3 = colorWarn}))
	
	table.insert(yellowTweens, TweenService:Create(radarOuterStroke, ti, {Color = colorWarn}))
	for _, techEl in ipairs(techCornerElements) do table.insert(yellowTweens, TweenService:Create(techEl, ti, {BackgroundColor3 = colorWarn})) end
	table.insert(yellowTweens, TweenService:Create(crossV, ti, {BackgroundColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(crossH, ti, {BackgroundColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(radarScanner, ti, {BackgroundColor3 = colorWarn}))
	table.insert(yellowTweens, TweenService:Create(radarCenter, ti, {BackgroundColor3 = colorWarn}))
	for _, rStroke in ipairs(radarRings) do table.insert(yellowTweens, TweenService:Create(rStroke, ti, {Color = colorWarn})) end
	
	for _, item in ipairs(radialLayers) do
		local cWarn = Color3.fromRGB(
			math.floor((255 * 0.25) * (item.ratio^2)),
			math.floor((215 * 0.25) * (item.ratio^2)),
			0
		)
		table.insert(yellowTweens, TweenService:Create(item.instance, ti, {
			BackgroundColor3 = cWarn,
			BackgroundTransparency = 0.88 + (0.09 * (1 - math.clamp(item.ratio, 0, 1)))
		}))
	end

	for _, blip in pairs(cachedBlips) do
		local stroke = blip:FindFirstChildOfClass("UIStroke")
		table.insert(yellowTweens, TweenService:Create(blip, ti, {BackgroundColor3 = colorWarn}))
		if stroke then table.insert(yellowTweens, TweenService:Create(stroke, ti, {Color = colorWarn})) end
	end
	
	for _, item in ipairs(toggleList) do 
		if item.label then table.insert(yellowTweens, TweenService:Create(item.label, ti, {TextColor3 = colorWarn})) end
		if item.badge then table.insert(yellowTweens, TweenService:Create(item.badge, ti, {TextColor3 = colorWarn})) end
		if item.stroke then table.insert(yellowTweens, TweenService:Create(item.stroke, ti, {Color = colorWarn})) end
		if item.arrow then table.insert(yellowTweens, TweenService:Create(item.arrow, ti, {TextColor3 = colorWarn})) end
	end
	if togglesOpen then 
		table.insert(yellowTweens, TweenService:Create(extOuterStroke, ti, {Color = colorWarn}))
		table.insert(yellowTweens, TweenService:Create(extSideL, ti, {BackgroundColor3 = colorWarn}))
		table.insert(yellowTweens, TweenService:Create(extSideR, ti, {BackgroundColor3 = colorWarn}))
	end
	for _, tw in ipairs(yellowTweens) do tw:Play() end

	local thisHold = holdTick
	task.delay(3, function()
		if isHoldingEye and holdTick == thisHold and not shuttingDown then
			shuttingDown = true
			clearYellowTweens()
			if active then active = false resetMomentum() soundOff:Play() end
			statusText.Text = "<X>"
			local fadeOutTI = TweenInfo.new(1)
			TweenService:Create(mainFrame, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(statusText, fadeOutTI, {TextTransparency = 1}):Play()
			TweenService:Create(headerTag, fadeOutTI, {TextTransparency = 1}):Play()
			TweenService:Create(bottomHeader, fadeOutTI, {TextTransparency = 1}):Play()
			TweenService:Create(scanline, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(outerStroke, fadeOutTI, {Transparency = 1}):Play()
			TweenService:Create(innerStroke, fadeOutTI, {Transparency = 1}):Play()
			TweenService:Create(extendedFrame, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(extOuterStroke, fadeOutTI, {Transparency = 1}):Play()
			TweenService:Create(extSideL, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(extSideR, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(zeroWrapper, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(zeroStroke, fadeOutTI, {Transparency = 1}):Play()
			TweenService:Create(zeroAccent, fadeOutTI, {BackgroundTransparency = 1}):Play()
			TweenService:Create(zeroHeader, fadeOutTI, {TextTransparency = 1}):Play()
			TweenService:Create(zeroText, fadeOutTI, {TextTransparency = 1}):Play()
			for _, item in ipairs(toggleList) do 
				if item.label then TweenService:Create(item.label, fadeOutTI, {TextTransparency = 1}):Play() end
				if item.badge then TweenService:Create(item.badge, fadeOutTI, {TextTransparency = 1}):Play() end
				if item.arrow then TweenService:Create(item.arrow, fadeOutTI, {TextTransparency = 1}):Play() end
			end
			task.wait(1) wipeSystem()
		end
	end)
end

local function handleInputBegan(input, region)
	if shuttingDown then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true hasDragged = false
		dragStart = input.Position startPos = mainFrame.Position dragInputObject = input
		local currentHoldTick = tick()
		if region == "eye" and not minimized then isHoldingEye = true holdTick = currentHoldTick startYellowTransition() end

		local endConn
		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false isHoldingEye = false
				if holdTick == currentHoldTick and not shuttingDown then clearYellowTweens() updateUI() end
				endConn:Disconnect()
				if not hasDragged and not shuttingDown then
					if region == "header" then toggleMinimize() elseif region == "eye" then toggle() elseif region == "bottom" then toggleExtension() end
				end
			end
		end)
	end
end

headerTag.InputBegan:Connect(function(input) handleInputBegan(input, "header") end)
mainFrame.InputBegan:Connect(function(input) handleInputBegan(input, "eye") end)
bottomHeader.InputBegan:Connect(function(input) handleInputBegan(input, "bottom") end)

table.insert(connections, UserInputService.InputChanged:Connect(function(input)
	if dragging and input == dragInputObject and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		if delta.Magnitude > 3 then
			if not hasDragged then hasDragged = true if isHoldingEye then isHoldingEye = false clearYellowTweens() if not shuttingDown then updateUI() end end end
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe or shuttingDown then return end
	if input.KeyCode == Enum.KeyCode.ButtonL3 or input.KeyCode == Enum.KeyCode.P then toggle()
	elseif input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.End then wipeSystem() end
end))

local function registerDescendant(desc)
	if desc:IsA("Model") then
		if isTwisted(desc) then 
			TrackedEntities.Twisteds[desc] = true 
		elseif isMachine(desc) then
			registerMachine(desc)
		end
	elseif desc:IsA("ProximityPrompt") then
		TrackedEntities.Prompts[desc] = true
		trackPrompt(desc)
		if toggleStates.Instant_Interact then desc.HoldDuration = 0 end
		if toggleStates.Item_ESP and desc.ActionText ~= "Ichor" and desc.ActionText ~= "" and desc.Enabled and isItemAllowed(desc.ActionText) then 
			task.wait(0.1) 
			applyESP(desc.Parent, "Item", desc.ActionText) 
		end
		
		local parentModel = desc:FindFirstAncestorWhichIsA("Model")
		if parentModel and isMachine(parentModel) and not TrackedEntities.Machines[parentModel] then
			registerMachine(parentModel)
		end
	end
end

table.insert(connections, workspace.DescendantAdded:Connect(function(desc)
	registerDescendant(desc)
	if toggleStates.Twisted_ESP and isTwisted(desc) then task.wait(0.15) applyESP(desc, "Monster") end
	if toggleStates.Machine_ESP and (TrackedEntities.Machines[desc] or isMachine(desc)) then task.wait(0.15) applyESP(desc, "Machine") end
end))

table.insert(connections, workspace.DescendantRemoving:Connect(function(desc)
	if desc:IsA("Model") then
		TrackedEntities.Twisteds[desc] = nil
		TrackedEntities.Machines[desc] = nil
	elseif desc:IsA("ProximityPrompt") then
		TrackedEntities.Prompts[desc] = nil
		EnvironmentSnapshot.Prompts[desc] = nil
	end
	if cachedBlips[desc] then
		cachedBlips[desc]:Destroy()
		cachedBlips[desc] = nil
	end
end))

for _, desc in ipairs(workspace:GetDescendants()) do
	registerDescendant(desc)
end

updateUI()
scanAndApplyESP()
updateProximityPrompts()

local lastRadarTick = 0

local function getOrCreateBlip(target, blipType)
	if cachedBlips[target] then return cachedBlips[target] end
	local blip = Instance.new("Frame")
	blip.Name = blipType
	blip.Size = UDim2.new(0, 5, 0, 5)
	blip.AnchorPoint = Vector2.new(0.5, 0.5) 
	blip.BorderSizePixel = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = blip
	
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Parent = blip
	
	if active then
		if blipType == "Twisted" then
			blip.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
			stroke.Color = COLOR_ACTIVE
		elseif blipType == "Player" then
			blip.BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
			stroke.Color = COLOR_ACTIVE
		elseif blipType == "Machine" then
			blip.BackgroundColor3 = COLOR_ACTIVE 
			stroke.Color = Color3.fromRGB(0, 0, 0)
		end
	else
		if blipType == "Twisted" then
			blip.BackgroundColor3 = Color3.fromRGB(130, 130, 130) 
			stroke.Color = Color3.fromRGB(255, 255, 255)
		elseif blipType == "Player" then
			blip.BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
			stroke.Color = Color3.fromRGB(0, 0, 0)
		elseif blipType == "Machine" then
			blip.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
			stroke.Color = Color3.fromRGB(255, 255, 255)
		end
	end

	blip.Parent = radarBlips
	cachedBlips[target] = blip
	return blip
end

local function executeRadarTick()
	if shuttingDown then return end 
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	local hrp = player.Character.HumanoidRootPart
	local look = cam.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
	else
		flatLook = Vector3.new(0, 0, -1)
	end

	local myCFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook)
	local maxRange, radius = 150, 70
	local seenTargets = {}

	local function processTarget(targetObj, blipType)
		if not targetObj or not targetObj.Parent then return end
		local part = targetObj:IsA("Model") and (targetObj:FindFirstChild("HumanoidRootPart") or targetObj.PrimaryPart or targetObj:FindFirstChildWhichIsA("BasePart")) or (targetObj:IsA("BasePart") and targetObj or nil)
		if not part then return end

		local relativePos = myCFrame:PointToObjectSpace(part.Position)
		local dist2D = Vector2.new(relativePos.X, relativePos.Z).Magnitude
		
		if dist2D <= maxRange then
			seenTargets[targetObj] = true
			local blip = getOrCreateBlip(targetObj, blipType)
			local rX = (relativePos.X / maxRange) * radius
			local rY = (relativePos.Z / maxRange) * radius
			
			blip.Position = UDim2.new(0.5, rX, 0.5, rY)

			local blipAngle = (math.deg(math.atan2(rY, rX)) + 360) % 360
			local scanAngle = scannerPivot.Rotation % 360
			local angleDiff = math.abs(blipAngle - scanAngle)
			
			local str = blip:FindFirstChildOfClass("UIStroke")
			if angleDiff < 14 or angleDiff > 346 then
				blip.BackgroundTransparency = 0
				if str then
					str.Thickness = 1.6
					str.Transparency = 0
				end
			else
				blip.BackgroundTransparency = math.clamp(blip.BackgroundTransparency + 0.0088, 0, 0.35)
				if str then
					str.Thickness = math.clamp(str.Thickness - 0.012, 1.0, 1.6)
					str.Transparency = math.clamp(str.Transparency + 0.0088, 0, 0.5)
				end
			end
		end
	end

	for t in pairs(TrackedEntities.Twisteds) do
		if isTwisted(t) then processTarget(t, "Twisted") end
	end
	for m in pairs(TrackedEntities.Machines) do
		processTarget(m, "Machine")
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then processTarget(p.Character, "Player") end
	end

	for obj, blip in pairs(cachedBlips) do
		if not seenTargets[obj] then
			blip:Destroy()
			cachedBlips[obj] = nil
		end
	end
end

table.insert(connections, RunService.Stepped:Connect(function()
	if shuttingDown then return end
	if active then
		applyAntiSlip(true)
	end
end))

table.insert(connections, RunService.RenderStepped:Connect(function()
	if shuttingDown then
		radarWrapper.Visible = false
		return
	else
		radarWrapper.Visible = not toggleStates.Hide_Radar
		scannerPivot.Rotation = (tick() * 150) % 360
	end

	if tick() - lastRadarTick >= 0.005 then
		lastRadarTick = tick()
		executeRadarTick()
	end
end))

table.insert(connections, RunService.Heartbeat:Connect(function()
	if shuttingDown then return end

	-- Time-Based Lovey-Dovey (3 mins) & Super Love (10 mins) Logic
	local timeSinceDamage = tick() - lastHitTick
	if active and not isChatting then
		if timeSinceDamage >= 600 and (tick() - lastSuperLoveTick > 90) then
			lastSuperLoveTick = tick()
			queueDialogue("SuperLove")
		elseif timeSinceDamage >= 180 and timeSinceDamage < 600 and (tick() - lastLoveyDoveyTick > 60) then
			lastLoveyDoveyTick = tick()
			queueDialogue("LoveyDovey")
		end
	end

	if tick() - lastStatUpdate > 1 then
		lastStatUpdate = tick()
		
		if toggleStates.Player_ESP then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and p.Character then applyESP(p.Character, "Player", p.DisplayName or p.Name) end
			end
		end
		
		if toggleStates.Stat_HUD then
			local mCount, itemsFound = 0, {}
			
			for model in pairs(TrackedEntities.Twisteds) do
				if isTwisted(model) then mCount = mCount + 1 end
			end
			
			for prompt in pairs(TrackedEntities.Prompts) do
				if prompt.Enabled and prompt.ActionText ~= "Ichor" and prompt.ActionText ~= "" then
					if StatHudValuables[prompt.ActionText] then 
						itemsFound[prompt.ActionText] = (itemsFound[prompt.ActionText] or 0) + 1 
					end
				end
			end
			
			local lines = {string.format("> Twisteds: %02d", mCount), "", "> Valuables:"}
			local hasItems = false
			for name, count in pairs(itemsFound) do lines[#lines+1] = string.format("  • %s x%d", name, count) hasItems = true end
			if not hasItems then lines[#lines+1] = "  • None" end
			statBody.Text = table.concat(lines, "\n")
		end
	end

	if toggleStates.Fullbright then
		Lighting.Ambient = Color3.fromRGB(110, 110, 115)
		Lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 115)
		Lighting.GlobalShadows = false
		Lighting.ExposureCompensation = EnvironmentSnapshot.Lighting.ExposureCompensation + 0.8
	end

	if toggleStates.Auto_Escape then
		local squirmUI = pgui:FindFirstChild("TwistedSquirmEscapeUI")
		if squirmUI and squirmUI.Enabled and (tick() - lastEscapeTap > 0.05) then
			lastEscapeTap = tick()
			pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game) task.wait(0.01) VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		end
	end
end))
