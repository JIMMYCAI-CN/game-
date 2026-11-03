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
	steel     = {color = Color3.fromRGB(232, 240, 255), color2 = Color3.fromRGB(150, 168, 195), shake = 0.95, arc = 1.00, extra = "none"},
	obsidian  = {color = Color3.fromRGB(165, 115, 255), color2 = Color3.fromRGB(60, 40, 90),   shake = 1.15, arc = 1.08, extra = "smoke"},
	thunder   = {color = Color3.fromRGB(120, 195, 255), color2 = Color3.fromRGB(245, 250, 255), shake = 1.35, arc = 1.15, extra = "bolt"},
	sakura    = {color = Color3.fromRGB(255, 165, 210), color2 = Color3.fromRGB(255, 235, 245), shake = 1.30, arc = 1.18, extra = "petal"},
	frost     = {color = Color3.fromRGB(170, 235, 255), color2 = Color3.fromRGB(255, 255, 255), shake = 1.50, arc = 1.22, extra = "ice"},
	astra     = {color = Color3.fromRGB(130, 255, 190), color2 = Color3.fromRGB(255, 255, 210), shake = 1.70, arc = 1.28, extra = "rune"},
	hydra     = {color = Color3.fromRGB(140, 240, 110), color2 = Color3.fromRGB(40, 120, 40),   shake = 1.85, arc = 1.32, extra = "venom"},
	blueflame = {color = Color3.fromRGB(90, 180, 255), color2 = Color3.fromRGB(220, 245, 255),  shake = 2.10, arc = 1.40, extra = "flame"},
	phoenix   = {color = Color3.fromRGB(255, 155, 60), color2 = Color3.fromRGB(255, 240, 170),  shake = 2.50, arc = 1.50, extra = "phoenix"},
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
-- 3D 浮空傷害跳字 (Floating Damage Numbers)
-- ------------------------------------------------------------
local function popupDamageNumber(worldPos: Vector3?, text: string, col: Color3, isCrit: boolean?)
	local cam = workspace.CurrentCamera
	if not cam then return end
	local pos = worldPos or (cam.CFrame.Position + cam.CFrame.LookVector * 10)

	local bb = Instance.new("BillboardGui")
	bb.Name = "DamagePopup"
	bb.Size = isCrit and UDim2.new(0, 160, 0, 50) or UDim2.new(0, 120, 0, 40)
	bb.StudsOffsetWorldSpace = pos + Vector3.new((rng:NextNumber() - 0.5) * 1.2, 1.8, (rng:NextNumber() - 0.5) * 1.2)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = isCrit and Enum.Font.GothamBlack or Enum.Font.GothamBold
	lbl.Text = text
	lbl.TextColor3 = col
	lbl.TextScaled = true
	lbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 25)
	lbl.TextStrokeTransparency = 0.1
	lbl.Parent = bb

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = workspace

	bb.Adornee = anchor
	bb.Parent = plr:WaitForChild("PlayerGui")

	local floatDur = isCrit and 0.85 or 0.65
	local targetOffset = bb.StudsOffsetWorldSpace + Vector3.new(0, 3.2, 0)
	TweenService:Create(bb, TweenInfo.new(floatDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = targetOffset
	}):Play()

	task.delay(floatDur * 0.5, function()
		TweenService:Create(lbl, TweenInfo.new(floatDur * 0.5, Enum.EasingStyle.Linear), {
			TextTransparency = 1,
			TextStrokeTransparency = 1
		}):Play()
	end)

	game:GetService("Debris"):AddItem(anchor, floatDur + 0.05)
	game:GetService("Debris"):AddItem(bb, floatDur + 0.05)
end

-- ------------------------------------------------------------
-- 人物受擊紅白閃爍高光 (Character Hit Flash Highlight)
-- ------------------------------------------------------------
local function flashCharacter(char: Model?)
	if not char or not char:IsA("Model") then return end
	local hl = Instance.new("Highlight")
	hl.Name = "HitFlashHighlight"
	hl.FillColor = Color3.fromRGB(255, 45, 45)
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.2
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = char

	TweenService:Create(hl, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FillTransparency = 1,
		OutlineTransparency = 1
	}):Play()

	game:GetService("Debris"):AddItem(hl, 0.18)
end

-- ------------------------------------------------------------
-- 打擊頓幀 (Hit-Stop / Micro Freeze 40ms)
-- ------------------------------------------------------------
local function hitStop(dur: number?)
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local originalSpeed = hum.WalkSpeed
	hum.WalkSpeed = 4
	task.delay(dur or 0.038, function()
		if hum and hum.Parent then
			hum.WalkSpeed = originalSpeed
		end
	end)
end

-- ------------------------------------------------------------
-- 斬擊爆裂火花噴泉 (Slash Impact Sparks)
-- ------------------------------------------------------------
local function slashImpactSparks(hitPos: Vector3, theme: any, isCrit: boolean?)
	ringWave(hitPos, theme.color, isCrit and 4.2 or 3.0, 0.26)
	ringWave(hitPos, Color3.new(1, 1, 1), isCrit and 2.5 or 1.8, 0.20)
	particleBurst(hitPos, theme.color, isCrit and 36 or 24, 60, 0.55, 0.45)
	particleBurst(hitPos, Color3.new(1, 1, 1), isCrit and 20 or 12, 75, 0.45, 0.35)
	debrisFly(hitPos, theme.color, isCrit and 10 or 6, 45)
end

local function ballImpact(pos, theme, kind, coin, ballName)
	-- 金屬撞擊與超音速彈反爆響音效
	local hitSnd = Instance.new("Sound")
	hitSnd.SoundId = "rbxassetid://12222225"
	hitSnd.Volume = 1.45
	hitSnd.PlaybackSpeed = 1.05 + rng:NextNumber() * 0.15
	hitSnd.Parent = workspace.CurrentCamera
	hitSnd:Play()
	game:GetService("Debris"):AddItem(hitSnd, 1.5)

	local clinkSnd = Instance.new("Sound")
	clinkSnd.SoundId = "rbxassetid://12222208"
	clinkSnd.Volume = 1.2
	clinkSnd.PlaybackSpeed = 1.15
	clinkSnd.Parent = workspace.CurrentCamera
	clinkSnd:Play()
	game:GetService("Debris"):AddItem(clinkSnd, 1.5)

	hitStop(0.04)

	if kind == "destroy" then
		ringWave(pos, theme.color, 4.2, 0.38)
		ringWave(pos, Color3.new(1, 1, 1), 2.5, 0.25)
		particleBurst(pos, theme.color, 38, 55, 0.6, 0.6)
		particleBurst(pos, Color3.new(1, 1, 1), 18, 70, 0.45, 0.4)
		debrisFly(pos, theme.color, 8, 42)
		screenFlash(theme.color, 0.25, 0.18)
		speedLines(theme.color)
		addShake(theme.shake * 1.8, 0.26)
		punchIn(1.35)
		popupDamageNumber(pos, "💥 碎球!", theme.color, true)
		hitText("⚔️ 砍碎" .. (ballName and (" " .. ballName) or ""), theme.color, coin)
	else
		ringWave(pos, theme.color, 3.2, 0.28)
		ringWave(pos, Color3.new(1, 1, 1), 1.8, 0.20)
		particleBurst(pos, Color3.new(1, 1, 1), 24, 70, 0.5, 0.45)
		particleBurst(pos, theme.color, 18, 50, 0.45, 0.4)
		screenFlash(Color3.new(1, 1, 1), 0.18, 0.14)
		speedLines(theme.color)
		addShake(theme.shake * 1.35, 0.20)
		punchIn(0.95)
		popupDamageNumber(pos, "⚡ 反彈!", theme.color, false)
		hitText("⚡ 完美反彈", theme.color, coin)
	end
end

Net.OnClientEvent:Connect(function(msg)
	if type(msg) ~= "table" then return end
	if msg.act == "swing" then
		local d = msg.data or {}
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
	elseif msg.act == "bot_swingfx" then
		local d = msg.data or {}
		local b = workspace:FindFirstChild(tostring(d.botName))
		local hrp = b and b:FindFirstChild("HumanoidRootPart")
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
			local char = plr.Character
			local tool = char and char:FindFirstChildOfClass("Tool")
			skin = tool and skinOfTool(tool) or "steel"
		end
		ballImpact(pos, themeOf(skin), d.kind, d.coin, d.name)
	elseif msg.act == "hitsuccess" then
		local d = msg.data or {}
		local theme = themeOf(d.skin)
		local isCrit = d.isCrit or (d.dmg and d.dmg >= 45)
		local hitPos = d.pos and Vector3.new(d.pos.X, d.pos.Y, d.pos.Z) or (plr.Character and (plr.Character:GetPivot().Position + Vector3.new(0, 1.5, 0)))

		addShake(isCrit and (theme.shake * 1.5) or (theme.shake * 1.1), 0.22)
		punchIn(isCrit and 1.3 or 0.85)
		screenFlash(isCrit and Color3.fromRGB(255, 230, 160) or Color3.fromRGB(255, 255, 255), isCrit and 0.28 or 0.18, 0.12)
		hitStop(isCrit and 0.05 or 0.038)

		slashImpactSparks(hitPos, theme, isCrit)

		if d.victim then
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and (m.Name == d.victim or (m:FindFirstChild("Humanoid") and m.Humanoid.DisplayName == d.victim)) then
					flashCharacter(m)
					break
				end
			end
		end

		local dmgText = "-" .. tostring(d.dmg or 25) .. (isCrit and " 暴擊!" or "")
		popupDamageNumber(hitPos, dmgText, isCrit and Color3.fromRGB(255, 215, 50) or Color3.fromRGB(255, 85, 55), isCrit)

		local hitSnd = Instance.new("Sound")
		hitSnd.SoundId = isCrit and "rbxassetid://12222225" or "rbxassetid://5665637213"
		hitSnd.Volume = isCrit and 1.6 or 1.3
		hitSnd.PlaybackSpeed = 0.98 + rng:NextNumber() * 0.15
		hitSnd.Parent = workspace.CurrentCamera
		hitSnd:Play()
		game:GetService("Debris"):AddItem(hitSnd, 1.5)

		if isCrit then
			local critBoom = Instance.new("Sound")
			critBoom.SoundId = "rbxassetid://281444251"
			critBoom.Volume = 1.4
			critBoom.Parent = workspace.CurrentCamera
			critBoom:Play()
			game:GetService("Debris"):AddItem(critBoom, 1.5)
		end

		hitText("⚔️ 命中 " .. tostring(d.victim or "敵人") .. " " .. dmgText, isCrit and Color3.fromRGB(255, 225, 70) or Color3.fromRGB(255, 190, 60))
	elseif msg.act == "hurt" then
		local d = msg.data or {}
		addShake(1.1, 0.24)
		screenFlash(Color3.fromRGB(255, 45, 45), 0.38, 0.22)
		if plr.Character then
			flashCharacter(plr.Character)
			popupDamageNumber(plr.Character:GetPivot().Position + Vector3.new(0, 1.5, 0), "-" .. tostring(d.dmg or 25), Color3.fromRGB(255, 50, 50), false)
		end
		hitText("💔 受傷 -" .. tostring(d.dmg or 25) .. (d.attacker and (" (" .. d.attacker .. ")") or ""), Color3.fromRGB(255, 80, 80))
	elseif msg.act == "coinpopup" then
		local d = msg.data or {}
		local p = d.pos and Vector3.new(d.pos.X, d.pos.Y, d.pos.Z) or (plr.Character and plr.Character:GetPivot().Position)
		popupDamageNumber(p, "+" .. tostring(d.amt or 10) .. " 💰", Color3.fromRGB(255, 220, 60), true)
	elseif msg.act == "perfectparry" then
		local d = msg.data or {}
		local pos = d.pos and Vector3.new(d.pos.X, d.pos.Y, d.pos.Z) or (plr.Character and plr.Character:GetPivot().Position)
		addShake(2.2, 0.28)
		punchIn(1.6)
		screenFlash(Color3.fromRGB(255, 225, 75), 0.42, 0.16)
		hitStop(0.06)

		-- 金色極限衝擊波擴散光環
		local ring = newPart(Vector3.new(2, 0.2, 2), Color3.fromRGB(255, 220, 50), 0.1)
		ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0)
		ring.Shape = Enum.PartType.Cylinder
		local tw = TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.2, 28, 28),
			Transparency = 1,
		})
		tw:Play()
		tw.Completed:Connect(function() ring:Destroy() end)

		-- 清脆金屬彈反音效（Roblox 原廠高品質刀劍金屬敲擊聲）
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://12222208"
		s.Volume = 2.0
		s.PlaybackSpeed = 1.62 -- 高頻清亮叮的一聲
		s.Parent = workspace.CurrentCamera
		s:Play()
		game:GetService("Debris"):AddItem(s, 1.5)

		popupDamageNumber(pos + Vector3.new(0, 2, 0), "⚡ 完美彈反! +5 💰", Color3.fromRGB(255, 230, 60), true)
		hitText("⚡ PERFECT PARRY! 完美彈反! +5 💰 ⚡", Color3.fromRGB(255, 225, 50))
	elseif msg.act == "swordclash" then
		local d = msg.data or {}
		local pos = d.pos and Vector3.new(d.pos.X, d.pos.Y, d.pos.Z) or (plr.Character and plr.Character:GetPivot().Position)
		addShake(1.5, 0.20)
		screenFlash(Color3.fromRGB(255, 245, 200), 0.25, 0.10)
		hitStop(0.05)

		-- 拼刀金屬火花迸射
		local sparkCount = 12
		for _ = 1, sparkCount do
			local sp = newPart(Vector3.new(0.35, 0.35, 1.4), Color3.fromRGB(255, 200, 70), 0)
			local v = rng:NextUnitVector()
			sp.CFrame = CFrame.lookAt(pos, pos + v)
			local twS = TweenService:Create(sp, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = sp.CFrame + v * rng:NextNumber(4, 9),
				Transparency = 1,
				Size = Vector3.new(0.05, 0.05, 0.2),
			})
			twS:Play()
			twS.Completed:Connect(function() sp:Destroy() end)
		end

		-- 重金屬拼刀回響
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://12222208"
		s.Volume = 1.8
		s.PlaybackSpeed = 1.05 + rng:NextNumber() * 0.12
		s.Parent = workspace.CurrentCamera
		s:Play()
		game:GetService("Debris"):AddItem(s, 1.5)

		popupDamageNumber(pos + Vector3.new(0, 1.8, 0), "⚔️ 拼刀格擋!", Color3.fromRGB(255, 210, 80), true)
		hitText("⚔️ SWORD CLASH! 貼身拼刀僵直!", Color3.fromRGB(255, 200, 70))
	elseif msg.act == "ultimate_burst" then
		local d = msg.data or {}
		local pos = d.pos and Vector3.new(d.pos.X, d.pos.Y, d.pos.Z) or (plr.Character and plr.Character:GetPivot().Position)
		addShake(2.8, 0.45)
		punchIn(2.0)
		screenFlash(Color3.fromRGB(255, 200, 50), 0.55, 0.25)
		hitStop(0.08)

		-- 巨大金色全屏劍氣光環擴散
		local ring = newPart(Vector3.new(4, 0.3, 4), Color3.fromRGB(255, 180, 30), 0.1)
		ring.CFrame = CFrame.new(pos)
		ring.Shape = Enum.PartType.Cylinder
		local tw = TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.3, 68, 68),
			Transparency = 1,
		})
		tw:Play()
		tw.Completed:Connect(function() ring:Destroy() end)

		-- 轟鳴必殺音效
		local b = Instance.new("Sound")
		b.SoundId = "rbxassetid://281444251"
		b.Volume = 2.2
		b.Parent = workspace.CurrentCamera
		b:Play()
		game:GetService("Debris"):AddItem(b, 2.0)

		popupDamageNumber(pos + Vector3.new(0, 3, 0), "🔥 必殺爆發!", Color3.fromRGB(255, 120, 30), true)
		hitText("🔥 ULTIMATE BURST! 必殺絕技全屏震盪! 🔥", Color3.fromRGB(255, 140, 40))
	end
end)
