--[[
	=========================================================
	 CharacterMovesClient   （LocalScript，每個玩家都會有一份）
	 放置位置：StarterPlayer > StarterPlayerScripts
	---------------------------------------------------------
	 走 路  Roblox 原生絲滑步伐
	 跑 步  Shift / 衝刺按鈕   = 疾跑（加速＋FOV 視野延伸）
	 滑 剷  C / 滑剷按鈕       = 貼地滑剷（高速突進＋動態視角）
	 攻 擊  滑鼠左鍵 / F / 攻   = 帥氣三段連擊刀法（全身軀幹聯動斬擊）
	 二段跳 Space × 2          = 空中凌空二段跳
	 快 閃  E / 閃按鈕         = 向前迅疾位移
	 閃 身  Q 向右 / R 向左     = 左右側身閃避橫移
	 視角鎖定 Alt / Ctrl / 鎖定 = 自由視角鎖定（免長按右鍵拖拽）
	---------------------------------------------------------
	 手機／平板：右下角呈現極簡磨砂半透明圓形按鈕組（完美適配）
	=========================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
assert(player, "[CharacterMoves] 這支必須是 LocalScript！請放在 StarterPlayer > StarterPlayerScripts")

--============================ 可調整設定 ============================
local CONFIG = {
	Debug = false,

	-- 速度
	WalkSpeed = 16,
	RunSpeed = 54,            -- 跑步（衝刺）速度加快，極致奔馳感
	SlideSpeed = 74,          -- 滑剷初速

	-- 畫面衝刺感（FOV）
	BaseFov = 70,
	RunFov = 92,
	SlideFov = 106,
	DashFov = 102,
	FovSmooth = 8,

	-- 滑剷
	SlideDuration = 0.62,
	SlideCooldown = 1.1,
	SlideEndSpeedFactor = 0.55,

	-- 二段跳
	DoubleJumpVelocity = 64,
	DoubleJumpMaxCount = 1,

	-- 快閃（E，向前）
	DashDistance = 28,
	DashDuration = 0.18,
	DashCooldown = 1.3,
	DashStopBuffer = 1.5,

	-- 閃身（Q 向右 / R 向左）
	DodgeDistance = 10,
	DodgeDuration = 0.15,
	DodgeCooldown = 0.8,

	-- 動畫播放速度
	WalkAnimSpeed = 1,
	RunAnimSpeed = 1.15,

	-- 攻擊冷卻
	AttackCooldown = 0.26,

	-- 按鍵
	SprintKey = Enum.KeyCode.LeftShift,
	SlideKey = Enum.KeyCode.C,
	AttackKey = Enum.KeyCode.F,
	JumpKey = Enum.KeyCode.Space,
	DashKey = Enum.KeyCode.E,
	LeftDodgeKey = Enum.KeyCode.R,
	RightDodgeKey = Enum.KeyCode.Q,
	ShiftLockKey1 = Enum.KeyCode.LeftAlt,
	ShiftLockKey2 = Enum.KeyCode.LeftControl,

	AutoSprint = false,

	-- 動作 ID（Action4 優先級，覆蓋工具動作以展現全身揮砍聯動）
	AnimationIds = {
		Walk = "",
		Run = "",
		Slide = "rbxassetid://113527499571998",
		Attack = "rbxassetid://522635533",
		Attack1 = "rbxassetid://522635533",       -- 第一式：疾風斜斬
		Attack2 = "rbxassetid://522638767",       -- 第二式：回旋上挑
		Attack3 = "rbxassetid://113532863616074", -- 第三式：凌空重劈
		DoubleJump = "rbxassetid://78281951371423",
		Dash = "rbxassetid://138926327377619",
		DodgeLeft = "rbxassetid://127771728638518",
		DodgeRight = "rbxassetid://109449343171378",
	},
}

local function log(...)
	if CONFIG.Debug then
		print("[CharacterMoves:Client]", ...)
	end
end

local attackRemote = nil
do
	local folder = ReplicatedStorage:WaitForChild("CharacterMoves", 10)
	if folder then
		attackRemote = folder:WaitForChild("AttackRequest", 10)
	end
	if attackRemote then
		log("攻擊 RemoteEvent 已就緒")
	else
		warn("[CharacterMoves] 找不到 CharacterMoves.AttackRequest")
	end
end

--============================ 狀態變數 ============================
local character = nil
local humanoid = nil
local rootPart = nil
local animator = nil
local animFolder = nil

local tracks = {}
local currentMovementAnim = nil

local isSprinting = false
local isSliding = false
local isDashing = false
local isDodging = false
local isShiftLocked = false

local lastSlideTime = 0
local lastAttackTime = 0
local lastDashTime = 0
local lastDodgeTime = 0
local jumpsUsed = 0

local characterConnections = {}
local slideConnection = nil
local dashConnection = nil
local activeImpulseTrack = nil
local dashingUsesFov = false

local function addCharacterConnection(conn)
	table.insert(characterConnections, conn)
	return conn
end

local function clearCharacterConnections()
	for _, c in ipairs(characterConnections) do
		c:Disconnect()
	end
	table.clear(characterConnections)
end

--============================ 動畫輔助 ============================
local function loadTrack(name, id, looped, priority)
	if not animator or not id or id == "" then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.Name = name
	anim.AnimationId = id
	anim.Parent = animFolder

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = looped or false
		track.Priority = priority or Enum.AnimationPriority.Action4
		return track
	end
	return nil
end

local function stopTracksExcept(...)
	local keep = {}
	for i = 1, select("#", ...) do
		keep[select(i, ...)] = true
	end
	for name, tr in pairs(tracks) do
		if not keep[name] and tr.IsPlaying then
			tr:Stop(0.15)
		end
	end
end

--============================ 速度計算 ============================
local function isRunning()
	return isSprinting or CONFIG.AutoSprint
end

local function desiredWalkSpeed()
	if not humanoid then return CONFIG.WalkSpeed end
	local base = isRunning() and CONFIG.RunSpeed or CONFIG.WalkSpeed
	local mul = humanoid:GetAttribute("SpeedMul")
	if typeof(mul) == "number" and mul > 0 then
		base = base * mul
	end
	return base
end

local function applyWalkSpeed()
	if humanoid and humanoid.Health > 0 and not isSliding and not isDashing and not isDodging then
		humanoid.WalkSpeed = desiredWalkSpeed()
	end
end

local function updateLocomotion()
	if not humanoid or humanoid.Health <= 0 then return end
	if isSliding or isDashing or isDodging then return end
	applyWalkSpeed()
end

--============================ 視角鎖定（Shift-Lock）系統 ============================
local shiftLockIndicator = nil
local crosshairGui = nil

local function setupShiftLockGui()
	local pgui = player:WaitForChild("PlayerGui")
	local sg = Instance.new("ScreenGui")
	sg.Name = "ShiftLockCrosshair"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 10
	sg.Parent = pgui
	crosshairGui = sg

	-- 中心準星
	local dot = Instance.new("Frame")
	dot.Name = "CenterDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	dot.Size = UDim2.new(0, 6, 0, 6)
	dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	dot.BackgroundTransparency = 0.2
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = dot
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(0, 0, 0)
	s.Transparency = 0.4
	s.Thickness = 1.2
	s.Parent = dot
	dot.Parent = sg
	sg.Enabled = false

	-- 畫面常駐鎖定提示 / 開關按鈕（PC / 手機均可一鍵點擊切換）
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ShiftLockToggle"
	toggleBtn.AnchorPoint = Vector2.new(1, 0)
	toggleBtn.Size = UDim2.new(0, 115, 0, 32)
	toggleBtn.Position = UDim2.new(1, -12, 0, 48)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
	toggleBtn.BackgroundTransparency = 0.45
	toggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 13
	toggleBtn.Text = "🔒 視角鎖定 [關]"
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 8)
	tc.Parent = toggleBtn
	local ts = Instance.new("UIStroke")
	ts.Color = Color3.fromRGB(200, 205, 220)
	ts.Transparency = 0.5
	ts.Thickness = 1.5
	ts.Parent = toggleBtn
	toggleBtn.Parent = sg
	shiftLockIndicator = toggleBtn

	local function onToggle()
		isShiftLocked = not isShiftLocked
		if isShiftLocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			sg.Enabled = true
			toggleBtn.Text = "🔓 視角鎖定 [開]"
			toggleBtn.TextColor3 = Color3.fromRGB(120, 255, 180)
			ts.Color = Color3.fromRGB(120, 255, 180)
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			sg.Enabled = false
			toggleBtn.Text = "🔒 視角鎖定 [關]"
			toggleBtn.TextColor3 = Color3.fromRGB(220, 225, 235)
			ts.Color = Color3.fromRGB(200, 205, 220)
		end
	end
	toggleBtn.Activated:Connect(onToggle)
end
setupShiftLockGui()

local function toggleShiftLock()
	if shiftLockIndicator then
		local cur = isShiftLocked
		isShiftLocked = not cur
		if isShiftLocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			if crosshairGui then crosshairGui.Enabled = true end
			shiftLockIndicator.Text = "🔓 視角鎖定 [開]"
			shiftLockIndicator.TextColor3 = Color3.fromRGB(120, 255, 180)
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			if crosshairGui then crosshairGui.Enabled = false end
			shiftLockIndicator.Text = "🔒 視角鎖定 [關]"
			shiftLockIndicator.TextColor3 = Color3.fromRGB(220, 225, 235)
		end
	end
end

-- 每幀視角與角色朝向同步
RunService.RenderStepped:Connect(function()
	if isShiftLocked and humanoid and humanoid.Health > 0 and rootPart then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		local cam = workspace.CurrentCamera
		if cam then
			local _, camY, _ = cam.CFrame:ToOrientation()
			rootPart.CFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, camY, 0)
		end
	end
end)

--============================ 滑剷 ============================
local function endSlide()
	if not isSliding then return end
	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end
	isSliding = false
	if tracks.Slide then
		tracks.Slide:Stop(0.18)
	end
	applyWalkSpeed()
end

local function startSlide()
	local now = os.clock()
	if now - lastSlideTime < CONFIG.SlideCooldown then return end
	if isSliding or isDashing or not humanoid or humanoid.Health <= 0 or not rootPart then return end

	local moveDir = humanoid.MoveDirection
	local slideDir = (moveDir.Magnitude > 0.1) and moveDir.Unit or rootPart.CFrame.LookVector

	lastSlideTime = now
	isSliding = true

	if tracks.Slide then
		tracks.Slide:Play(0.08)
	end

	local startTime = now
	local duration = CONFIG.SlideDuration
	local startSpeed = CONFIG.SlideSpeed
	local endSpeed = CONFIG.SlideSpeed * CONFIG.SlideEndSpeedFactor

	slideConnection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration or not humanoid or humanoid.Health <= 0 then
			endSlide()
			return
		end
		local alpha = elapsed / duration
		local currentSpeed = startSpeed + (endSpeed - startSpeed) * (alpha * alpha)
		local currentY = rootPart.AssemblyLinearVelocity.Y
		rootPart.AssemblyLinearVelocity = Vector3.new(
			slideDir.X * currentSpeed,
			currentY,
			slideDir.Z * currentSpeed
		)
	end)
end

--============================ 快閃 / 閃身 ============================
local function startImpulseMove(direction, distance, duration, trackName, usesFov, isDodgeMove)
	if not rootPart or not humanoid or humanoid.Health <= 0 then return end
	local now = os.clock()
	if isDodgeMove then
		if now - lastDodgeTime < CONFIG.DodgeCooldown then return end
		lastDodgeTime = now
		isDodging = true
	else
		if now - lastDashTime < CONFIG.DashCooldown then return end
		lastDashTime = now
		isDashing = true
		dashingUsesFov = usesFov
	end

	local track = tracks[trackName]
	if track then
		track:Play(0.05, 1, 1.25)
		activeImpulseTrack = track
	end

	local startPos = rootPart.Position
	local targetOffset = direction * distance

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	local rayResult = workspace:Raycast(startPos, targetOffset, rayParams)

	local actualOffset = targetOffset
	if rayResult then
		local hitDist = (rayResult.Position - startPos).Magnitude
		local safeDist = math.max(0, hitDist - CONFIG.DashStopBuffer)
		actualOffset = direction * safeDist
	end

	local speed = actualOffset.Magnitude / math.max(duration, 0.05)
	local startTime = now

	dashConnection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration or not humanoid or humanoid.Health <= 0 then
			if dashConnection then
				dashConnection:Disconnect()
				dashConnection = nil
			end
			if isDodgeMove then
				isDodging = false
			else
				isDashing = false
				dashingUsesFov = false
			end
			if activeImpulseTrack then
				activeImpulseTrack:Stop(0.12)
				activeImpulseTrack = nil
			end
			applyWalkSpeed()
			return
		end
		local vy = rootPart.AssemblyLinearVelocity.Y
		rootPart.AssemblyLinearVelocity = Vector3.new(
			direction.X * speed,
			vy,
			direction.Z * speed
		)
	end)
end

local function startDash()
	if isSliding or isDashing or not rootPart then return end
	local dir = rootPart.CFrame.LookVector
	startImpulseMove(dir, CONFIG.DashDistance, CONFIG.DashDuration, "Dash", true, false)
end

local function startDodge(sign)
	if isSliding or isDashing or isDodging or not rootPart then return end
	local right = rootPart.CFrame.RightVector
	local dir = (sign < 0) and -right or right
	local trackName = (sign < 0) and "DodgeLeft" or "DodgeRight"
	startImpulseMove(dir, CONFIG.DodgeDistance, CONFIG.DodgeDuration, trackName, false, true)
end

--============================ 二段跳 ============================
local function tryDoubleJump()
	if not humanoid or humanoid.Health <= 0 or not rootPart then return end
	local state = humanoid:GetState()
	local inAir = (state == Enum.HumanoidStateType.Freefall) or (state == Enum.HumanoidStateType.Jumping)
	if not inAir then return end
	if jumpsUsed >= CONFIG.DoubleJumpMaxCount then return end

	jumpsUsed += 1
	if tracks.DoubleJump then
		tracks.DoubleJump:Stop(0.02)
		tracks.DoubleJump:Play(0.04, 1, 1.35)
	end

	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, CONFIG.DoubleJumpVelocity, velocity.Z)
end

--============================ 攻擊（帥氣三段連擊刀法）============================
local comboStep = 1
local lastComboTime = 0

local function doAttack()
	local now = os.clock()
	if now - lastAttackTime < CONFIG.AttackCooldown then
		return
	end
	if not humanoid or humanoid.Health <= 0 or isSliding or isDashing then
		return
	end

	-- 0.85 秒內連續擊打視為連擊，超過時間則重置為第一式
	if now - lastComboTime > 0.85 then
		comboStep = 1
	end

	lastAttackTime = now
	lastComboTime = now

	local currentHit = comboStep
	comboStep = (comboStep % 3) + 1

	-- 播放連貫動作（第一式：斜斬、第二式：上挑突進、第三式：躍起重劈）
	local trackName = "Attack" .. currentHit
	local tr = tracks[trackName] or tracks.Attack
	if tr then
		tr.Priority = Enum.AnimationPriority.Action4
		tr:Stop(0.03)
		local speed = (currentHit == 3) and 1.25 or 1.4
		tr:Play(0.05, 1, speed)
	end

	-- 揮刀破空音效（輕脆破風聲，隨連擊音調上揚）
	if rootPart then
		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/swordslash.wav"
		s.Volume = (currentHit == 3) and 1.15 or 0.85
		s.PlaybackSpeed = (currentHit == 1 and 1.05) or (currentHit == 2 and 1.22) or 0.92
		s.Parent = rootPart
		s:Play()
		game:GetService("Debris"):AddItem(s, 1.0)
	end

	if attackRemote then
		attackRemote:FireServer(currentHit)
	end
end

--============================ 每幀更新 ============================
local function updateFieldOfView(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local targetFov = CONFIG.BaseFov
	if isDashing and dashingUsesFov then
		targetFov = CONFIG.DashFov
	elseif isSliding then
		targetFov = CONFIG.SlideFov
	elseif isRunning() and humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		targetFov = CONFIG.RunFov
	end

	local alpha = 1 - math.exp(-CONFIG.FovSmooth * dt)
	camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * alpha
end

RunService.Heartbeat:Connect(function(dt)
	if humanoid and humanoid.Health > 0 and humanoid.WalkSpeed ~= desiredWalkSpeed() then
		humanoid.WalkSpeed = desiredWalkSpeed()
	end
	updateLocomotion()
	updateFieldOfView(dt)
end)

--============================ 角色載入 ============================
local currentChar = nil

local function setupCharacter(newCharacter)
	if currentChar == newCharacter then return end
	currentChar = newCharacter

	clearCharacterConnections()
	tracks = {}
	currentMovementAnim = nil
	isSprinting = false
	jumpsUsed = 0
	character = newCharacter

	if isSliding then endSlide() end
	if isDashing and dashConnection then dashConnection:Disconnect(); dashConnection = nil end
	isDashing = false

	humanoid = character:WaitForChild("Humanoid", 10)
	rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not rootPart then return end
	animator = humanoid:WaitForChild("Animator", 10)
	if not animator then return end

	animFolder = Instance.new("Folder")
	animFolder.Name = "CharacterMoveAnims"
	animFolder.Parent = character

	local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 5)
	if animate then animate.Disabled = false end

	local trackOrder = {
		{ "Slide", CONFIG.AnimationIds.Slide, false, Enum.AnimationPriority.Action4 },
		{ "Attack", CONFIG.AnimationIds.Attack, false, Enum.AnimationPriority.Action4 },
		{ "Attack1", CONFIG.AnimationIds.Attack1, false, Enum.AnimationPriority.Action4 },
		{ "Attack2", CONFIG.AnimationIds.Attack2, false, Enum.AnimationPriority.Action4 },
		{ "Attack3", CONFIG.AnimationIds.Attack3, false, Enum.AnimationPriority.Action4 },
		{ "DoubleJump", CONFIG.AnimationIds.DoubleJump, false, Enum.AnimationPriority.Action4 },
		{ "Dash", CONFIG.AnimationIds.Dash, false, Enum.AnimationPriority.Action4 },
		{ "DodgeLeft", CONFIG.AnimationIds.DodgeLeft, false, Enum.AnimationPriority.Action4 },
		{ "DodgeRight", CONFIG.AnimationIds.DodgeRight, false, Enum.AnimationPriority.Action4 },
	}

	for _, info in ipairs(trackOrder) do
		tracks[info[1]] = loadTrack(info[1], info[2], info[3], info[4])
	end

	-- 監聽裝備的 Tool（滑鼠點刀時同步揮刀動作與打擊！）
	local function hookTool(tool)
		if tool:IsA("Tool") then
			addCharacterConnection(tool.Activated:Connect(function()
				doAttack()
			end))
		end
	end
	for _, ch in ipairs(character:GetChildren()) do hookTool(ch) end
	addCharacterConnection(character.ChildAdded:Connect(hookTool))

	addCharacterConnection(humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			if jumpsUsed < 1 then jumpsUsed = 1 end
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			jumpsUsed = 0
			if tracks.DoubleJump then tracks.DoubleJump:Stop(0.15) end
		end
	end))

	addCharacterConnection(humanoid.Died:Connect(function()
		isSprinting = false
		if isSliding then endSlide() end
		isDashing = false
	end))

	applyWalkSpeed()
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
player.CharacterAdded:Connect(setupCharacter)

--============================ 鍵盤與滑鼠事件 ============================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- 滑鼠左鍵點擊（若不是在點擊聊天框/UI按鈕，則揮刀）
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not gameProcessed then
			doAttack()
		end
		return
	end

	if gameProcessed then return end

	local key = input.KeyCode
	if key == CONFIG.SprintKey then
		isSprinting = true
		applyWalkSpeed()
	elseif key == CONFIG.ShiftLockKey1 or key == CONFIG.ShiftLockKey2 then
		toggleShiftLock()
	elseif key == CONFIG.SlideKey then
		startSlide()
	elseif key == CONFIG.AttackKey then
		doAttack()
	elseif key == CONFIG.JumpKey then
		tryDoubleJump()
	elseif key == CONFIG.DashKey then
		startDash()
	elseif key == CONFIG.LeftDodgeKey then
		startDodge(-1)
	elseif key == CONFIG.RightDodgeKey then
		startDodge(1)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == CONFIG.SprintKey then
		isSprinting = false
		applyWalkSpeed()
	end
end)

--============================ 手機 / 平板觸控按鈕（極簡半透明磨砂圓形組） ============================
-- 參考附圖設計：右下角圓弧排列、半透明暗黑圓底、純白極簡圖標、彈性按壓反饋
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterMovesTouch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "TouchPanel"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Size = UDim2.new(0, 260, 0, 260)
	panel.Position = UDim2.new(1, -12, 1, -18)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local function makeRoundBtn(name, iconText, sz, posRel, onTap)
		local btn = Instance.new("ImageButton")
		btn.Name = name
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Size = sz
		btn.Position = posRel
		btn.BackgroundColor3 = Color3.fromRGB(25, 28, 36)
		btn.BackgroundTransparency = 0.42
		btn.AutoButtonColor = false
		btn.ZIndex = 20

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(220, 225, 235)
		stroke.Transparency = 0.35
		stroke.Thickness = 2.4
		stroke.Parent = btn

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0.85, 0, 0.85, 0)
		lbl.Position = UDim2.new(0.075, 0, 0.075, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextScaled = true
		lbl.Text = iconText
		lbl.ZIndex = 21
		lbl.Parent = btn

		-- 觸控彈性動態回饋
		btn.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(btn, TweenInfo.new(0.08), {Size = UDim2.new(sz.X.Scale, sz.X.Offset * 0.9, sz.Y.Scale, sz.Y.Offset * 0.9), BackgroundTransparency = 0.2}):Play()
			end
		end)
		btn.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.Touch then
				TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = sz, BackgroundTransparency = 0.42}):Play()
			end
		end)

		btn.Activated:Connect(onTap)
		btn.Parent = panel
		return btn
	end

	-- 1. 奔跑（🏃 人形圖標，右上角）
	makeRoundBtn("BtnSprint", "🏃", UDim2.new(0, 56, 0, 56), UDim2.new(0.78, 0, 0.14, 0), function()
		isSprinting = not isSprinting
		applyWalkSpeed()
	end)

	-- 2. 揮刀核心攻擊（⚔️ 居中稍大按鍵）
	makeRoundBtn("BtnAttack", "⚔️", UDim2.new(0, 68, 0, 68), UDim2.new(0.52, 0, 0.42, 0), doAttack)

	-- 3. 前衝（▲ 上箭頭，右側）
	makeRoundBtn("BtnDash", "▲", UDim2.new(0, 54, 0, 54), UDim2.new(0.86, 0, 0.58, 0), startDash)

	-- 4. 滑剷（⤹ 折箭頭，底部）
	makeRoundBtn("BtnSlide", "⤹", UDim2.new(0, 54, 0, 54), UDim2.new(0.42, 0, 0.82, 0), startSlide)

	-- 5. 左閃身（◀ 左箭頭，左側）
	makeRoundBtn("BtnDodgeL", "◀", UDim2.new(0, 52, 0, 52), UDim2.new(0.12, 0, 0.52, 0), function()
		startDodge(-1)
	end)

	-- 6. 右閃身（▶ 右箭頭）
	makeRoundBtn("BtnDodgeR", "▶", UDim2.new(0, 52, 0, 52), UDim2.new(0.40, 0, 0.16, 0), function()
		startDodge(1)
	end)

	log("手機端簡約磨砂圓形按鈕已成功掛載")
end

--============================ 電腦版按鍵提示（12 秒後淡出） ============================
if UserInputService.KeyboardEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterMovesHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Size = UDim2.new(0, 590, 0, 32)
	hint.Position = UDim2.new(0, 14, 1, -14)
	hint.BackgroundColor3 = Color3.fromRGB(15, 16, 22)
	hint.BackgroundTransparency = 0.45
	hint.TextColor3 = Color3.fromRGB(225, 230, 240)
	hint.Font = Enum.Font.GothamMedium
	hint.TextScaled = true
	hint.Text = "Shift 跑 | C 滑剷 | 左鍵/F 攻擊 | E 衝刺 | Q/R 閃避 | 空格×2 二段跳 | Alt 視角鎖定"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hint
	local strk = Instance.new("UIStroke")
	strk.Color = Color3.fromRGB(180, 185, 200)
	strk.Transparency = 0.6
	strk.Thickness = 1
	strk.Parent = hint
	hint.Parent = gui

	task.delay(12, function()
		TweenService:Create(hint, TweenInfo.new(1.2), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		TweenService:Create(strk, TweenInfo.new(1.2), { Transparency = 1 }):Play()
		task.wait(1.3)
		gui:Destroy()
	end)
end
