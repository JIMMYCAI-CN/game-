--[[
	=========================================================
	 CharacterMovesClient   （LocalScript，每個玩家都會有一份）
	 放置位置：StarterPlayer > StarterPlayerScripts
	---------------------------------------------------------
	 走 路  119174241724731    Shift = 跑步（加速＋FOV 拉寬）
	 跑 步  128677818236008    C     = 滑剷（往前滑＋FOV）
	 滑 剷  113527499571998    F     = 攻擊（走伺服器判定，扣 20 血）
	 攻 擊  113532863616074    Space = 跳，空中再按 = 二段跳
	 二段跳 78281951371423     E     = 快閃（向前位移）
	 快 閃  138926327377619    Q     = 向右閃身（橫移）
	 左閃身 127771728638518    R     = 向左閃身（橫移）
	 右閃身 109449343171378
	---------------------------------------------------------
	 手機／平板：右下角會自動出現六顆觸控按鈕（不用鍵盤）
	=========================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- 型別檢查：如果真的被放成 Script（伺服器腳本），LocalPlayer 會是 nil
assert(player, "[CharacterMoves] 這支必須是 LocalScript！請放在 StarterPlayer > StarterPlayerScripts")

--============================ 可調整設定 ============================
local CONFIG = {
	Debug = true,            -- true = 在 Output 印出每個動作有沒有觸發（測試完可改 false）

	-- 速度
	WalkSpeed = 16,          -- 一般走路速度
	RunSpeed = 44,           -- 跑步（衝刺）速度（加快奔馳快感）
	SlideSpeed = 64,         -- 滑剷初速

	-- 畫面衝刺感（數值越大，畫面越「拉長」）
	BaseFov = 70,
	RunFov = 92,
	SlideFov = 106,
	DashFov = 102,
	FovSmooth = 8,

	-- 滑剷
	SlideDuration = 0.62,
	SlideCooldown = 1.2,
	SlideEndSpeedFactor = 0.55,

	-- 二段跳
	DoubleJumpVelocity = 62,   -- 50 ≈ 6.4 格、62 ≈ 10 格、75 ≈ 14 格
	DoubleJumpMaxCount = 1,    -- 1 = 二段跳，2 = 三段跳

	-- 快閃（E，向前）
	DashDistance = 20,
	DashDuration = 0.18,
	DashCooldown = 1.5,
	DashStopBuffer = 1.5,      -- 前方有牆時停在牆前幾格

	-- 閃身（Q 向右 / R 向左，橫移一小段）
	DodgeDistance = 8,         -- 橫移幾格（想更遠改 12~15）
	DodgeDuration = 0.16,      -- 花多久（越小越像瞬移）
	DodgeCooldown = 0.9,

	-- 動畫播放速度
	WalkAnimSpeed = 1,
	RunAnimSpeed = 1.15,

	-- 攻擊（伺服器端另有一道冷卻）
	AttackCooldown = 0.28,

	-- 按鍵
	SprintKey = Enum.KeyCode.LeftShift,
	SlideKey = Enum.KeyCode.C,
	AttackKey = Enum.KeyCode.F,
	JumpKey = Enum.KeyCode.Space,
	DashKey = Enum.KeyCode.E,
	LeftDodgeKey = Enum.KeyCode.R,    -- 向左閃身
	RightDodgeKey = Enum.KeyCode.Q,   -- 向右閃身

	AutoSprint = false,      -- true = 一移動就自動跑，不用按 Shift

	-- 動作 ID（Walk/Run 空字串以使用 Roblox 原生絲滑 R15 動畫，Attack 支援三段連招）
	AnimationIds = {
		Walk = "",
		Run = "",
		Slide = "rbxassetid://113527499571998",
		Attack = "rbxassetid://522635533",
		Attack1 = "rbxassetid://522635533",       -- 第一式：疾風斜斬
		Attack2 = "rbxassetid://522638767",       -- 第二式：回旋上挑
		Attack3 = "rbxassetid://113532863616074", -- 第三式：凌空重斬
		DoubleJump = "rbxassetid://78281951371423",
		Dash = "rbxassetid://138926327377619",
		DodgeLeft = "rbxassetid://127771728638518",
		DodgeRight = "rbxassetid://109449343171378",
	},
}
--====================================================================

local function log(...)
	if CONFIG.Debug then
		print("[CharacterMoves]", ...)
	end
end

print("[CharacterMoves] 客戶端腳本已啟動 ✔")

-- 伺服器建立的 RemoteEvent（攻擊用）
local attackRemote = nil
do
	local folder = ReplicatedStorage:WaitForChild("CharacterMoves", 10)
	if folder then
		attackRemote = folder:WaitForChild("AttackRequest", 10)
	end
	if attackRemote then
		log("攻擊用 RemoteEvent 已就緒")
	else
		warn("[CharacterMoves] 找不到 CharacterMoves.AttackRequest → 攻擊不會扣血。請確認 ServerScriptService 內的伺服器腳本已放入並執行。")
	end
end

--============================ 執行狀態 ============================
local character
local humanoid, rootPart, animator
local animFolder
local tracks = {}
local currentMovementAnim = nil

local isSprinting = false
local isSliding = false
local isDashing = false
local jumpsUsed = 0
local lastSlideTime = 0
local lastDashTime = 0
local lastDodgeTime = 0
local lastAttackTime = 0

local characterConnections = {}
local slideConnection = nil
local dashConnection = nil
local activeImpulseTrack = nil
local dashingUsesFov = false
local endSlide
local endDash
--=================================================================

local function addCharacterConnection(connection)
	table.insert(characterConnections, connection)
	return connection
end

local function clearCharacterConnections()
	for _, connection in ipairs(characterConnections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(characterConnections)
end

--============================ 動畫 ============================
local function loadTrack(name, id, looped, priority)
	if not animator or not id or id == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	animation.Parent = animFolder

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(("[CharacterMoves] 動畫載入失敗：%s (%s) → 這個動畫資產可能不是你的/你的群組上傳的。"):format(name, id))
		return nil
	end

	track.Looped = looped
	track.Priority = priority
	return track
end

local function setMovementAnim(name, fadeTime)
	if currentMovementAnim == name then
		return
	end

	local previous = currentMovementAnim and tracks[currentMovementAnim]
	if previous then
		previous:Stop(fadeTime or 0.15)
	end

	currentMovementAnim = name
	local newTrack = name and tracks[name]
	if newTrack then
		newTrack:Play(fadeTime or 0.15)
	end
end

local function isRunning()
	return (isSprinting or CONFIG.AutoSprint) and not isSliding and not isDashing
end

-- 給其他系統（例如減速陷阱 / 疾風藥水）用的倍率：
-- 伺服器只要 humanoid:SetAttribute("SpeedMul", 0.45) 就會生效
local function speedMul(): number
	if not humanoid then
		return 1
	end
	local m = humanoid:GetAttribute("SpeedMul")
	if typeof(m) == "number" and m > 0 then
		return m
	end
	return 1
end

local function desiredWalkSpeed(): number
	if isSliding or isDashing then
		return 0
	end
	local base = isRunning() and CONFIG.RunSpeed or CONFIG.WalkSpeed
	return base * speedMul()
end

local function applyWalkSpeed()
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = desiredWalkSpeed()
end

local function updateLocomotion()
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if isSliding or isDashing then
		return
	end

	local state = humanoid:GetState()
	local moving = humanoid.MoveDirection.Magnitude > 0.1

	local wanted
	if state == Enum.HumanoidStateType.Jumping then
		wanted = tracks.Jump and "Jump" or nil
	elseif state == Enum.HumanoidStateType.Freefall then
		wanted = tracks.Fall and "Fall" or nil
	elseif moving then
		if isRunning() and tracks.Run then
			wanted = "Run"
		else
			wanted = "Walk"
		end
	else
		wanted = "Idle"
	end

	setMovementAnim(wanted)
end

--============================ 滑剷 ============================
endSlide = function()
	if not isSliding then
		return
	end

	isSliding = false

	if slideConnection then
		slideConnection:Disconnect()
		slideConnection = nil
	end

	if tracks.Slide then
		tracks.Slide:Stop(0.15)
	end

	if humanoid then
		humanoid.AutoRotate = true
	end

	currentMovementAnim = nil
	applyWalkSpeed()
end

local function startSlide()
	if isSliding or isDashing or not humanoid or humanoid.Health <= 0 or not rootPart then
		return
	end

	local now = os.clock()
	if now - lastSlideTime < CONFIG.SlideCooldown then
		return
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		log("滑剷：在空中，無法滑")
		return
	end
	if humanoid.MoveDirection.Magnitude < 0.1 then
		log("滑剷：沒有移動輸入，無法滑（請先按著 W 再按 C）")
		return
	end

	lastSlideTime = now
	isSliding = true
	log("滑剷 開始")

	local direction = humanoid.MoveDirection.Unit
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = rootPart.CFrame.LookVector
	end
	flatDirection = flatDirection.Unit

	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDirection)
	humanoid.AutoRotate = false

	applyWalkSpeed()
	setMovementAnim(nil, 0.1)

	if tracks.Slide then
		tracks.Slide:Play(0.08)
	else
		warn("[CharacterMoves] 滑剷動畫沒有載入，只會有位移效果")
	end

	local startClock = os.clock()

	if slideConnection then
		slideConnection:Disconnect()
	end
	slideConnection = RunService.Heartbeat:Connect(function()
		if not isSliding then
			return
		end
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			endSlide()
			return
		end

		local elapsed = os.clock() - startClock
		if elapsed >= CONFIG.SlideDuration then
			endSlide()
			return
		end

		local alpha = elapsed / CONFIG.SlideDuration
		local speed = CONFIG.SlideSpeed * (1 - (1 - CONFIG.SlideEndSpeedFactor) * alpha)

		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(
			flatDirection.X * speed,
			math.min(velocity.Y, 0),
			flatDirection.Z * speed
		)
	end)
end

--==================== 位移型動作共用（快閃 / 閃身） ====================
endDash = function()
	if not isDashing then
		return
	end

	isDashing = false
	dashingUsesFov = false

	if dashConnection then
		dashConnection:Disconnect()
		dashConnection = nil
	end

	if activeImpulseTrack then
		activeImpulseTrack:Stop(0.1)
		activeImpulseTrack = nil
	end

	if humanoid then
		humanoid.AutoRotate = true
	end

	currentMovementAnim = nil
	applyWalkSpeed()
end

-- 沿 direction 高速推進 distance 格，duration 秒內完成
-- 回傳 true = 真的有衝出去（呼叫端用來扣冷卻）
local function startImpulseMove(direction, distance, duration, track, label)
	if not humanoid or not rootPart or not character then
		return false
	end
	if isSliding or isDashing or humanoid.Health <= 0 then
		return false
	end

	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return false
	end
	direction = direction.Unit

	-- 往前打一條射線，撞牆就把距離縮短，不會穿牆
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local hit = workspace:Raycast(rootPart.Position, direction * distance, rayParams)
	if hit then
		distance = math.max((hit.Position - rootPart.Position).Magnitude - CONFIG.DashStopBuffer, 0)
	end
	if distance <= 1 then
		log(label .. "：旁邊／前面就是牆，取消")
		return false
	end

	isDashing = true
	humanoid.AutoRotate = false      -- 位移期間不轉向（閃身才不會轉圈）
	activeImpulseTrack = track

	applyWalkSpeed()                 -- WalkSpeed = 0
	setMovementAnim(nil, 0.05)

	if track then
		track:Play(0.05)
	else
		warn("[CharacterMoves] " .. label .. " 動畫沒有載入，只會有位移效果")
	end

	log(("%s 開始（距離 %.1f 格）"):format(label, distance))

	local speed = distance / duration
	local startClock = os.clock()

	if dashConnection then
		dashConnection:Disconnect()
	end
	dashConnection = RunService.Heartbeat:Connect(function()
		if not isDashing then
			return
		end
		if not humanoid or humanoid.Health <= 0 or not rootPart then
			endDash()
			return
		end

		if os.clock() - startClock >= duration then
			endDash()
			return
		end

		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(
			direction.X * speed,
			math.min(velocity.Y, 0),
			direction.Z * speed
		)
	end)

	return true
end

-- E：向前快閃（有 FOV 衝刺感）
local function startDash()
	if not humanoid or not rootPart then
		return
	end

	local now = os.clock()
	if now - lastDashTime < CONFIG.DashCooldown then
		return
	end

	local direction
	if humanoid.MoveDirection.Magnitude > 0.1 then
		direction = humanoid.MoveDirection.Unit
	else
		direction = rootPart.CFrame.LookVector
	end

	if startImpulseMove(direction, CONFIG.DashDistance, CONFIG.DashDuration, tracks.Dash, "快閃") then
		lastDashTime = now
		dashingUsesFov = true
	end
end

-- Q / R：向左 / 向右閃身（橫移，不改視角）
local function startDodge(side)
	if not humanoid or not rootPart then
		return
	end

	local now = os.clock()
	if now - lastDodgeTime < CONFIG.DodgeCooldown then
		return
	end

	-- 以角色自身左右方向橫移：side = -1 左、1 右
	local direction = rootPart.CFrame.RightVector * side
	local track = (side < 0) and tracks.DodgeLeft or tracks.DodgeRight
	local label = (side < 0) and "左閃身" or "右閃身"

	if startImpulseMove(direction, CONFIG.DodgeDistance, CONFIG.DodgeDuration, track, label) then
		lastDodgeTime = now
	end
end

--============================ 二段跳 ============================
local function tryDoubleJump()
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end
	if isSliding or isDashing then
		return
	end

	local floorMaterial = humanoid.FloorMaterial
	if floorMaterial ~= Enum.Material.Air then
		return   -- 站在地上，第一次跳交給 Roblox 原本的跳躍
	end
	if jumpsUsed < 1 then
		log("二段跳：沒有先跳一次（從邊緣掉下去不算）")
		return
	end
	if jumpsUsed > CONFIG.DoubleJumpMaxCount then
		log("二段跳：次數已用完")
		return
	end

	jumpsUsed += 1
	humanoid.Jump = false   -- 清掉預設跳躍請求，避免落地又自動跳

	if tracks.DoubleJump then
		tracks.DoubleJump:Play(0.1)
	else
		warn("[CharacterMoves] 二段跳動畫沒有載入，只會有跳躍效果")
	end

	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		velocity.X,
		CONFIG.DoubleJumpVelocity,
		velocity.Z
	)

	log(("二段跳 觸發（第 %d 次，速度 %d）"):format(jumpsUsed, CONFIG.DoubleJumpVelocity))
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
		tr:Stop(0.04)
		local speed = (currentHit == 3) and 1.2 or 1.35
		tr:Play(0.06, 1, speed)
	end

	-- 揮刀破空音效（音調隨連擊遞增）
	if rootPart then
		local s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/swordslash.wav"
		s.Volume = (currentHit == 3) and 1.2 or 0.85
		s.PlaybackSpeed = (currentHit == 1 and 1.05) or (currentHit == 2 and 1.22) or 0.88
		s.Parent = rootPart
		s:Play()
		game:GetService("Debris"):AddItem(s, 1.2)
	end

	log(("連貫刀法 第 %d 式！"):format(currentHit))

	if attackRemote then
		attackRemote:FireServer(currentHit)
	end
end

--============================ 每幀更新 ============================
local function updateFieldOfView(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

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
	-- 如果有其他腳本在每幀改 WalkSpeed，這裡會把它改回來
	-- （減速 / 加速道具改成用 SpeedMul 屬性，所以不會被打架）
	if humanoid and humanoid.Health > 0 and humanoid.WalkSpeed ~= desiredWalkSpeed() then
		humanoid.WalkSpeed = desiredWalkSpeed()
	end

	updateLocomotion()
	updateFieldOfView(dt)
end)

--============================ 角色載入 ============================
local currentChar = nil

local function setupCharacter(newCharacter)
	-- player.Character 與 CharacterAdded 可能同時觸發同一個角色，只設定一次
	if currentChar == newCharacter then
		return
	end
	currentChar = newCharacter

	clearCharacterConnections()
	tracks = {}
	currentMovementAnim = nil
	isSprinting = false
	jumpsUsed = 0
	character = newCharacter

	if isSliding then
		if slideConnection then
			slideConnection:Disconnect()
			slideConnection = nil
		end
		isSliding = false
	end
	if isDashing then
		if dashConnection then
			dashConnection:Disconnect()
			dashConnection = nil
		end
		isDashing = false
		activeImpulseTrack = nil
		dashingUsesFov = false
	end

	humanoid = character:WaitForChild("Humanoid", 10)
	rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not rootPart then return end
	animator = humanoid:WaitForChild("Animator", 10)
	if not animator then return end

	animFolder = Instance.new("Folder")
	animFolder.Name = "CharacterMoveAnims"
	animFolder.Parent = character

	local defaultIds = {}
	local animate = character:FindFirstChild("Animate") or character:WaitForChild("Animate", 5)

	-- 保持 Roblox 官方原生 Animate 啟用，提供絲滑自然的行走、跑步與呼吸動作
	if animate then
		animate.Disabled = false
	end

	local trackOrder = {
		{ "Slide", CONFIG.AnimationIds.Slide, false, Enum.AnimationPriority.Action },
		{ "Attack", CONFIG.AnimationIds.Attack, false, Enum.AnimationPriority.Action },
		{ "Attack1", CONFIG.AnimationIds.Attack1, false, Enum.AnimationPriority.Action },
		{ "Attack2", CONFIG.AnimationIds.Attack2, false, Enum.AnimationPriority.Action },
		{ "Attack3", CONFIG.AnimationIds.Attack3, false, Enum.AnimationPriority.Action },
		{ "DoubleJump", CONFIG.AnimationIds.DoubleJump, false, Enum.AnimationPriority.Action },
		{ "Dash", CONFIG.AnimationIds.Dash, false, Enum.AnimationPriority.Action },
		{ "DodgeLeft", CONFIG.AnimationIds.DodgeLeft, false, Enum.AnimationPriority.Action },
		{ "DodgeRight", CONFIG.AnimationIds.DodgeRight, false, Enum.AnimationPriority.Action },
	}

	for _, info in ipairs(trackOrder) do
		tracks[info[1]] = loadTrack(info[1], info[2], info[3], info[4])
	end

	if tracks.Walk then
		tracks.Walk:AdjustSpeed(CONFIG.WalkAnimSpeed)
	end
	if tracks.Run then
		tracks.Run:AdjustSpeed(CONFIG.RunAnimSpeed)
	end

	-- 跳躍次數：起跳 = 1，落地歸零
	addCharacterConnection(humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			if jumpsUsed < 1 then
				jumpsUsed = 1
			end
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			jumpsUsed = 0
			if tracks.DoubleJump then
				tracks.DoubleJump:Stop(0.15)
			end
		end
	end))

	addCharacterConnection(humanoid.Died:Connect(function()
		isSprinting = false
		if isSliding then
			endSlide()
		end
		if isDashing then
			endDash()
		end
	end))

	-- 坐下動作（隊友定制 sitting animation id: 110976420397279）
	local sitTrack: AnimationTrack? = nil
	local okSit, sitAnim = pcall(function()
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://110976420397279"
		return a
	end)
	if okSit and sitAnim and animator then
		pcall(function()
			sitTrack = animator:LoadAnimation(sitAnim)
			sitTrack.Priority = Enum.AnimationPriority.Action4
			sitTrack.Looped = true
		end)
	end

	addCharacterConnection(humanoid.Seated:Connect(function(isSeated, seatPart)
		if isSeated then
			if sitTrack then
				sitTrack:Play(0.2)
			end
		else
			if sitTrack and sitTrack.IsPlaying then
				sitTrack:Stop(0.25)
			end
		end
	end))

	applyWalkSpeed()
	updateLocomotion()

	local loaded = 0
	local total = 0
	for _, info in ipairs(trackOrder) do
		total += 1
		if tracks[info[1]] then
			loaded += 1
		end
	end
	log(("角色就緒：%s｜骨架 %s｜載入 %d/%d 個動畫"):format(
		character.Name,
		humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6",
		loaded,
		total
	))
end

if player.Character then
	task.spawn(setupCharacter, player.Character)
end
player.CharacterAdded:Connect(function(newCharacter)
	task.spawn(setupCharacter, newCharacter)
end)

--============================ 按鍵輸入 ============================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local key = input.KeyCode
	if key == CONFIG.SprintKey then
		isSprinting = true
		applyWalkSpeed()
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

--============================ 手機 / 平板觸控按鈕 ============================
-- 只有觸控裝置（手機、平板）才會建立；電腦玩家看不到
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "CharacterMovesTouch"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Name = "Buttons"
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Size = UDim2.new(0, 272, 0, 176)
	panel.Position = UDim2.new(1, -16, 1, -178)
	panel.BackgroundTransparency = 1
	panel.Parent = gui

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 84, 0, 84)
	layout.CellPadding = UDim2.new(0, 8, 0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = 3
	layout.Parent = panel

	local function makeButton(order, label, color, onTap)
		local btn = Instance.new("TextButton")
		btn.LayoutOrder = order
		btn.BackgroundColor3 = color
		btn.BackgroundTransparency = 0.25
		btn.Text = label
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.TextScaled = true
		btn.Font = Enum.Font.SourceSansBold
		btn.AutoButtonColor = true
		btn.ZIndex = 6
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.55
		stroke.Thickness = 2
		stroke.Parent = btn
		btn.Parent = panel
		btn.Activated:Connect(onTap)
		return btn
	end

	local purple = Color3.fromRGB(90, 70, 150)
	local orange = Color3.fromRGB(170, 90, 40)
	local blue = Color3.fromRGB(45, 95, 160)
	local red = Color3.fromRGB(150, 55, 65)

	-- 第一列：跑 / 滑 / 左閃
	makeButton(1, "跑", blue, function()
		isSprinting = not isSprinting
		applyWalkSpeed()
	end)
	makeButton(2, "滑", orange, startSlide)
	makeButton(3, "左閃", purple, function() startDodge(-1) end)
	-- 第二列：攻 / 閃 / 右閃
	makeButton(4, "攻", red, doAttack)
	makeButton(5, "快閃", purple, startDash)
	makeButton(6, "右閃", purple, function() startDodge(1) end)

	log("觸控按鈕已建立（手機 / 平板）")
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
	hint.Size = UDim2.new(0, 560, 0, 30)
	hint.Position = UDim2.new(0, 14, 1, -14)
	hint.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	hint.BackgroundTransparency = 0.45
	hint.TextColor3 = Color3.fromRGB(220, 225, 235)
	hint.Font = Enum.Font.SourceSans
	hint.TextScaled = true
	hint.Text = "Shift 跑　C 滑剷　F 攻擊　E 快閃　Q / R 左右閃身　空白鍵×2 二段跳"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = hint
	hint.Parent = gui

	task.delay(12, function()
		TweenService:Create(hint, TweenInfo.new(1.2), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(1.3)
		gui:Destroy()
	end)
end

