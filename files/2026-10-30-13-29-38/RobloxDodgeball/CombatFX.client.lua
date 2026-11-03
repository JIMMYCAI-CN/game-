--!nocheck
-- ============================================================
--  戰鬥手感特效：揮刀刀光 / 命中反饋 / 刀皮膚分級特效
--  放置位置：StarterPlayer → StarterPlayerScripts（LocalScript）
--  說明：純客戶端表現，不改任何數值與判定
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local plr = Players.LocalPlayer
local Net = ReplicatedStorage:WaitForChild("DodgeNet") :: RemoteEvent
local rng = Random.new()

-- ------------------------------------------------------------
-- 刀皮膚 → 特效設定（越貴越華麗）
-- ------------------------------------------------------------
local THEMES = {
	steel     = {color = Color3.fromRGB(232, 240, 255), color2 = Color3.fromRGB(150, 168, 195), shake = 0.45, arc = 0.95, extra = "none"},
	obsidian  = {color = Color3.fromRGB(165, 115, 255), color2 = Color3.fromRGB(60, 40, 90),   shake = 0.55, arc = 1.00, extra = "smoke"},
	thunder   = {color = Color3.fromRGB(120, 195, 255), color2 = Color3.fromRGB(245, 250, 255), shake = 0.70, arc = 1.05, extra = "bolt"},
	sakura    = {color = Color3.fromRGB(255, 165, 210), color2 = Color3.fromRGB(255, 235, 245), shake = 0.60, arc = 1.10, extra = "petal"},
	frost     = {color = Color3.fromRGB(170, 235, 255), color2 = Color3.fromRGB(255, 255, 255), shake = 0.65, arc = 1.12, extra = "ice"},
	astra     = {color = Color3.fromRGB(130, 255, 190), color2 = Color3.fromRGB(255, 255, 210), shake = 0.72, arc = 1.18, extra = "rune"},
	hydra     = {color = Color3.fromRGB(140, 240, 110), color2 = Color3.fromRGB(40, 120, 40),   shake = 0.78, arc = 1.22, extra = "venom"},
	blueflame = {color = Color3.fromRGB(90, 180, 255), color2 = Color3.fromRGB(220, 245, 255),  shake = 0.88, arc = 1.28, extra = "flame"},
	phoenix   = {color = Color3.fromRGB(255, 155, 60), color2 = Color3.fromRGB(255, 240, 170),  shake = 1.05, arc = 1.36, extra = "phoenix"},
}

local function themeOf(skinId)
	return THEMES[tostring(skinId or "steel")] or THEMES.steel
end

-- ------------------------------------------------------------
-- 共用小工具
-- ------------------------------------------------------------
local function newPart(size, color, transparency)
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

-- 鏡頭前推衝擊（FOV 由角色動作腳本每幀接管，這裡不動 FOV，改用位移）
local punchAmt = 0
local function punchIn(dist)
	punchAmt = math.clamp(punchAmt + dist, -1.2, 1.4)
end

-- 鏡頭震動
local shakeLeft, shakeDur, shakeMag = 0, 0.2, 0
local function addShake(mag, dur)
	shakeMag = math.max(shakeMag, mag)
	shakeDur = math.max(dur, 0.06)
	shakeLeft = math.max(shakeLeft, dur)
end

RunService:BindToRenderStep("CombatFX_Shake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	local cam = workspace.CurrentCamera
	if not cam then return end
	if punchAmt ~= 0 then
		punchAmt *= math.exp(-dt * 15)
		if math.abs(punchAmt) < 0.01 then punchAmt = 0 end
		cam.CFrame = cam.CFrame * CFrame.new(0, 0, -punchAmt * 0.55)
	end
	if shakeLeft > 0 then
		shakeLeft -= dt
		local k = math.clamp(shakeLeft / shakeDur, 0, 1)
		local m = shakeMag * k * k * 1.6
		cam.CFrame = cam.CFrame
			* CFrame.new((rng:NextNumber() - 0.5) * m, (rng:NextNumber() - 0.5) * m, 0)
			* CFrame.Angles((rng:NextNumber() - 0.5) * m * 0.010, (rng:NextNumber() - 0.5) * m * 0.010, (rng:NextNumber() - 0.5) * m * 0.016)
	else
		shakeMag = 0
	end
end)

-- 全螢幕閃光
local flashGui = Instance.new("ScreenGui")
flashGui.Name = "CombatFX"
flashGui.ResetOnSpawn = false
flashGui.IgnoreGuiInset = true
flashGui.DisplayOrder = 90
flashGui.Parent = plr:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = Color3.new(1, 1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 5
flash.Parent = flashGui

local function screenFlash(color, alpha, dur)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - alpha
	TweenService:Create(flash, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
end

-- 命中提示（畫面中央）
local hitLabel = Instance.new("TextLabel")
hitLabel.Size = UDim2.new(0, 600, 0, 70)
hitLabel.Position = UDim2.new(0.5, -300, 0.58, 0)
hitLabel.BackgroundTransparency = 1
hitLabel.Font = Enum.Font.GothamBold
hitLabel.TextSize = 42
hitLabel.TextScaled = false
hitLabel.TextTransparency = 1
hitLabel.TextStrokeTransparency = 1
hitLabel.ZIndex = 6
hitLabel.Text = ""
hitLabel.Parent = flashGui

local function hitText(txt, color, coin)
	hitLabel.Text = (coin and coin > 0) and (txt .. "  +" .. tostring(coin)) or txt
	hitLabel.TextColor3 = color
	hitLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
	hitLabel.TextStrokeTransparency = 0.35
	hitLabel.TextTransparency = 0.05
	hitLabel.Position = UDim2.new(0.5, -300, 0.58, 0)
	hitLabel.TextSize = 40
	TweenService:Create(hitLabel, TweenInfo.new(0.10, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 48,
		Position = UDim2.new(0.5, -300, 0.55, 0),
	}):Play()
	task.delay(0.14, function()
		TweenService:Create(hitLabel, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			Position = UDim2.new(0.5, -300, 0.50, 0),
		}):Play()
	end)
end

-- 放射狀速度線（重擊時的動漫感）
local function speedLines(color)
	for i = 1, 14 do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0.5, 0, 0.5, 0)
		line.Size = UDim2.new(0, 70, 0, 3)
		line.Rotation = (i / 14) * 360 + rng:NextNumber(-6, 6)
		line.BackgroundColor3 = color
		line.BackgroundTransparency = 0.25
		line.BorderSizePixel = 0
		line.ZIndex = 5
		line.Parent = flashGui
		TweenService:Create(line, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 300, 0, 1),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.32, function()
			if line.Parent then line:Destroy() end
		end)
	end
end

-- ------------------------------------------------------------
-- 粒子 / 衝擊波 / 碎片
-- ------------------------------------------------------------
local function particleBurst(pos, color, count, speed, size, life)
	local host = newPart(Vector3.new(0.2, 0.2, 0.2), color, 1)
	host.Position = pos
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(life * 0.55, life)
	pe.Speed = NumberRange.new(speed * 0.35, speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 3
	pe.Acceleration = Vector3.new(0, -24, 0)
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Parent = host
	pe:Emit(count)
	task.delay(life + 0.2, function()
		if host.Parent then host:Destroy() end
	end)
end

local function ringWave(pos, color, radius, dur)
	local ring = newPart(Vector3.new(0.35, 1.2, 1.2), color, 0.05)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(ring, TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.35, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(dur + 0.1, function()
		if ring.Parent then ring:Destroy() end
	end)
end

local function debrisFly(pos, color, count, power)
	for _ = 1, count do
		local d = newPart(Vector3.new(0.34, 0.34, 0.34), color, 0.1)
		d.Anchored = false
		d.Position = pos
		d.AssemblyLinearVelocity = Vector3.new(
			(rng:NextNumber() - 0.5) * power,
			rng:NextNumber() * power * 0.8 + 6,
			(rng:NextNumber() - 0.5) * power
		)
		d.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12))
		task.delay(0.75, function()
			if d.Parent then
				TweenService:Create(d, TweenInfo.new(0.3), {Transparency = 1}):Play()
				task.delay(0.32, function()
					if d.Parent then d:Destroy() end
				end)
			end
		end)
	end
end

-- ------------------------------------------------------------
-- 刀光：一段薄片排成的弧（會依序亮起再淡出）
-- ------------------------------------------------------------
local function arcSlash(baseCF, theme, radius, life, segCount, width)
	local model = Instance.new("Model")
	model.Name = "SlashArc"
	local segs = {}
	local N = segCount or 14
	local w = width or 1

	for i = 1, N do
		local t = (i - 1) / (N - 1)
		local ang = math.rad(-74 + 148 * t)
		local thick = math.sin(math.pi * t)
		local len = (0.55 + 1.7 * thick) * w
		local part = newPart(Vector3.new(0.14 * w, len, 0.42 * w), theme.color, 1)
		part.Name = "Seg"
		part.Parent = model
		local x = math.sin(ang) * radius
		local y = (math.cos(ang) - 0.62) * radius * 0.55
		local z = (1 - math.cos(ang)) * 0.85
		segs[#segs + 1] = {
			p = part,
			cf = baseCF * CFrame.new(x, y, z) * CFrame.Angles(0, 0, -ang),
			delay = (i - 1) * 0.0045,
			thick = thick,
			len = len,
		}
	end

	for _, s in ipairs(segs) do
		task.delay(s.delay, function()
			if not s.p.Parent then return end
			s.p.CFrame = s.cf
			s.p.Transparency = 0.02
			TweenService:Create(s.p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = Vector3.new(s.p.Size.X * 1.6, s.len * 1.15, s.p.Size.Z * 1.4),
				CFrame = s.cf * CFrame.new(0, 0.45, -1.15),
			}):Play()
		end)
	end

	task.delay(life + 0.25, function()
		if model.Parent then model:Destroy() end
	end)
end

-- ------------------------------------------------------------
-- 各刀專屬附加特效
-- ------------------------------------------------------------
local function lightningBolt(fromPos, color)
	local p = fromPos
	for i = 1, 4 do
		local nextP = p + Vector3.new((rng:NextNumber() - 0.5) * 2.2, rng:NextNumber(0.6, 1.8), (rng:NextNumber() - 0.5) * 2.2)
		local seg = newPart(Vector3.new(0.16, (nextP - p).Magnitude, 0.16), color, 0.05)
		seg.CFrame = CFrame.lookAt((p + nextP) / 2, nextP) * CFrame.Angles(math.rad(90), 0, 0)
		TweenService:Create(seg, TweenInfo.new(0.16), {Transparency = 1}):Play()
		task.delay(0.2, function()
			if seg.Parent then seg:Destroy() end
		end)
		p = nextP
	end
end

local function runeRing(cf, color)
	local model = Instance.new("Model")
	model.Parent = workspace
	for i = 1, 10 do
		local ang = (i / 10) * math.pi * 2
		local p = newPart(Vector3.new(0.18, 0.9, 0.18), color, 0.05)
		p.CFrame = cf * CFrame.new(math.cos(ang) * 2.6, math.sin(ang) * 2.6, 0) * CFrame.Angles(0, 0, ang)
		p.Parent = model
		TweenService:Create(p, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.18, 1.6, 0.18),
		}):Play()
	end
	task.delay(0.55, function()
		if model.Parent then model:Destroy() end
	end)
end

local function petalFall(cf, color, count)
	for i = 1, count do
		local p = newPart(Vector3.new(0.42, 0.06, 0.3), color, 0.05)
		local ang = math.rad(rng:NextNumber(0, 360))
		local r = rng:NextNumber(1.0, 3.4)
		p.CFrame = cf * CFrame.new(math.cos(ang) * r, math.sin(ang) * r * 0.6 + 0.4, -0.6) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6))
		TweenService:Create(p, TweenInfo.new(rng:NextNumber(0.6, 1.1), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			CFrame = p.CFrame * CFrame.new((rng:NextNumber() - 0.5) * 1.6, -rng:NextNumber(1.2, 2.6), (rng:NextNumber() - 0.5) * 1.6)
				* CFrame.Angles(rng:NextNumber(0, 4), rng:NextNumber(0, 4), 0),
		}):Play()
		task.delay(1.25, function()
			if p.Parent then p:Destroy() end
		end)
	end
end

local function shardSpray(cf, color, count)
	for i = 1, count do
		local p = newPart(Vector3.new(0.16, 1.0, 0.16), color, 0.05)
		p.CFrame = cf * CFrame.new((rng:NextNumber() - 0.5) * 1.2, (rng:NextNumber() - 0.5) * 1.2, 0) * CFrame.Angles(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Transparency = 1,
			CFrame = p.CFrame * CFrame.new((rng:NextNumber() - 0.5) * 3, rng:NextNumber(-0.4, 1.6), -rng:NextNumber(2, 5)),
		}):Play()
		task.delay(0.55, function()
			if p.Parent then p:Destroy() end
		end)
	end
end

local function doExtra(theme, cf, hrpPos)
	local kind = theme.extra
	if kind == "bolt" then
		for i = 1, 2 do
			lightningBolt(cf * CFrame.new((rng:NextNumber() - 0.5) * 2.4, rng:NextNumber(0.4, 1.4), 0).Position, theme.color2)
		end
		particleBurst(cf.Position, theme.color, 14, 26, 0.4, 0.35)
	elseif kind == "petal" then
		petalFall(cf, theme.color, 10)
	elseif kind == "ice" then
		shardSpray(cf, theme.color2, 9)
		particleBurst(cf.Position, theme.color, 12, 18, 0.42, 0.45)
	elseif kind == "rune" then
		runeRing(cf, theme.color2)
		particleBurst(cf.Position, theme.color, 16, 20, 0.36, 0.5)
	elseif kind == "venom" then
		particleBurst(cf.Position, theme.color, 20, 24, 0.45, 0.55)
		shardSpray(cf, theme.color, 6)
	elseif kind == "flame" then
		particleBurst(cf.Position, theme.color, 22, 22, 0.55, 0.6)
		ringWave(cf.Position, theme.color, 1.6, 0.3)
	elseif kind == "phoenix" then
		particleBurst(cf.Position, theme.color, 26, 26, 0.6, 0.7)
		particleBurst(cf.Position, theme.color2, 14, 16, 0.45, 0.5)
		ringWave(hrpPos or cf.Position, theme.color, 4.2, 0.42)
		debrisFly(cf.Position, theme.color, 5, 26)
	elseif kind == "smoke" then
		particleBurst(cf.Position, theme.color, 14, 12, 0.6, 0.7)
	end
end

-- ------------------------------------------------------------
-- 揮刀
-- ------------------------------------------------------------
local lastPlay = 0
local comboDir = 1
local gripBusy = false

local function animateGrip(char, dir)
	if gripBusy then return end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand then return end
	local grip = hand:FindFirstChild("RightGrip")
	if not grip or not (grip:IsA("Weld") or grip:IsA("Motor6D")) then return end
	gripBusy = true
	local base = grip.C0
	local goal = base * CFrame.Angles(math.rad(-75 * dir), 0, math.rad(40 * dir)) * CFrame.new(0, 0.3, 0)
	TweenService:Create(grip, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {C0 = goal}):Play()
	task.delay(0.10, function()
		if grip.Parent then
			TweenService:Create(grip, TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {C0 = base}):Play()
		end
		task.delay(0.18, function()
			gripBusy = false
		end)
	end)
end

-- 刀的揮擊基座（在世界座標擺出刀光）
local function baseCFOf(hrpCF, dir)
	return hrpCF
		* CFrame.new(0.30 * dir, 0.9, -1.35)
		* CFrame.Angles(math.rad(-14), math.rad(12 * dir), math.rad(40 * dir))
end

-- 刀光本體（自己與別人都用這支）
local function swingFX(theme, baseCF, hrpPos, dir)
	arcSlash(baseCF, theme, 3.6 * theme.arc, 0.20, 14, 1 + (theme.arc - 1) * 0.5)
	if theme.arc >= 1.10 then
		arcSlash(baseCF * CFrame.new(0, -0.15, 0.25) * CFrame.Angles(0, 0, math.rad(14 * dir)), {
			color = theme.color2 or theme.color,
		}, 3.1 * theme.arc, 0.24, 12, 0.8)
	end
	doExtra(theme, baseCF, hrpPos)
end

local function playSwing(skinId)
	local now = os.clock()
	if now - lastPlay < 0.13 then return end
	lastPlay = now

	local theme = themeOf(skinId)
	local char = plr.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	comboDir = -comboDir
	local dir = comboDir
	local baseCF = baseCFOf((hrp :: BasePart).CFrame, dir)

	swingFX(theme, baseCF, (hrp :: BasePart).Position, dir)
	animateGrip(char, dir)
	addShake(theme.shake * 0.55, 0.13)
	punchIn(-0.35)

	-- 揮刀破空音效
	local whoosh = Instance.new("Sound")
	whoosh.SoundId = "rbxasset://sounds/swordslash.wav"
	whoosh.Volume = 0.95
	whoosh.PlaybackSpeed = 0.95 + rng:NextNumber() * 0.25
	whoosh.Parent = hrp
	whoosh:Play()
	game:GetService("Debris"):AddItem(whoosh, 1.2)
end

-- 刀身拖尾（裝備時掛上）
local function attachTrail(tool, skinId)
	local handle = tool:FindFirstChild("Handle")
	if not handle or handle:FindFirstChild("FXTrail") then return end
	local theme = themeOf(skinId)
	local a0 = Instance.new("Attachment")
	a0.Name = "FXA0"
	a0.Position = Vector3.new(0, 3.3, 0)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "FXA1"
	a1.Position = Vector3.new(0, 0.3, 0)
	a1.Parent = handle
	local tr = Instance.new("Trail")
	tr.Name = "FXTrail"
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = 0.18
	tr.Texture = ""
	tr.Color = ColorSequence.new(theme.color, theme.color2 or theme.color)
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	tr.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	tr.Parent = handle
end

local function skinOfTool(tool)
	local s = tool:GetAttribute("Skin")
	if s then return tostring(s) end
	return "steel"
end

local function hookTool(tool)
	if not tool:IsA("Tool") then return end
	if tool:GetAttribute("FXHooked") then return end
	tool:SetAttribute("FXHooked", true)

	tool.Activated:Connect(function()
		playSwing(skinOfTool(tool))
	end)
	tool.Equipped:Connect(function()
		attachTrail(tool, skinOfTool(tool))
	end)
	tool.AncestryChanged:Connect(function()
		if not tool.Parent then
			tool:SetAttribute("FXHooked", nil)
		end
	end)
	if tool.Parent and tool.Parent:IsA("Model") then
		attachTrail(tool, skinOfTool(tool))
	end
end

local function watchContainer(container)
	for _, c in ipairs(container:GetChildren()) do
		hookTool(c)
	end
	container.ChildAdded:Connect(function(c)
		task.wait(0.05)
		hookTool(c)
	end)
end

local function onCharacter(char)
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			task.wait(0.05)
			hookTool(c)
		end
	end)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then hookTool(c) end
	end
end

if plr.Character then onCharacter(plr.Character) end
plr.CharacterAdded:Connect(onCharacter)

local bp = plr:FindFirstChild("Backpack")
if bp then watchContainer(bp) end
plr.ChildAdded:Connect(function(c)
	if c.Name == "Backpack" then
		task.wait(0.1)
		watchContainer(c)
	end
end)

-- ------------------------------------------------------------
-- 球命中反饋
-- ------------------------------------------------------------
local function ballImpact(pos, theme, kind, coin, ballName)
	-- 金屬撞擊與清脆彈反打擊音效
	local hitSnd = Instance.new("Sound")
	hitSnd.SoundId = "rbxasset://sounds/swordhit.wav"
	hitSnd.Volume = 1.35
	hitSnd.PlaybackSpeed = 1.02 + rng:NextNumber() * 0.16
	hitSnd.Parent = workspace.CurrentCamera
	hitSnd:Play()
	game:GetService("Debris"):AddItem(hitSnd, 1.5)

	local clinkSnd = Instance.new("Sound")
	clinkSnd.SoundId = "rbxassetid://9114223171"
	clinkSnd.Volume = 0.9
	clinkSnd.PlaybackSpeed = 1.15
	clinkSnd.Parent = workspace.CurrentCamera
	clinkSnd:Play()
	game:GetService("Debris"):AddItem(clinkSnd, 1.5)

	if kind == "destroy" then
		ringWave(pos, theme.color, 3.4, 0.34)
		ringWave(pos, Color3.new(1, 1, 1), 1.9, 0.22)
		particleBurst(pos, theme.color, 26, 46, 0.6, 0.6)
		particleBurst(pos, Color3.new(1, 1, 1), 10, 60, 0.4, 0.35)
		debrisFly(pos, theme.color, 6, 34)
		screenFlash(theme.color, 0.20, 0.16)
		speedLines(theme.color)
		addShake(theme.shake * 1.5, 0.22)
		punchIn(1.05)
		hitText("✦ 砍碎" .. (ballName and ("「" .. ballName .. "」") or ""), theme.color, coin)
	else
		ringWave(pos, theme.color, 2.6, 0.26)
		particleBurst(pos, Color3.new(1, 1, 1), 18, 62, 0.45, 0.4)
		particleBurst(pos, theme.color, 12, 40, 0.4, 0.35)
		screenFlash(Color3.new(1, 1, 1), 0.14, 0.12)
		addShake(theme.shake * 1.05, 0.16)
		punchIn(0.65)
		hitText("✦ 反彈", theme.color, coin)
	end
end

Net.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.act == "swing" then
		local d = msg.data or {}
		-- 伺服器回音（F 鍵攻擊）：本機已播過就不重播
		if os.clock() - lastPlay > 0.16 then
			playSwing(d.skin)
		end
	elseif msg.act == "swingfx" then
		local d = msg.data or {}
		local who = Players:GetPlayerByUserId(d.userId)
		local ch = who and who.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp then
			local cf = baseCFOf((hrp :: BasePart).CFrame, 1)
			swingFX(themeOf(d.skin), cf, (hrp :: BasePart).Position, 1)
		end
	elseif msg.act == "ballhit" then
		local d = msg.data or {}
		local pos = d.pos
		if typeof(pos) ~= "Vector3" then return end
		local skin = d.skin
		if not skin then
			-- 沒有帶皮膚就讀自己手上的刀
			local char = plr.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			skin = tool and skinOfTool(tool) or "steel"
		end
		ballImpact(pos, themeOf(skin), d.kind, d.coin, d.name)
	elseif msg.act == "hitsuccess" then
		local d = msg.data or {}
		addShake(0.65, 0.18)
		punchIn(0.85)
		local hitSnd = Instance.new("Sound")
		hitSnd.SoundId = "rbxasset://sounds/swordhit.wav"
		hitSnd.Volume = 1.2
		hitSnd.PlaybackSpeed = 1.1
		hitSnd.Parent = workspace.CurrentCamera
		hitSnd:Play()
		game:GetService("Debris"):AddItem(hitSnd, 1.2)
		hitText("⚔ 命中 " .. tostring(d.victim or "敵人") .. " -" .. tostring(d.dmg or 25), Color3.fromRGB(255, 200, 60))
	elseif msg.act == "hurt" then
		local d = msg.data or {}
		addShake(0.85, 0.22)
		screenFlash(Color3.fromRGB(255, 45, 45), 0.35, 0.22)
		hitText("💔 受傷 -" .. tostring(d.dmg or 25) .. (d.attacker and (" (" .. d.attacker .. ")") or ""), Color3.fromRGB(255, 80, 80))
	end
end)
