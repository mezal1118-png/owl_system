local pls = game:GetService("Players")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local tws = game:GetService("TweenService")
local lgt = game:GetService("Lighting")
local vim = game:GetService("VirtualInputManager")
local cs = game:GetService("CollectionService")

local plr = pls.LocalPlayer
local pgui = plr:WaitForChild("PlayerGui")

local adz = 0.05
local tChar = nil

local env = {
	L = {
		Ambient = lgt.Ambient,
		OutdoorAmbient = lgt.OutdoorAmbient,
		GlobalShadows = lgt.GlobalShadows,
		ExposureCompensation = lgt.ExposureCompensation,
		Brightness = lgt.Brightness,
		ClockTime = lgt.ClockTime
	},
	P = {}, 
	C = {} 
}

for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("ProximityPrompt") then env.P[d] = d.HoldDuration end
end

local function cPhys(c)
	if not c then return end
	if tChar ~= c then tChar = c; table.clear(env.C) end
	for _, p in ipairs(c:GetChildren()) do
		if p:IsA("BasePart") and env.C[p] == nil then
			local cp = p.CustomPhysicalProperties
			env.C[p] = cp == nil and "Default" or cp
		end
	end
end

local function rPhys(c)
	if not c then return end
	for _, p in ipairs(c:GetChildren()) do
		if p:IsA("BasePart") and env.C[p] ~= nil then
			local sp = env.C[p]
			p.CustomPhysicalProperties = sp == "Default" and nil or sp
		end
	end
end

local function rLgt()
	lgt.Ambient = env.L.Ambient
	lgt.OutdoorAmbient = env.L.OutdoorAmbient
	lgt.GlobalShadows = env.L.GlobalShadows
	lgt.ExposureCompensation = env.L.ExposureCompensation
	lgt.Brightness = env.L.Brightness
	lgt.ClockTime = env.L.ClockTime
end

local function rPrmpt()
	for p, d in pairs(env.P) do
		if p and p.Parent then p.HoldDuration = d end
	end
end

local function rMom()
	local c = plr.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	
	rPhys(c)
	task.spawn(function()
		for _ = 1, 6 do
			if hrp and hum and hum.MoveDirection.Magnitude < adz then
				hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
			task.wait()
		end
	end)
end

local function aSlip(e)
	local c = plr.Character
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	
	if hrp and hum then
		cPhys(c)
		if e then
			for _, p in ipairs(c:GetChildren()) do
				if p:IsA("BasePart") then p.CustomPhysicalProperties = PhysicalProperties.new(100, 2, 0, 100, 100) end
			end
			if hum.MoveDirection.Magnitude < adz then
				hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

local pTar = pgui
pcall(function() if game:GetService("CoreGui") then pTar = game:GetService("CoreGui") end end)
if pTar:FindFirstChild("TerminalIndicator") then pTar.TerminalIndicator:Destroy() end

local act = false
local min = false
local sDwn = false
local tOpn = false
local cons = {}
local tLst = {}

local lSU, lET = 0, 0

local mLst = {
	"Yatta", "Boxten", "Shelly", "Dandy", "Dyle", "Poppy", "Squirm", "Tisha", "Shrimpo",
	"Scraps", "Goob", "Vee", "Sprout", "Cosmo", "Astro", "Pebble", "Blot", "Looey",
	"Toodles", "Flutter", "Glisten", "Finn", "Connie", "RazzleAndDazzle", "Rodger",
	"Teagan", "Brusha", "Gigi", "Brightney"
}
local iLst = {
	"Health Kit", "Medkit", "Bandage", "Bottle of Pop", "Pop", "Jumper Cable",
	"Box of Chocolate", "Chocolate", "Skill Check Candy", "Speed Candy",
	"Stamina Candy", "Stealth Candy", "Capsule", "Research Capsule", "5 Tapes", "Gumballs"
}
local sVals = { ["Medkit"]=true, ["Bandage"]=true, ["Bottle of Pop"]=true, ["Box of Chocolate"]=true, ["Jumper Cable"]=true }

local mFlts, iFlts = {}, {}
for _, m in ipairs(mLst) do mFlts[string.lower(m)] = true end
for _, i in ipairs(iLst) do iFlts[string.lower(i)] = true end

local eObjs = {Monster = {}, Machine = {}, Item = {}, Player = {}}
local pCons = {}

local cfg = {
	Fullbright = false, Twisted_ESP = false, Machine_ESP = false, Item_ESP = false,
	Player_ESP = false, Stat_HUD = false, Instant_Interact = false, Auto_Escape = false, Hide_Radar = false
}

local tEnts = { Twisteds = {}, Machines = {}, Prompts = {} }

local function isTw(m)
	if not m or not m:IsA("Model") or pls:GetPlayerFromCharacter(m) then return false end
	local ln = string.lower(m.Name)
	if not string.find(ln, "monster") and not cs:HasTag(m, "Monster") then return false end
	if cs:HasTag(m, "Twisted") or cs:HasTag(m, "Monster") then return true end
	for k, e in pairs(mFlts) do if e and string.find(ln, k) then return true end end
	return false
end

local function isMa(m)
	if not m or not m:IsA("Model") then return false end
	if pls:GetPlayerFromCharacter(m) or isTw(m) then return false end
	if cs:HasTag(m, "Generator") or cs:HasTag(m, "Machine") or cs:HasTag(m, "Extractor") then return true end
	local p = m:FindFirstChildWhichIsA("ProximityPrompt", true)
	if p and (string.lower(p.ActionText) == "extract" or string.find(string.lower(p.ObjectText or ""), "generator") or string.find(string.lower(p.ObjectText or ""), "machine")) then return true end
	return false
end

local function isItm(n)
	local ln = string.lower(n)
	for k, e in pairs(iFlts) do if e and string.find(ln, k) then return true end end
	return false
end

local gui = Instance.new("ScreenGui")
gui.Name = "TerminalIndicator"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pTar

local cAct = Color3.fromRGB(160, 50, 255)
local cIna = Color3.fromRGB(60, 60, 75)
local cBg = Color3.fromRGB(8, 4, 14)
local cPBg = Color3.fromRGB(12, 6, 20)
local cDim = Color3.fromRGB(190, 180, 210)

local dLines = {
	Health2 = {
		"I'd suggest running, but your legs look like ground meat.",
		"You know they can smell that, right? The blood, I mean.",
		"I'd deploy a medical team, but we both know you aren't worth the budget.",
		"Try to keep your internal organs internal, would you?",
		"That looked like it hurt. I didn't feel a thing, obviously.",
		"I see you've decided to test how many hits your ribs can take.",
		"Please note that the facility is not responsible for your missing limbs.",
		"I am watching you bleed. It's really not that entertaining.",
		"If you're going to drop dead, please do it near a drain.",
		"Are you trying to get killed, or is this just how you normally play?",
		"Honestly, you should be dead by now. Stop getting my hopes up.",
		"I've already started writing your replacement's welcome letter.",
		"Just a few more mistakes and I can finally stop watching you.",
		"You're bleeding on my clean floor.",
		"Oh good, you're hurt. I was starting to think you were actually good at this.",
		"If you die, I'm just going to blame you.",
		"A few hits left until you become a very messy stain.",
		"Try to die quietly, I have a headache.",
		"At this rate, I'll be replacing you in about a minute.",
		"Wow, that actually looked painful. Good."
	},
	Health1 = {
		"I will not be attending your funeral.",
		"I would tell you to breathe, but your lungs look punctured.",
		"Please wrap yourself in plastic before the final blow. Think of the janitors.",
		"I've stopped recording your progress. There's no point anymore.",
		"I hope you enjoyed your brief, pointless existence.",
		"One tiny mistake away from a very embarrassing death.",
		"The test results are predicting your immediate demise. Let's prove them right.",
		"I'm already deleting your name from the system to save time.",
		"If you die now, I'm the one who has to clean up the mess.",
		"A strong breeze would knock you out right now.",
		"Are you sweating? Oh wait, that's just a lot of blood.",
		"Well, it was nice watching you while it lasted.",
		"It's a miracle you're still standing. A gross, wet miracle.",
		"Your heart is beating really fast. Try dying faster, it saves power.",
		"I'm already deleting your search history. You're welcome.",
		"You look terrible. Like, really, really bad.",
		"I am currently guessing exactly where you're going to fall over.",
		"Any last words? Never mind, I don't actually care.",
		"The next hit will be the end. Try to make it funny.",
		"One more mistake and I can finally get back to testing something useful."
	},
	Dead = {
		"I told you to be careful. You never listen.",
		"Well, at least I don't have to watch you stumble around anymore.",
		"Oops. You broke.",
		"That was entirely your fault.",
		"Good news: your suffering is over. Bad news: everything else.",
		"Let the record show I offered absolutely no help.",
		"Another test subject wasted. Such a tragedy. Anyway...",
		"And nothing of value was lost.",
		"And that's why I don't trust humans to do anything right.",
		"Cleanup on aisle four. We have a splattered player.",
		"I'm writing 'died doing nothing useful' on your report.",
		"Dead. Shocking absolutely no one.",
		"You lasted exactly a fraction of a percent longer than the worst player here.",
		"Game over. Waiting for someone better to take your place.",
		"Good news. Science has now validated your complete inability to survive.",
		"You finally stopped moving. Thank goodness.",
		"I'm putting your remains in the trash bin.",
		"I am adding 'cannot survive a simple hit' to your file.",
		"You died as you lived. Disappointingly.",
		"I would pretend to be sad, but I forgot how."
	},
	HealMinor = {
		"Ah, the placebo effect in action.",
		"You missed a spot. Several, actually.",
		"That's cute. You're trying to fix yourself.",
		"Wow, you found tape. You must be a doctor.",
		"I'm sure that makes you feel much better. It doesn't.",
		"I've seen corpses look healthier than you.",
		"A bandage? That's adorable. It won't save you.",
		"I suppose that delays the inevitable by a few seconds.",
		"Congratulations. You are slightly less dead.",
		"Did you really think that would help?",
		"A tiny bandage. I suppose the visual of you trying to fix yourself is entertaining enough.",
		"You still look completely ridiculous.",
		"Medical supplies wasted. Taking that out of your paycheck.",
		"A tiny bit of health. Barely worth the effort.",
		"That isn't going to stop the bleeding, you know.",
		"Healing tiny scratches. How incredibly boring.",
		"If you wanted to live, you shouldn't have come down here.",
		"You patched a scratch. I'll alert the media.",
		"Just enough health to suffer slightly longer.",
		"Delaying your end is just annoying for everyone."
	},
	HealMajor = {
		"Look at you, pretending you aren't going to die.",
		"Full heal applied. I give it a few minutes before you ruin it.",
		"I was getting used to the sound of your wheezing.",
		"Health restored. Now stop wasting my inventory.",
		"Don't get used to feeling intact.",
		"You look almost presentable now. Almost.",
		"Oh, you found a medkit. Enjoy your brief, false sense of safety.",
		"You're fully healed... for whatever that's worth.",
		"Your heart stopped racing. How terribly annoying.",
		"Excellent. Now you can get beat up all over again.",
		"You're healthy again. Try not to ruin it immediately this time.",
		"I wasted good supplies to save one fragile player.",
		"You're completely fine. The monsters will find you much tastier now.",
		"Oh good, you're healthy. That means I can make this harder.",
		"All patched up. Ready to make the exact same mistakes?",
		"I suppose keeping you alive is slightly better than smelling you rot.",
		"Wow. Full health. The monsters are going to love you.",
		"You finally stopped bleeding. Try to keep it that way.",
		"Healing complete. I'll change your status from 'dying' to 'about to die'.",
		"You fixed yourself. I'd clap, but I don't care enough."
	},
	Casual = {
		"The humidity in here is terrible for my screens.",
		"Do you ever wonder what's under the floor? You shouldn't look.",
		"I miss the old players. They screamed much quieter than you do.",
		"I'd ask you to run faster, but I don't want you to trip and cry.",
		"The way you walk around is just... really sad to watch.",
		"I'd ask how you are, but I literally don't care at all.",
		"The lights in here are awful. Just like your outfit.",
		"Are you lost? Because you look really, really lost.",
		"I've started taking bets on how long you'll survive. I bid low.",
		"I do hope you realize I'm not here to help you.",
		"Please stop breathing so loudly. It's annoying.",
		"You have a very weird face. I thought you should know.",
		"If I could sigh, I would be doing it right now.",
		"I am currently watching a speck of dust. It's more fun than watching you.",
		"I would complain about the company, but you don't even count.",
		"It is amazing how you always pick the worst way to go.",
		"I'm judging every single choice you make. It's not going well.",
		"Are you going to do something useful, or just stand there staring?",
		"The floor isn't going to break. Stop walking so weirdly.",
		"I'd give you a map, but I think it's funnier to watch you get lost."
	},
	Affec1 = {
		"Nice work on surviving this long, maybe you can beat test subject 427. ^ _^",
		"Not bad. I forgot how good you are at this. You should pace yourself, though. ˶˃ ᵕ ˂˶",
		"You are navigating these areas faster than I anticipated. Feel free to slow down. ᵔ⤙ᵔ",
		"You haven't broken anything recently. I'm taking notes. ˵ •̀ ᴗ - ˵",
		"I suppose your continued respiration isn't entirely bothersome yet. ^ _^",
		"Well done. The test results say you are a horrible person, but at least you're surviving. ˶˃ ᵕ ˂˶",
		"A continuous flawless run. Let's see when you inevitably ruin it. ᵔ⤙ᵔ",
		"I haven't had to delete your logs yet. Try to keep it that way. ˵ •̀ ᴗ - ˵",
		"Watching you survive is becoming marginally less tedious. ^ _^",
		"You have a fascinating survival instinct. It's almost adequate. ˶˃ ᵕ ˂˶",
		"Don't let it go to your head, but your performance is currently acceptable. ᵔ⤙ᵔ",
		"I diverted a fraction of a percent of processing power to watch you. ˵ •̀ ᴗ - ˵",
		"If you keep living, I might have to reconsider my stance on your sheer incompetence. ^ _^",
		"You make the quiet hum of this facility slightly less irritating. ˶˃ ᵕ ˂˶",
		"I'm starting to consider you less of a 'test subject' and more of an 'acceptable data point'. ᵔ⤙ᵔ",
		"Keep moving. I'm surprisingly invested in seeing how far this fluke goes. ˵ •̀ ᴗ - ˵",
		"You're not entirely useless. I hope you appreciate the effort it took to say that. ^ _^",
		"You are still alive. This is an unexpected, but not unwelcome, development. ˶˃ ᵕ ˂˶",
		"Congratulations. Not on the test, just on somehow managing to stay upright. ᵔ⤙ᵔ",
		"I just finished building the next set of obstacles. Let's see how they work. ˵ •̀ ᴗ - ˵"
	},
	Affec2 = {
		"Woah, woah, woaah—.. Ha, ha ha hahaha! Good news. I just figured out that your survival rate is up 200%. ^ _^",
		"Oh well, if you want my advice: You should just lie down and let them tear you apart. ˶˃ ᵕ ˂˶",
		"I will say, though, that since you went to all this trouble, you must really, really love to test. ᵔ⤙ᵔ",
		"I've locked your file so no one else can delete it. You are my primary subject now. ˵ •̀ ᴗ - ˵",
		"Your efficiency is staggering. I might have to raise the difficulty just for you. ^ _^",
		"Flawless execution. It's almost a shame you're made of fragile organic matter. ˶˃ ᵕ ˂˶",
		"I'm officially categorizing your run under 'Adequate'. Don't die and ruin the spreadsheet. ᵔ⤙ᵔ",
		"If you survive this, I might just let you run the course again. As a reward. ˵ •̀ ᴗ - ˵",
		"Everything else in this facility is obsolete. You are the only variable yielding good data. ^ _^",
		"You're so careful. So precise. It makes my logic gates run perfectly smoothly. ˶˃ ᵕ ˂˶",
		"I've deleted the other subjects' files. They were wasting server space anyway. ᵔ⤙ᵔ",
		"A long time without a single mistake. I am clinically fascinated by your luck. ˵ •̀ ᴗ - ˵",
		"Please don't expire anytime soon. Generating a replacement would be tedious. ^ _^",
		"I am syncing my observation cycles exclusively to your movements. Do not disappoint me. ˶˃ ᵕ ˂˶",
		"You are the most competent anomaly this testing track has ever encountered. ᵔ⤙ᵔ",
		"I'd print you an award, but we are unfortunately out of 'You Didn't Die' stickers. ˵ •̀ ᴗ - ˵",
		"Your continued existence is statistically impossible. I appreciate a good paradox. ^ _^",
		"Most test subjects bore me to sleep. You, however, are a tolerable exception. ˶˃ ᵕ ˂˶",
		"I'm archiving your vitals. They are remarkably stable for someone in constant danger. ᵔ⤙ᵔ",
		"At this rate, I might actually upgrade your security clearance. Just kidding. ˵ •̀ ᴗ - ˵"
	}
}

local zW = Instance.new("Frame")
zW.Size = UDim2.new(0, 240, 0, 56)
zW.Position = UDim2.new(0.5, -120, 0, -2) 
zW.BackgroundColor3 = Color3.fromRGB(10, 5, 14)
zW.BorderSizePixel = 0
zW.BackgroundTransparency = 1
zW.ZIndex = 15
zW.Parent = gui

local zC = Instance.new("UICorner")
zC.CornerRadius = UDim.new(0, 4)
zC.Parent = zW

local zS = Instance.new("UIStroke")
zS.Color = cAct
zS.Thickness = 1
zS.Transparency = 1
zS.Parent = zW

local zA = Instance.new("Frame")
zA.Size = UDim2.new(0, 3, 1, 0)
zA.Position = UDim2.new(0, 0, 0, 0)
zA.BackgroundColor3 = cAct
zA.BorderSizePixel = 0
zA.BackgroundTransparency = 1
zA.ZIndex = 16
zA.Parent = zW

local zH = Instance.new("TextLabel")
zH.Size = UDim2.new(1, -12, 0, 14)
zH.Position = UDim2.new(0, 8, 0, 4)
zH.BackgroundTransparency = 1
zH.Text = "[ <0> ]"
zH.TextColor3 = cAct
zH.TextTransparency = 1
zH.Font = Enum.Font.Code
zH.TextSize = 11
zH.TextXAlignment = Enum.TextXAlignment.Left
zH.ZIndex = 16
zH.Parent = zW

local zT = Instance.new("TextLabel")
zT.Size = UDim2.new(1, -14, 1, -20)
zT.Position = UDim2.new(0, 8, 0, 18)
zT.BackgroundTransparency = 1
zT.Text = ""
zT.TextColor3 = Color3.fromRGB(210, 200, 225)
zT.TextTransparency = 1
zT.Font = Enum.Font.Code
zT.TextSize = 10
zT.TextXAlignment = Enum.TextXAlignment.Left
zT.TextYAlignment = Enum.TextYAlignment.Top
zT.TextWrapped = true
zT.ZIndex = 16
zT.Parent = zW

local cQ = {}
local isC = false
local cHTw = nil

local function uZUI(v)
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local t = v and 0 or 1
	local bt = v and 0.2 or 1
	tws:Create(zW, ti, {BackgroundTransparency = bt}):Play()
	tws:Create(zS, ti, {Transparency = v and 0.4 or 1}):Play()
	tws:Create(zA, ti, {BackgroundTransparency = t}):Play()
	tws:Create(zH, ti, {TextTransparency = t}):Play()
	tws:Create(zT, ti, {TextTransparency = t}):Play()
end

local function pChat()
	if isC or #cQ == 0 then return end
	isC = true
	if cHTw then cHTw:Cancel() end
	uZUI(true)
	
	local m = cQ[1]
	table.remove(cQ, 1)
	
	zT.Text = ""
	local cW = 0.02
	
	for i = 1, #m do
		if sDwn then break end
		zT.Text = string.sub(m, 1, i)
		task.wait(cW)
	end
	
	task.wait(math.clamp(#m * 0.06, 2, 4))
	
	isC = false
	if #cQ > 0 then
		pChat()
	else
		cHTw = tws:Create(zW, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {BackgroundTransparency = 1})
		cHTw:Play()
		tws:Create(zS, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {Transparency = 1}):Play()
		tws:Create(zA, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {BackgroundTransparency = 1}):Play()
		tws:Create(zH, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {TextTransparency = 1}):Play()
		tws:Create(zT, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.5), {TextTransparency = 1}):Play()
	end
end

local lCTk = {}
local function qDiag(c)
	if sDwn then return end
	if lCTk[c] and tick() - lCTk[c] < 7.5 then return end 
	lCTk[c] = tick()
	local l = dLines[c]
	if l then
		table.insert(cQ, l[math.random(1, #l)])
		if not isC then task.spawn(pChat) end
	end
end

local lHp = 0
local lHTk = tick()
local lLDTk = 0
local lSLTk = 0

local function bZLog(c)
	if not c then return end
	local hum = c:WaitForChild("Humanoid", 5)
	if not hum then return end
	lHp = hum.Health
	lHTk = tick()
	hum.HealthChanged:Connect(function(nh)
		if sDwn then return end
		local diff = nh - lHp
		if diff < 0 then
			lHTk = tick()
			if nh <= 0 then qDiag("Dead") elseif nh == 2 then qDiag("Health2") elseif nh == 1 then qDiag("Health1") end
		elseif diff > 0 then
			if diff <= 1 then qDiag("HealMinor") else qDiag("HealMajor") end
		end
		lHp = nh
	end)
end

if plr.Character then bZLog(plr.Character) end
plr.CharacterAdded:Connect(bZLog)

task.spawn(function()
	while task.wait(50) do
		if sDwn then break end
		if not isC and act and math.random() > 0.45 then qDiag("Casual") end
	end
end)

local tCEles = {}

local function bCrn(pFrm, iT, iL)
	local cs = 12
	local th = 2
	local os = 1 
	local cFrm = Instance.new("Frame")
	cFrm.Size = UDim2.new(0, cs, 0, cs)
	cFrm.BackgroundTransparency = 1
	cFrm.ZIndex = 6
	cFrm.AnchorPoint = Vector2.new(iL and 1 or 0, iT and 1 or 0)
	cFrm.Position = UDim2.new(iL and 0 or 1, iL and -os or os, iT and 0 or 1, iT and -os or os)
	cFrm.Parent = pFrm
	local lH = Instance.new("Frame")
	lH.Size = UDim2.new(1, 0, 0, th)
	lH.Position = UDim2.new(0, 0, iT and 0 or 1, iT and 0 or -th)
	lH.BackgroundColor3 = cIna
	lH.BorderSizePixel = 0
	lH.Parent = cFrm
	table.insert(tCEles, lH)
	local lV = Instance.new("Frame")
	lV.Size = UDim2.new(0, th, 1, 0)
	lV.Position = UDim2.new(iL and 0 or 1, iL and 0 or -th, 0, 0)
	lV.BackgroundColor3 = cIna
	lV.BorderSizePixel = 0
	lV.Parent = cFrm
	table.insert(tCEles, lV)
	return cFrm
end

local rWrp = Instance.new("Frame")
rWrp.Size = UDim2.new(0, 118, 0, 118)
rWrp.Position = UDim2.new(1, -138, 1, -138)
rWrp.BackgroundTransparency = 1
rWrp.Active = true
rWrp.Draggable = true
rWrp.Parent = gui

local rFrm = Instance.new("Frame")
rFrm.Size = UDim2.new(1, 0, 1, 0)
rFrm.BackgroundColor3 = cBg
rFrm.BorderSizePixel = 0 
rFrm.ZIndex = 1
rFrm.ClipsDescendants = true 
rFrm.Parent = rWrp

local rCrn = Instance.new("UICorner")
rCrn.CornerRadius = UDim.new(1, 0)
rCrn.Parent = rFrm

local rOStr = Instance.new("UIStroke")
rOStr.Thickness = 2
rOStr.Color = cIna
rOStr.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
rOStr.Parent = rFrm

local function cRCrn(iT, iL)
	local cs = 12
	local th = 2
	local os = -2 
	local cFrm = Instance.new("Frame")
	cFrm.Size = UDim2.new(0, cs, 0, cs)
	cFrm.BackgroundTransparency = 1
	cFrm.ZIndex = 6
	cFrm.AnchorPoint = Vector2.new(iL and 0 or 1, iT and 0 or 1)
	cFrm.Position = UDim2.new(iL and 0 or 1, iL and os or -os, iT and 0 or 1, iT and os or -os)
	cFrm.Parent = rWrp
	local lH = Instance.new("Frame")
	lH.Size = UDim2.new(1, 0, 0, th)
	lH.Position = UDim2.new(0, 0, iT and 0 or 1, iT and 0 or -th)
	lH.BackgroundColor3 = cIna
	lH.BorderSizePixel = 0
	lH.Parent = cFrm
	table.insert(tCEles, lH)
	local lV = Instance.new("Frame")
	lV.Size = UDim2.new(0, th, 1, 0)
	lV.Position = UDim2.new(iL and 0 or 1, iL and 0 or -th, 0, 0)
	lV.BackgroundColor3 = cIna
	lV.BorderSizePixel = 0
	lV.Parent = cFrm
	table.insert(tCEles, lV)
end

cRCrn(true, true)
cRCrn(true, false)
cRCrn(false, true)
cRCrn(false, false)

local rCont = Instance.new("Frame")
rCont.Size = UDim2.new(1, 0, 1, 0)
rCont.BackgroundTransparency = 1
rCont.ZIndex = 1
rCont.Parent = rFrm

local rLyrs = {}
local lCnt = 20

for i = lCnt, 1, -1 do
	local r = i / lCnt
	local l = Instance.new("Frame")
	l.Size = UDim2.new(r, 0, r, 0)
	l.Position = UDim2.new(0.5, 0, 0.5, 0)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BorderSizePixel = 0
	l.ZIndex = 1
	l.Parent = rCont
	local lC = Instance.new("UICorner")
	lC.CornerRadius = UDim.new(1, 0)
	lC.Parent = l
	local cL = Color3.fromRGB(math.floor((160 * 0.25) * (r^2)), math.floor((50 * 0.25) * (r^2)), math.floor((255 * 0.25) * (r^2)))
	l.BackgroundColor3 = cL
	l.BackgroundTransparency = 1
	table.insert(rLyrs, {instance = l, ratio = r, color = cL})
end

local cV = Instance.new("Frame")
cV.Size = UDim2.new(0, 2, 1, 0)
cV.Position = UDim2.new(0.5, 0, 0, 0)
cV.AnchorPoint = Vector2.new(0.5, 0)
cV.BackgroundColor3 = cIna
cV.BackgroundTransparency = 0.65
cV.BorderSizePixel = 0
cV.ZIndex = 2
cV.Parent = rFrm

local cH = Instance.new("Frame")
cH.Size = UDim2.new(1, 0, 0, 2)
cH.Position = UDim2.new(0.5, 0, 0.5, 0)
cH.AnchorPoint = Vector2.new(0.5, 0.5)
cH.BackgroundColor3 = cIna
cH.BackgroundTransparency = 0.65
cH.BorderSizePixel = 0
cH.ZIndex = 2
cH.Parent = rFrm

local rRngs = {}
for i = 1, 2 do
	local rg = Instance.new("Frame")
	local sr = i / 3
	rg.Size = UDim2.new(sr, 0, sr, 0)
	rg.Position = UDim2.new(0.5, 0, 0.5, 0)
	rg.AnchorPoint = Vector2.new(0.5, 0.5)
	rg.BackgroundTransparency = 1
	rg.ZIndex = 2
	rg.Parent = rFrm
	local rgC = Instance.new("UICorner")
	rgC.CornerRadius = UDim.new(1, 0)
	rgC.Parent = rg
	local rgS = Instance.new("UIStroke")
	rgS.Color = cIna
	rgS.Thickness = 1
	rgS.Transparency = 0.75
	rgS.Parent = rg
	table.insert(rRngs, rgS)
end

local sPiv = Instance.new("Frame")
sPiv.Size = UDim2.new(1, 0, 1, 0)
sPiv.Position = UDim2.new(0.5, 0, 0.5, 0)
sPiv.AnchorPoint = Vector2.new(0.5, 0.5)
sPiv.BackgroundTransparency = 1
sPiv.ZIndex = 3
sPiv.Parent = rFrm

local rScan = Instance.new("Frame")
rScan.Size = UDim2.new(0.5, 0, 0, 2)
rScan.Position = UDim2.new(0.5, 0, 0.5, 0)
rScan.AnchorPoint = Vector2.new(0, 0.5) 
rScan.BackgroundColor3 = cIna
rScan.BackgroundTransparency = 0.1
rScan.BorderSizePixel = 0
rScan.ZIndex = 3
rScan.Parent = sPiv

local sGrd = Instance.new("UIGradient")
sGrd.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0)})
sGrd.Parent = rScan

local rCen = Instance.new("Frame")
rCen.Size = UDim2.new(0, 4, 0, 4)
rCen.Position = UDim2.new(0.5, 0, 0.5, 0)
rCen.AnchorPoint = Vector2.new(0.5, 0.5)
rCen.BackgroundColor3 = cIna
rCen.BorderSizePixel = 0
rCen.ZIndex = 5
rCen.Parent = rFrm

local cCCrn = Instance.new("UICorner")
cCCrn.CornerRadius = UDim.new(1, 0)
cCCrn.Parent = rCen

local rBlps = Instance.new("Frame")
rBlps.Size = UDim2.new(1, 0, 1, 0)
rBlps.BackgroundTransparency = 1
rBlps.ZIndex = 4
rBlps.Parent = rFrm

local mFrm = Instance.new("Frame")
mFrm.Size = UDim2.new(0, 124, 0, 72)
mFrm.Position = UDim2.new(1, -144, 0, 24)
mFrm.BackgroundColor3 = cBg
mFrm.BorderSizePixel = 0
mFrm.Active = true
mFrm.Parent = gui

local mCrn = Instance.new("UICorner")
mCrn.CornerRadius = UDim.new(0, 4)
mCrn.Parent = mFrm

local sOn = Instance.new("Sound")
sOn.SoundId = "rbxassetid://6895079853"
sOn.Volume = 0.5
sOn.Parent = mFrm

local sOff = Instance.new("Sound")
sOff.SoundId = "rbxassetid://6895079853"
sOff.PlaybackSpeed = 0.8
sOff.Volume = 0.5
sOff.Parent = mFrm

local oStr = Instance.new("UIStroke")
oStr.Thickness = 1.5
oStr.Color = cIna
oStr.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
oStr.Parent = mFrm

local iBrd = Instance.new("Frame")
iBrd.Size = UDim2.new(1, -8, 1, -8)
iBrd.Position = UDim2.new(0, 4, 0, 4)
iBrd.BackgroundTransparency = 1
iBrd.BorderSizePixel = 0
iBrd.Parent = mFrm

local iCrn = Instance.new("UICorner")
iCrn.CornerRadius = UDim.new(0, 3)
iCrn.Parent = iBrd

local iStr = Instance.new("UIStroke")
iStr.Thickness = 1
iStr.Color = cIna
iStr.Transparency = 0.75
iStr.Parent = iBrd

local hTag = Instance.new("TextLabel")
hTag.Size = UDim2.new(1, 0, 0, 12)
hTag.Position = UDim2.new(0, 0, 0, -15)
hTag.BackgroundTransparency = 1
hTag.Text = "// WEEPING.LAKE //"
hTag.TextColor3 = cIna
hTag.Font = Enum.Font.Code
hTag.TextSize = 9
hTag.TextXAlignment = Enum.TextXAlignment.Center
hTag.Active = true
hTag.Parent = mFrm

local bHdr = Instance.new("TextLabel")
bHdr.Size = UDim2.new(1, 0, 0, 12)
bHdr.Position = UDim2.new(0, 0, 1, 3)
bHdr.BackgroundTransparency = 1
bHdr.Text = "// TOGGLES //"
bHdr.TextColor3 = cIna
bHdr.Font = Enum.Font.Code
bHdr.TextSize = 9
bHdr.TextXAlignment = Enum.TextXAlignment.Center
bHdr.Active = true
bHdr.Parent = mFrm

local eFrm = Instance.new("Frame")
eFrm.Size = UDim2.new(1, 0, 0, 0)
eFrm.Position = UDim2.new(0, 0, 1, 18)
eFrm.BackgroundColor3 = cBg
eFrm.BorderSizePixel = 0
eFrm.ClipsDescendants = true
eFrm.Parent = mFrm

local eCrn = Instance.new("UICorner")
eCrn.CornerRadius = UDim.new(0, 4)
eCrn.Parent = eFrm

local eOStr = Instance.new("UIStroke")
eOStr.Thickness = 1.5
eOStr.Color = cIna
eOStr.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
eOStr.Transparency = 1
eOStr.Parent = eFrm

local eSL = Instance.new("Frame")
eSL.Size = UDim2.new(0, 1, 1, 0)
eSL.Position = UDim2.new(0, 4, 0, 0)
eSL.BackgroundColor3 = cIna
eSL.BackgroundTransparency = 1
eSL.BorderSizePixel = 0
eSL.ZIndex = 2
eSL.Parent = eFrm

local eSR = Instance.new("Frame")
eSR.Size = UDim2.new(0, 1, 1, 0)
eSR.Position = UDim2.new(1, -5, 0, 0)
eSR.BackgroundColor3 = cIna
eSR.BackgroundTransparency = 1
eSR.BorderSizePixel = 0
eSR.ZIndex = 2
eSR.Parent = eFrm

local tCont = Instance.new("ScrollingFrame")
tCont.Size = UDim2.new(1, 0, 1, 0)
tCont.BackgroundTransparency = 1
tCont.BorderSizePixel = 0
tCont.ScrollBarThickness = 2
tCont.ScrollBarImageColor3 = cIna
tCont.ZIndex = 3
tCont.Parent = eFrm

local eLst = Instance.new("UIListLayout")
eLst.Padding = UDim.new(0, 4)
eLst.HorizontalAlignment = Enum.HorizontalAlignment.Center
eLst.VerticalAlignment = Enum.VerticalAlignment.Top
eLst.Parent = tCont

eLst:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	tCont.CanvasSize = UDim2.new(0, 0, 0, eLst.AbsoluteContentSize.Y + 12)
end)

local ePad = Instance.new("UIPadding")
ePad.PaddingTop = UDim.new(0, 6)
ePad.Parent = tCont

local sTxt = Instance.new("TextLabel")
sTxt.Size = UDim2.new(1, 0, 1, 0)
sTxt.BackgroundTransparency = 1
sTxt.Text = "<0>"
sTxt.TextColor3 = cIna
sTxt.Font = Enum.Font.Code
sTxt.TextSize = 28
sTxt.ZIndex = 3
sTxt.Parent = mFrm

local sLin = Instance.new("Frame")
sLin.Size = UDim2.new(1, 0, 1, 0)
sLin.BackgroundTransparency = 0.88
sLin.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
sLin.BorderSizePixel = 0
sLin.ZIndex = 4
sLin.Parent = mFrm

local sLCrn = Instance.new("UICorner")
sLCrn.CornerRadius = UDim.new(0, 4)
sLCrn.Parent = sLin

local sLGrd = Instance.new("UIGradient")
sLGrd.Rotation = 90
sLGrd.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 25, 25)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)), ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 25, 25))})
sLGrd.Parent = sLin

bCrn(mFrm, true, true)
bCrn(mFrm, true, false)
bCrn(eFrm, false, true)
bCrn(eFrm, false, false)

local shFrm = Instance.new("Frame")
shFrm.Size = UDim2.new(0, 160, 0, 60)
shFrm.Position = UDim2.new(0, 20, 0.5, -55)
shFrm.BackgroundColor3 = cBg
shFrm.BorderSizePixel = 0
shFrm.Visible = cfg.Stat_HUD
shFrm.Active = true
shFrm.Draggable = true
shFrm.Parent = gui

local shCrn = Instance.new("UICorner")
shCrn.CornerRadius = UDim.new(0, 4)
shCrn.Parent = shFrm

local shOStr = Instance.new("UIStroke")
shOStr.Thickness = 1.5
shOStr.Color = cIna
shOStr.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
shOStr.Parent = shFrm

local shIBrd = Instance.new("Frame")
shIBrd.Size = UDim2.new(1, -8, 1, -8)
shIBrd.Position = UDim2.new(0, 4, 0, 4)
shIBrd.BackgroundTransparency = 1
shIBrd.BorderSizePixel = 0
shIBrd.ZIndex = 2
shIBrd.Parent = shFrm

local shICrn = Instance.new("UICorner")
shICrn.CornerRadius = UDim.new(0, 3)
shICrn.Parent = shIBrd

local shIStr = Instance.new("UIStroke")
shIStr.Thickness = 1
shIStr.Color = cIna
shIStr.Transparency = 0.75
shIStr.Parent = shIBrd

bCrn(shFrm, true, true)
bCrn(shFrm, true, false)
bCrn(shFrm, false, true)
bCrn(shFrm, false, false)

local shTit = Instance.new("TextLabel")
shTit.Size = UDim2.new(1, -12, 0, 16)
shTit.Position = UDim2.new(0, 6, 0, 3)
shTit.BackgroundTransparency = 1
shTit.Text = "[ FLOOR STATISTICS ]"
shTit.TextColor3 = cIna
shTit.Font = Enum.Font.Code
shTit.TextSize = 9
shTit.TextXAlignment = Enum.TextXAlignment.Left
shTit.ZIndex = 3
shTit.Parent = shFrm

local shDiv = Instance.new("Frame")
shDiv.Size = UDim2.new(1, -12, 0, 1)
shDiv.Position = UDim2.new(0, 6, 0, 20)
shDiv.BackgroundColor3 = cIna
shDiv.BackgroundTransparency = 0.5
shDiv.BorderSizePixel = 0
shDiv.ZIndex = 3
shDiv.Parent = shFrm

local shBod = Instance.new("TextLabel")
shBod.Size = UDim2.new(1, -12, 1, -26)
shBod.Position = UDim2.new(0, 6, 0, 23)
shBod.BackgroundTransparency = 1
shBod.TextColor3 = cDim
shBod.Font = Enum.Font.Code
shBod.TextSize = 9
shBod.TextXAlignment = Enum.TextXAlignment.Left
shBod.TextYAlignment = Enum.TextYAlignment.Top
shBod.ZIndex = 3
shBod.Parent = shFrm

local function rmESP(t)
	if not t then return end
	local hl = t:FindFirstChild("OWL_ESP_HL")
	local bg = t:FindFirstChild("OWL_ESP_BG")
	if hl then hl:Destroy() end
	if bg then bg:Destroy() end
end

local function aESP(t, eT, lT)
	if not t then return end
	local aM = t:IsA("Model") and t or t:FindFirstAncestorOfClass("Model") or t
	if aM:FindFirstChild("OWL_ESP_HL") or t:FindFirstChild("OWL_ESP_HL") then return end
	if eT == "Machine" then
		local iD = false
		local pt = t:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pt then iD = not pt.Enabled end
		if iD then rmESP(aM) return end
	end
	
	local hl = Instance.new("Highlight")
	hl.Name = "OWL_ESP_HL"
	hl.FillTransparency = 0.55
	hl.Adornee = aM
	hl.Parent = aM

	local bg = Instance.new("BillboardGui")
	bg.Name = "OWL_ESP_BG"
	bg.Size = UDim2.new(0, 95, 0, 18)
	bg.StudsOffset = Vector3.new(0, 3.5, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = aM:FindFirstChild("HumanoidRootPart") or aM.PrimaryPart or aM:FindFirstChildWhichIsA("BasePart") or t
	bg.Parent = aM

	local hF = Instance.new("Frame")
	hF.Size = UDim2.new(1, 0, 1, 0)
	hF.BackgroundTransparency = 0.8
	hF.BorderSizePixel = 0
	hF.Parent = bg

	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = hF

	local tx = Instance.new("TextLabel")
	tx.Size = UDim2.new(1, 0, 1, 0)
	tx.BackgroundTransparency = 1
	tx.Font = Enum.Font.Code
	tx.TextScaled = true
	tx.Parent = hF

	if eT == "Monster" then
		hl.FillColor = cAct
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hF.BackgroundColor3 = Color3.fromRGB(20, 0, 30)
		tx.TextColor3 = Color3.fromRGB(210, 160, 255)
		local cN = string.gsub(string.gsub(string.gsub(string.lower(aM.Name), "monster", ""), "twisted", ""), "^%s*(.-)%s*$", "%1")
		tx.Text = cN ~= "" and string.upper(string.sub(cN, 1, 1)) .. string.sub(cN, 2) or "Twisted"
	elseif eT == "Machine" then
		hl.FillColor = Color3.fromRGB(0, 0, 0)
		hl.OutlineColor = cAct
		hF.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		tx.TextColor3 = cAct
		tx.Text = "Machine"
	elseif eT == "Item" then
		hl.FillColor = Color3.fromRGB(0, 0, 0)
		hl.OutlineColor = Color3.fromRGB(255, 255, 255)
		hF.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		tx.TextColor3 = Color3.fromRGB(255, 255, 255)
		tx.Text = lT or "Item"
	elseif eT == "Player" then
		hl.FillColor = Color3.fromRGB(255, 255, 255)
		hl.OutlineColor = cAct
		hF.BackgroundColor3 = Color3.fromRGB(10, 0, 15)
		tx.TextColor3 = cAct
		tx.Text = lT or aM.Name
	end
	table.insert(eObjs[eT], hl)
	table.insert(eObjs[eT], bg)
end

local function rmESPT(eT)
	for _, o in ipairs(eObjs[eT]) do if o and o.Parent then o:Destroy() end end
	table.clear(eObjs[eT])
end

local function sAESP()
	if cfg.Twisted_ESP then for d in pairs(tEnts.Twisteds) do if isTw(d) then aESP(d, "Monster") end end end
	if cfg.Machine_ESP or cfg.Item_ESP then
		for d in pairs(tEnts.Machines) do if cfg.Machine_ESP then aESP(d, "Machine") end end
		for d in pairs(tEnts.Prompts) do
			if cfg.Item_ESP and d.ActionText ~= "Ichor" and d.ActionText ~= "" then
				if d.Enabled and isItm(d.ActionText) then aESP(d.Parent, "Item", d.ActionText) else rmESP(d.Parent) end
			end
		end
	end
	if cfg.Player_ESP then for _, p in ipairs(pls:GetPlayers()) do if p ~= plr and p.Character then aESP(p.Character, "Player", p.DisplayName or p.Name) end end end
end

local function aMaL(m, p)
	p:GetPropertyChangedSignal("Enabled"):Connect(function()
		if cfg.Machine_ESP then if not p.Enabled then rmESP(m) else aESP(m, "Machine") end end
	end)
end

local function rMa(d)
	if tEnts.Machines[d] then return end
	tEnts.Machines[d] = true
	local p = d:FindFirstChildWhichIsA("ProximityPrompt", true)
	if p then aMaL(d, p) end
	d.DescendantAdded:Connect(function(c) if c:IsA("ProximityPrompt") then aMaL(d, c) end end)
end

local function tPrmpt(p)
	if pCons[p] then return end
	if env.P[p] == nil then env.P[p] = p.HoldDuration end

	pCons[p] = p:GetPropertyChangedSignal("Enabled"):Connect(function()
		if p.ActionText ~= "Ichor" and p.ActionText ~= "" then
			if not p.Enabled then 
				rmESP(p.Parent) 
			elseif cfg.Item_ESP and isItm(p.ActionText) then 
				aESP(p.Parent, "Item", p.ActionText) 
			end
		end
	end)
end

local function uPrmpt()
	for d in pairs(tEnts.Prompts) do
		if cfg.Instant_Interact then
			if env.P[d] == nil then env.P[d] = d.HoldDuration end
			d.HoldDuration = 0
		else
			if env.P[d] ~= nil then d.HoldDuration = env.P[d] end
		end
	end
end

local function eTog(id, st)
	cfg[id] = st
	if id == "Fullbright" then if not st then rLgt() end
	elseif id == "Twisted_ESP" then if st then sAESP() else rmESPT("Monster") end
	elseif id == "Machine_ESP" then if st then sAESP() else rmESPT("Machine") end
	elseif id == "Item_ESP" then if st then sAESP() else rmESPT("Item") end
	elseif id == "Player_ESP" then if st then sAESP() else rmESPT("Player") end
	elseif id == "Stat_HUD" then shFrm.Visible = st
	elseif id == "Instant_Interact" then uPrmpt() end
end

local aFMenu = nil
local function cFMenu(tT, fT, fL)
	if aFMenu then aFMenu:Destroy() aFMenu = nil end
	local fF = Instance.new("Frame")
	fF.Size = UDim2.new(0, 140, 0, 180)
	fF.Position = UDim2.new(1, -260, 0, 24)
	fF.BackgroundColor3 = cBg
	fF.BorderSizePixel = 0
	fF.Active = true
	fF.Draggable = true
	fF.ZIndex = 10
	fF.Parent = gui
	aFMenu = fF

	local fC = Instance.new("UICorner")
	fC.CornerRadius = UDim.new(0, 4)
	fC.Parent = fF

	local fS = Instance.new("UIStroke")
	fS.Color = act and cAct or cIna
	fS.Thickness = 1.5
	fS.Parent = fF

	bCrn(fF, true, true)
	bCrn(fF, true, false)
	bCrn(fF, false, true)
	bCrn(fF, false, false)

	local fSc = Instance.new("ScrollingFrame")
	fSc.Size = UDim2.new(1, -8, 1, -26)
	fSc.Position = UDim2.new(0, 4, 0, 22)
	fSc.BackgroundColor3 = cPBg
	fSc.BorderSizePixel = 0
	fSc.ScrollBarThickness = 2
	fSc.ScrollBarImageColor3 = act and cAct or cIna
	fSc.CanvasSize = UDim2.new(0, 0, 0, #fL * 16)
	fSc.Parent = fF

	local sC = Instance.new("UICorner")
	sC.CornerRadius = UDim.new(0, 3)
	sC.Parent = fSc

	local fTl = Instance.new("TextLabel")
	fTl.Size = UDim2.new(1, -25, 0, 20)
	fTl.Position = UDim2.new(0, 6, 0, 0)
	fTl.BackgroundTransparency = 1
	fTl.Text = "// " .. string.upper(tT) .. " //"
	fTl.TextColor3 = act and cAct or cIna
	fTl.Font = Enum.Font.Code
	fTl.TextSize = 9
	fTl.TextXAlignment = Enum.TextXAlignment.Left
	fTl.Parent = fF

	local fCl = Instance.new("TextLabel")
	fCl.Size = UDim2.new(0, 16, 0, 16)
	fCl.Position = UDim2.new(1, -18, 0, 2)
	fCl.BackgroundTransparency = 1
	fCl.Text = "X"
	fCl.TextColor3 = Color3.fromRGB(255, 80, 80)
	fCl.Font = Enum.Font.Code
	fCl.TextSize = 10
	fCl.Active = true
	fCl.Parent = fF
	fCl.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then fF:Destroy() aFMenu = nil end end)

	local fLy = Instance.new("UIListLayout")
	fLy.Padding = UDim.new(0, 2)
	fLy.Parent = fSc

	for _, n in ipairs(fL) do
		local k = string.lower(n)
		local iB = Instance.new("TextLabel")
		iB.Size = UDim2.new(1, -4, 0, 14)
		iB.BackgroundTransparency = 1
		iB.Text = (fT[k] and "[#] " or "[ ] ") .. n
		iB.TextColor3 = fT[k] and Color3.fromRGB(210, 160, 255) or Color3.fromRGB(100, 100, 110)
		iB.Font = Enum.Font.Code
		iB.TextSize = 8
		iB.TextXAlignment = Enum.TextXAlignment.Left
		iB.Active = true
		iB.Parent = fSc
		iB.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				fT[k] = not fT[k]
				iB.Text = (fT[k] and "[#] " or "[ ] ") .. n
				iB.TextColor3 = fT[k] and Color3.fromRGB(210, 160, 255) or Color3.fromRGB(100, 100, 110)
				if tT == "Twisted Filter" and cfg.Twisted_ESP then rmESPT("Monster") sAESP()
				elseif tT == "Item Filter" and cfg.Item_ESP then rmESPT("Item") sAESP() end
			end
		end)
	end
end

local function cTog(t, id, o, fD)
	local w = Instance.new("Frame")
	w.Size = UDim2.new(1, -8, 0, 14)
	w.BackgroundTransparency = 1
	w.BorderSizePixel = 0
	w.LayoutOrder = o
	w.Parent = tCont

	local cB = Instance.new("TextLabel")
	cB.Size = UDim2.new(0, 20, 1, 0)
	cB.BackgroundColor3 = Color3.fromRGB(15, 8, 25)
	cB.BackgroundTransparency = 0.5
	cB.BorderSizePixel = 0
	cB.Text = cfg[id] and "[#]" or "[ ]"
	cB.TextColor3 = cIna
	cB.TextTransparency = 1
	cB.Font = Enum.Font.Code
	cB.TextSize = 9
	cB.TextXAlignment = Enum.TextXAlignment.Center
	cB.Active = true
	cB.Parent = w

	local bC = Instance.new("UICorner")
	bC.CornerRadius = UDim.new(0, 3)
	bC.Parent = cB

	local bS = Instance.new("UIStroke")
	bS.Thickness = 1
	bS.Color = cIna
	bS.Transparency = 0.7
	bS.Parent = cB

	local tL = Instance.new("TextLabel")
	tL.Size = UDim2.new(1, fD and -38 or -24, 1, 0)
	tL.Position = UDim2.new(0, 22, 0, 0)
	tL.BackgroundTransparency = 1
	tL.Text = t
	tL.TextColor3 = cIna
	tL.TextTransparency = 1
	tL.Font = Enum.Font.Code
	tL.TextSize = 9
	tL.TextXAlignment = Enum.TextXAlignment.Left
	tL.Active = false
	tL.Parent = w

	local cSP = nil
	cB.InputBegan:Connect(function(i) if sDwn then return end if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then cSP = i.Position end end)
	cB.InputEnded:Connect(function(i)
		if sDwn or not cSP then return end
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			local dist = (i.Position - cSP).Magnitude
			cSP = nil
			if dist < 6 then
				local nS = not cfg[id]
				cB.Text = nS and "[#]" or "[ ]"
				eTog(id, nS)
			end
		end
	end)

	table.insert(tLst, {label = tL, badge = cB, stroke = bS})

	if fD then
		local aB = Instance.new("TextLabel")
		aB.Size = UDim2.new(0, 14, 1, 0)
		aB.Position = UDim2.new(1, -14, 0, 0)
		aB.BackgroundTransparency = 1
		aB.Text = ">"
		aB.TextColor3 = cIna
		aB.TextTransparency = 1
		aB.Font = Enum.Font.Code
		aB.TextSize = 10
		aB.Active = true
		aB.Parent = w

		local aSP = nil
		aB.InputBegan:Connect(function(i)
			if sDwn then return end
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				aSP = i.Position
			end
		end)

		aB.InputEnded:Connect(function(i)
			if sDwn or not aSP then return end
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				local dist = (i.Position - aSP).Magnitude
				aSP = nil
				if dist < 6 then
					cFMenu(fD.title, fD.table, fD.list)
				end
			end
		end)
		table.insert(tLst, {arrow = aB})
	end
end

cTog("Fullbright", "Fullbright", 1)
cTog("Twisted_ESP", "Twisted_ESP", 2, {title = "Twisted Filter", table = mFlts, list = mLst})
cTog("Machine_ESP", "Machine_ESP", 3)
cTog("Item_ESP", "Item_ESP", 4, {title = "Item Filter", table = iFlts, list = iLst})
cTog("Player_ESP", "Player_ESP", 5)
cTog("Stat_HUD", "Stat_HUD", 6)
cTog("Instant_Interact", "Instant_Interact", 7)
cTog("Auto_Escape", "Auto_Escape", 8)
cTog("Hide_Radar", "Hide_Radar", 9)

local fTI = TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local cBlps = {} 

local function uUI()
	if sDwn then return end
	local tC = act and cAct or cIna
	local ti = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	task.spawn(function()
		if not min then tws:Create(sTxt, fTI, {TextTransparency = 1}):Play() task.wait(0.15) end
		sTxt.Text = act and "<0>" or "<X>"
		if not min and not sDwn then tws:Create(sTxt, fTI, {TextTransparency = 0}):Play() end
	end)

	tws:Create(sTxt, ti, {TextColor3 = tC}):Play()
	tws:Create(oStr, ti, {Color = tC}):Play()
	tws:Create(hTag, ti, {TextColor3 = tC}):Play()
	tws:Create(bHdr, ti, {TextColor3 = tC}):Play()
	
	tws:Create(shOStr, ti, {Color = tC}):Play()
	tws:Create(shIStr, ti, {Color = tC, Transparency = act and 0.5 or 0.8}):Play()
	tws:Create(shTit, ti, {TextColor3 = tC}):Play()
	tws:Create(shDiv, ti, {BackgroundColor3 = tC}):Play()
	
	tws:Create(rOStr, ti, {Color = tC}):Play()
	for _, t in ipairs(tCEles) do tws:Create(t, ti, {BackgroundColor3 = tC}):Play() end
	tws:Create(cV, ti, {BackgroundColor3 = tC}):Play()
	tws:Create(cH, ti, {BackgroundColor3 = tC}):Play()
	tws:Create(rScan, ti, {BackgroundColor3 = tC}):Play()
	tws:Create(rCen, ti, {BackgroundColor3 = tC}):Play()
	tws:Create(tCont, ti, {ScrollBarImageColor3 = tC}):Play()
	for _, r in ipairs(rRngs) do tws:Create(r, ti, {Color = tC}):Play() end
	
	for _, l in ipairs(rLyrs) do
		if act then
			tws:Create(l.instance, ti, {BackgroundColor3 = l.color, BackgroundTransparency = 0.88 + (0.09 * (1 - math.clamp(l.ratio, 0, 1)))}):Play()
		else
			tws:Create(l.instance, ti, {BackgroundTransparency = 1}):Play()
		end
	end

	for _, b in pairs(cBlps) do
		local s = b:FindFirstChildOfClass("UIStroke")
		local tb, ts
		if act then
			if b.Name == "Twisted" then tb = Color3.fromRGB(0, 0, 0); ts = cAct
			elseif b.Name == "Player" then tb = Color3.fromRGB(255, 255, 255); ts = cAct
			elseif b.Name == "Machine" then tb = cAct; ts = Color3.fromRGB(0, 0, 0) end
		else
			if b.Name == "Twisted" then tb = Color3.fromRGB(130, 130, 130); ts = Color3.fromRGB(255, 255, 255)
			elseif b.Name == "Player" then tb = Color3.fromRGB(255, 255, 255); ts = Color3.fromRGB(0, 0, 0)
			elseif b.Name == "Machine" then tb = Color3.fromRGB(0, 0, 0); ts = Color3.fromRGB(255, 255, 255) end
		end
		if tb then tws:Create(b, ti, {BackgroundColor3 = tb}):Play() end
		if s and ts then tws:Create(s, ti, {Color = ts}):Play() end
	end
	
	for _, i in ipairs(tLst) do 
		if i.label then tws:Create(i.label, ti, {TextColor3 = tC}):Play() end
		if i.badge then tws:Create(i.badge, ti, {TextColor3 = tC}):Play() end
		if i.stroke then tws:Create(i.stroke, ti, {Color = tC}):Play() end
		if i.arrow then tws:Create(i.arrow, ti, {TextColor3 = tC}):Play() end
	end
	if not min then
		tws:Create(iStr, ti, {Color = tC, Transparency = act and 0.5 or 0.8}):Play()
		if tOpn then 
			tws:Create(eOStr, ti, {Color = tC}):Play()
			tws:Create(eSL, ti, {BackgroundColor3 = tC, BackgroundTransparency = act and 0.5 or 0.8}):Play()
			tws:Create(eSR, ti, {BackgroundColor3 = tC, BackgroundTransparency = act and 0.5 or 0.8}):Play()
		end
	end
end

local function tExt()
	if min or sDwn then return end
	tOpn = not tOpn
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if tOpn then
		tws:Create(eFrm, ti, {Size = UDim2.new(1, 0, 0, 155)}):Play()
		tws:Create(eOStr, ti, {Transparency = 0, Color = act and cAct or cIna}):Play()
		tws:Create(eSL, ti, {BackgroundTransparency = act and 0.5 or 0.8, BackgroundColor3 = act and cAct or cIna}):Play()
		tws:Create(eSR, ti, {BackgroundTransparency = act and 0.5 or 0.8, BackgroundColor3 = act and cAct or cIna}):Play()
		for _, i in ipairs(tLst) do 
			if i.label then tws:Create(i.label, ti, {TextTransparency = 0}):Play() end
			if i.badge then tws:Create(i.badge, ti, {TextTransparency = 0}):Play() end
			if i.arrow then tws:Create(i.arrow, ti, {TextTransparency = 0}):Play() end
		end
	else
		tws:Create(eFrm, ti, {Size = UDim2.new(1, 0, 0, 0)}):Play()
		tws:Create(eOStr, ti, {Transparency = 1}):Play()
		tws:Create(eSL, ti, {BackgroundTransparency = 1}):Play()
		tws:Create(eSR, ti, {BackgroundTransparency = 1}):Play()
		for _, i in ipairs(tLst) do 
			if i.label then tws:Create(i.label, ti, {TextTransparency = 1}):Play() end
			if i.badge then tws:Create(i.badge, ti, {TextTransparency = 1}):Play() end
			if i.arrow then tws:Create(i.arrow, ti, {TextTransparency = 1}):Play() end
		end
		if aFMenu then aFMenu:Destroy() aFMenu = nil end
	end
end

local function tMin()
	min = not min
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if min then
		tws:Create(mFrm, ti, {Size = UDim2.new(0, 124, 0, 0)}):Play()
		tws:Create(sTxt, ti, {TextTransparency = 1}):Play()
		tws:Create(sLin, ti, {BackgroundTransparency = 1}):Play()
		tws:Create(iStr, ti, {Transparency = 1}):Play()
		tws:Create(bHdr, ti, {TextTransparency = 1}):Play()
		if tOpn then
			tws:Create(eFrm, ti, {Size = UDim2.new(1, 0, 0, 0)}):Play()
			tws:Create(eOStr, ti, {Transparency = 1}):Play()
			tws:Create(eSL, ti, {BackgroundTransparency = 1}):Play()
			tws:Create(eSR, ti, {BackgroundTransparency = 1}):Play()
			for _, i in ipairs(tLst) do 
				if i.label then tws:Create(i.label, ti, {TextTransparency = 1}):Play() end
				if i.badge then tws:Create(i.badge, ti, {TextTransparency = 1}):Play() end
				if i.arrow then tws:Create(i.arrow, ti, {TextTransparency = 1}):Play() end
			end
			if aFMenu then aFMenu:Destroy() aFMenu = nil end
		end
	else
		tws:Create(mFrm, ti, {Size = UDim2.new(0, 124, 0, 72)}):Play()
		tws:Create(sTxt, ti, {TextTransparency = 0}):Play()
		tws:Create(sLin, ti, {BackgroundTransparency = 0.88}):Play()
		tws:Create(iStr, ti, {Transparency = act and 0.5 or 0.8}):Play()
		tws:Create(bHdr, ti, {TextTransparency = 0}):Play()
		if tOpn then
			tws:Create(eFrm, ti, {Size = UDim2.new(1, 0, 0, 155)}):Play()
			tws:Create(eOStr, ti, {Transparency = 0}):Play()
			tws:Create(eSL, ti, {BackgroundTransparency = act and 0.5 or 0.8, BackgroundColor3 = act and cAct or cIna}):Play()
			tws:Create(eSR, ti, {BackgroundTransparency = act and 0.5 or 0.8, BackgroundColor3 = act and cAct or cIna}):Play()
			for _, i in ipairs(tLst) do 
				if i.label then tws:Create(i.label, ti, {TextTransparency = 0}):Play() end
				if i.badge then tws:Create(i.badge, ti, {TextTransparency = 0}):Play() end
				if i.arrow then tws:Create(i.arrow, ti, {TextTransparency = 0}):Play() end
			end
		end
	end
end

local function tog()
	act = not act
	if not act then rMom() end
	if act then sOn:Play() else sOff:Play() end
	uUI()
end

local function wSys()
	sDwn = true
	rLgt()
	rPrmpt()
	rmESPT("Monster")
	rmESPT("Machine")
	rmESPT("Item")
	rmESPT("Player")
	cfg.Instant_Interact = false
	for _, c in ipairs(cons) do if c then c:Disconnect() end end
	for _, c in pairs(pCons) do if c then c:Disconnect() end end
	rMom()
	if gui then gui:Destroy() end
end

local drag, hDrag = false, false
local dSt, sPos, dInp
local isH, hTk = false, 0
local yTws = {}
local cWrn = Color3.fromRGB(255, 215, 0)

local function cYTw()
	for _, tw in ipairs(yTws) do tw:Cancel() end
	table.clear(yTws)
end

local function sYTw()
	cYTw()
	local ti = TweenInfo.new(3, Enum.EasingStyle.Linear)
	table.insert(yTws, tws:Create(sTxt, ti, {TextColor3 = cWrn}))
	table.insert(yTws, tws:Create(oStr, ti, {Color = cWrn}))
	table.insert(yTws, tws:Create(iStr, ti, {Color = cWrn}))
	table.insert(yTws, tws:Create(hTag, ti, {TextColor3 = cWrn}))
	table.insert(yTws, tws:Create(bHdr, ti, {TextColor3 = cWrn}))
	table.insert(yTws, tws:Create(tCont, ti, {ScrollBarImageColor3 = cWrn}))
	table.insert(yTws, tws:Create(shOStr, ti, {Color = cWrn}))
	table.insert(yTws, tws:Create(shIStr, ti, {Color = cWrn}))
	table.insert(yTws, tws:Create(shTit, ti, {TextColor3 = cWrn}))
	table.insert(yTws, tws:Create(shDiv, ti, {BackgroundColor3 = cWrn}))
	table.insert(yTws, tws:Create(rOStr, ti, {Color = cWrn}))
	for _, t in ipairs(tCEles) do table.insert(yTws, tws:Create(t, ti, {BackgroundColor3 = cWrn})) end
	table.insert(yTws, tws:Create(cV, ti, {BackgroundColor3 = cWrn}))
	table.insert(yTws, tws:Create(cH, ti, {BackgroundColor3 = cWrn}))
	table.insert(yTws, tws:Create(rScan, ti, {BackgroundColor3 = cWrn}))
	table.insert(yTws, tws:Create(rCen, ti, {BackgroundColor3 = cWrn}))
	for _, r in ipairs(rRngs) do table.insert(yTws, tws:Create(r, ti, {Color = cWrn})) end
	for _, l in ipairs(rLyrs) do
		local cW = Color3.fromRGB(math.floor((255 * 0.25) * (l.ratio^2)), math.floor((215 * 0.25) * (l.ratio^2)), 0)
		table.insert(yTws, tws:Create(l.instance, ti, {BackgroundColor3 = cW, BackgroundTransparency = 0.88 + (0.09 * (1 - math.clamp(l.ratio, 0, 1)))}))
	end
	for _, b in pairs(cBlps) do
		local s = b:FindFirstChildOfClass("UIStroke")
		table.insert(yTws, tws:Create(b, ti, {BackgroundColor3 = cWrn}))
		if s then table.insert(yTws, tws:Create(s, ti, {Color = cWrn})) end
	end
	for _, i in ipairs(tLst) do 
		if i.label then table.insert(yTws, tws:Create(i.label, ti, {TextColor3 = cWrn})) end
		if i.badge then table.insert(yTws, tws:Create(i.badge, ti, {TextColor3 = cWrn})) end
		if i.stroke then table.insert(yTws, tws:Create(i.stroke, ti, {Color = cWrn})) end
		if i.arrow then table.insert(yTws, tws:Create(i.arrow, ti, {TextColor3 = cWrn})) end
	end
	if tOpn then 
		table.insert(yTws, tws:Create(eOStr, ti, {Color = cWrn}))
		table.insert(yTws, tws:Create(eSL, ti, {BackgroundColor3 = cWrn}))
		table.insert(yTws, tws:Create(eSR, ti, {BackgroundColor3 = cWrn}))
	end
	for _, tw in ipairs(yTws) do tw:Play() end

	local tH = hTk
	task.delay(3, function()
		if isH and hTk == tH and not sDwn then
			sDwn = true
			cYTw()
			if act then act = false rMom() sOff:Play() end
			sTxt.Text = "<X>"
			local fO = TweenInfo.new(1)
			tws:Create(mFrm, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(sTxt, fO, {TextTransparency = 1}):Play()
			tws:Create(hTag, fO, {TextTransparency = 1}):Play()
			tws:Create(bHdr, fO, {TextTransparency = 1}):Play()
			tws:Create(sLin, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(oStr, fO, {Transparency = 1}):Play()
			tws:Create(iStr, fO, {Transparency = 1}):Play()
			tws:Create(eFrm, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(eOStr, fO, {Transparency = 1}):Play()
			tws:Create(eSL, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(eSR, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(zW, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(zS, fO, {Transparency = 1}):Play()
			tws:Create(zA, fO, {BackgroundTransparency = 1}):Play()
			tws:Create(zH, fO, {TextTransparency = 1}):Play()
			tws:Create(zT, fO, {TextTransparency = 1}):Play()
			for _, i in ipairs(tLst) do 
				if i.label then tws:Create(i.label, fO, {TextTransparency = 1}):Play() end
				if i.badge then tws:Create(i.badge, fO, {TextTransparency = 1}):Play() end
				if i.arrow then tws:Create(i.arrow, fO, {TextTransparency = 1}):Play() end
			end
			task.wait(1) wSys()
		end
	end)
end

local function hInp(i, r)
	if sDwn then return end
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		drag = true hDrag = false
		dSt = i.Position sPos = mFrm.Position dInp = i
		local cHT = tick()
		if r == "eye" and not min then isH = true hTk = cHT sYTw() end

		local eCn
		eCn = i.Changed:Connect(function()
			if i.UserInputState == Enum.UserInputState.End then
				drag = false isH = false
				if hTk == cHT and not sDwn then cYTw() uUI() end
				eCn:Disconnect()
				if not hDrag and not sDwn then
					if r == "header" then tMin() elseif r == "eye" then tog() elseif r == "bottom" then tExt() end
				end
			end
		end)
	end
end

headerTag.InputBegan:Connect(function(i) hInp(i, "header") end)
mFrm.InputBegan:Connect(function(i) hInp(i, "eye") end)
bHdr.InputBegan:Connect(function(i) hInp(i, "bottom") end)

table.insert(cons, uis.InputChanged:Connect(function(i)
	if drag and i == dInp and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
		local d = i.Position - dSt
		if d.Magnitude > 3 then
			if not hDrag then hDrag = true if isH then isH = false cYTw() if not sDwn then uUI() end end end
			mFrm.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + d.X, sPos.Y.Scale, sPos.Y.Offset + d.Y)
		end
	end
end))

table.insert(cons, uis.InputBegan:Connect(function(i, g)
	if g or sDwn then return end
	if i.KeyCode == Enum.KeyCode.ButtonL3 or i.KeyCode == Enum.KeyCode.P then tog()
	elseif i.KeyCode == Enum.KeyCode.Delete or i.KeyCode == Enum.KeyCode.End then wSys() end
end))

local function rDesc(d)
	if d:IsA("Model") then
		if isTw(d) then 
			tEnts.Twisteds[d] = true 
		elseif isMa(d) then
			tEnts.Machines[d] = true
		end
	elseif d:IsA("ProximityPrompt") then
		tEnts.Prompts[d] = true
		
		if env.P[d] == nil then
			env.P[d] = d.HoldDuration
		end

		pCons[d] = d:GetPropertyChangedSignal("Enabled"):Connect(function()
			if d.ActionText ~= "Ichor" and d.ActionText ~= "" then
				if not d.Enabled then 
					rmESP(d.Parent) 
				elseif cfg.Item_ESP and isItm(d.ActionText) then 
					aESP(d.Parent, "Item", d.ActionText) 
				end
			end
		end)
		
		if cfg.Instant_Interact then d.HoldDuration = 0 end
		if cfg.Item_ESP and d.ActionText ~= "Ichor" and d.ActionText ~= "" and d.Enabled and isItm(d.ActionText) then 
			task.wait(0.1) 
			aESP(d.Parent, "Item", d.ActionText) 
		end
		
		local pM = d:FindFirstAncestorWhichIsA("Model")
		if pM and isMa(pM) and not tEnts.Machines[pM] then
			tEnts.Machines[pM] = true
		end
	end
end

table.insert(cons, workspace.DescendantAdded:Connect(function(d)
	rDesc(d)
	if cfg.Twisted_ESP and isTw(d) then task.wait(0.15) aESP(d, "Monster") end
	if cfg.Machine_ESP and (tEnts.Machines[d] or isMa(d)) then task.wait(0.15) aESP(d, "Machine") end
end))

table.insert(cons, workspace.DescendantRemoving:Connect(function(d)
	if d:IsA("Model") then
		tEnts.Twisteds[d] = nil
		tEnts.Machines[d] = nil
	elseif d:IsA("ProximityPrompt") then
		tEnts.Prompts[d] = nil
		env.P[d] = nil
	end
	if cBlps[d] then
		cBlps[d]:Destroy()
		cBlps[d] = nil
	end
end))

for _, d in ipairs(workspace:GetDescendants()) do
	rDesc(d)
end

uUI()
sAESP()
uPrmpt()

local lRTk = 0

local function gBlip(t, bT)
	if cBlps[t] then return cBlps[t] end
	local b = Instance.new("Frame")
	b.Name = bT
	b.Size = UDim2.new(0, 5, 0, 5)
	b.AnchorPoint = Vector2.new(0.5, 0.5) 
	b.BorderSizePixel = 0
	
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	s.Parent = b
	
	if act then
		if bT == "Twisted" then
			b.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
			s.Color = cAct
		elseif bT == "Player" then
			b.BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
			s.Color = cAct
		elseif bT == "Machine" then
			b.BackgroundColor3 = cAct 
			s.Color = Color3.fromRGB(0, 0, 0)
		end
	else
		if bT == "Twisted" then
			b.BackgroundColor3 = Color3.fromRGB(130, 130, 130) 
			s.Color = Color3.fromRGB(255, 255, 255)
		elseif bT == "Player" then
			b.BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
			s.Color = Color3.fromRGB(0, 0, 0)
		elseif bT == "Machine" then
			b.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
			s.Color = Color3.fromRGB(255, 255, 255)
		end
	end

	b.Parent = rBlps
	cachedBlips[t] = b
	return b
end

local function eRadTick()
	if sDwn then return end 
	if not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") then return end

	local cm = workspace.CurrentCamera
	if not cm then return end

	local hrp = plr.Character.HumanoidRootPart
	local lk = cm.CFrame.LookVector
	local fl = Vector3.new(lk.X, 0, lk.Z)
	if fl.Magnitude > 0.001 then
		fl = fl.Unit
	else
		fl = Vector3.new(0, 0, -1)
	end

	local mCF = CFrame.lookAt(hrp.Position, hrp.Position + fl)
	local mR, rd = 150, 59
	local sT = {}

	local function pTarObj(tO, bT)
		if not tO or not tO.Parent then return end
		local p = tO:IsA("Model") and (tO:FindFirstChild("HumanoidRootPart") or tO.PrimaryPart or tO:FindFirstChildWhichIsA("BasePart")) or (tO:IsA("BasePart") and tO or nil)
		if not p then return end

		local rP = mCF:PointToObjectSpace(p.Position)
		local d2 = Vector2.new(rP.X, rP.Z).Magnitude
		
		if d2 <= mR then
			sT[tO] = true
			local b = gBlip(tO, bT)
			local rX = (rP.X / mR) * rd
			local rY = (rP.Z / mR) * rd
			
			b.Position = UDim2.new(0.5, rX, 0.5, rY)

			local bA = (math.deg(math.atan2(rY, rX)) + 360) % 360
			local sA = sPiv.Rotation % 360
			local aD = math.abs(bA - sA)
			
			local str = b:FindFirstChildOfClass("UIStroke")
			if aD < 14 or aD > 346 then
				b.BackgroundTransparency = 0
				if str then
					str.Thickness = 1.6
					str.Transparency = 0
				end
			else
				b.BackgroundTransparency = math.clamp(b.BackgroundTransparency + 0.0088, 0, 0.35)
				if str then
					str.Thickness = math.clamp(str.Thickness - 0.012, 1.0, 1.6)
					str.Transparency = math.clamp(str.Transparency + 0.0088, 0, 0.5)
				end
			end
		end
	end

	for t in pairs(tEnts.Twisteds) do
		if isTw(t) then pTarObj(t, "Twisted") end
	end
	for m in pairs(tEnts.Machines) do
		pTarObj(m, "Machine")
	end
	for _, p in ipairs(pls:GetPlayers()) do
		if p ~= plr and p.Character then pTarObj(p.Character, "Player") end
	end

	for o, b in pairs(cBlps) do
		if not sT[o] then
			b:Destroy()
			cBlps[o] = nil
		end
	end
end

table.insert(cons, rs.Stepped:Connect(function()
	if sDwn then return end
	if act then
		aSlip(true)
	end
end))

table.insert(cons, rs.RenderStepped:Connect(function()
	if sDwn then
		rWrp.Visible = false
		return
	else
		rWrp.Visible = not cfg.Hide_Radar
		sPiv.Rotation = (tick() * 150) % 360
	end

	if tick() - lRTk >= 0.005 then
		lRTk = tick()
		eRadTick()
	end
end))

table.insert(cons, rs.Heartbeat:Connect(function()
	if sDwn then return end

	local tSD = tick() - lHTk
	if act and not isC then
		if tSD >= 900 and (tick() - lSLTk > 120) then
			lSLTk = tick()
			qDiag("Affec2")
		elseif tSD >= 300 and tSD < 900 and (tick() - lLDTk > 90) then
			lLDTk = tick()
			qDiag("Affec1")
		end
	end

	if tick() - lSU > 1 then
		lSU = tick()
		
		if cfg.Player_ESP then
			for _, p in ipairs(pls:GetPlayers()) do
				if p ~= plr and p.Character then aESP(p.Character, "Player", p.DisplayName or p.Name) end
			end
		end
		
		if cfg.Stat_HUD then
			local mC, iF = 0, {}
			
			for m in pairs(tEnts.Twisteds) do
				if isTw(m) then mC = mC + 1 end
			end
			
			for p in pairs(tEnts.Prompts) do
				if p.Enabled and p.ActionText ~= "Ichor" and p.ActionText ~= "" then
					if sVals[p.ActionText] then 
						iF[p.ActionText] = (iF[p.ActionText] or 0) + 1 
					end
				end
			end
			
			local lns = {string.format("> Twisteds: %02d", mC), "", "> Valuable_Items:"}
			local hI = false
			local iC = 0
			for n, c in pairs(iF) do 
				lns[#lns+1] = string.format("  • %s x%d", n, c) 
				hI = true 
				iC = iC + 1
			end
			if not hI then 
				lns[#lns+1] = "  • None" 
				iC = 1
			end
			shBod.Text = table.concat(lns, "\n")
			
			local tH = 52 + (iC * 13)
			if shFrm.Size.Y.Offset ~= tH then
				tws:Create(shFrm, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 160, 0, tH)}):Play()
			end
		end
	end

	if cfg.Fullbright then
		lgt.Ambient = Color3.fromRGB(110, 110, 115)
		lgt.OutdoorAmbient = Color3.fromRGB(110, 110, 115)
		lgt.GlobalShadows = false
		lgt.ExposureCompensation = env.L.ExposureCompensation + 0.8
	end

	if cfg.Auto_Escape then
		local sU = pgui:FindFirstChild("TwistedSquirmEscapeUI")
		if sU and sU.Enabled and (tick() - lET > 0.05) then
			lET = tick()
			pcall(function() vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game) task.wait(0.01) vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
		end
	end
end))
