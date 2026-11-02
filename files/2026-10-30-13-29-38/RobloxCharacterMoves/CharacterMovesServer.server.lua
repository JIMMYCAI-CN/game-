--[[
	=========================================================
	 CharacterMovesServer   （② 這支是 Script，不是 LocalScript）
	 放置位置：ServerScriptService
	---------------------------------------------------------
	 工作：建立 RemoteEvent、處理 F 攻擊的命中判定與扣血
	=========================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--============================ 可調整設定 ============================
local CONFIG = {
	Debug = true,                           -- true = 在 Output 印出命中紀錄
	Damage = 20,                            -- 每次攻擊傷害
	Cooldown = 0.5,                         -- 攻擊冷卻（秒）
	HitboxSize = Vector3.new(5.5, 5, 5.5),  -- 判定框大小（寬, 高, 深）
	HitboxForward = 3.2,                    -- 判定框往前推的距離
	MaxTargets = 4,                         -- 一次最多打幾個目標
}
--====================================================================

local function log(...)
	if CONFIG.Debug then
		print("[CharacterMoves:Server]", ...)
	end
end

-- 建立 RemoteEvent
local folder = ReplicatedStorage:FindFirstChild("CharacterMoves")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CharacterMoves"
	folder.Parent = ReplicatedStorage
end

local attackRemote = folder:FindFirstChild("AttackRequest")
if not attackRemote then
	attackRemote = Instance.new("RemoteEvent")
	attackRemote.Name = "AttackRequest"
	attackRemote.Parent = folder
end

print("[CharacterMoves] 伺服器腳本已啟動 ✔ (RemoteEvent: CharacterMoves.AttackRequest)")

local cooldowns = {}

attackRemote.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if now - (cooldowns[player] or 0) < CONFIG.Cooldown then
		return
	end
	cooldowns[player] = now

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }
	overlapParams.MaxParts = 60

	local boxCFrame = rootPart.CFrame * CFrame.new(0, 0, -(CONFIG.HitboxSize.Z / 2 + CONFIG.HitboxForward))
	local parts = workspace:GetPartBoundsInBox(boxCFrame, CONFIG.HitboxSize, overlapParams)

	local alreadyHit = {}
	local hitCount = 0

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not alreadyHit[model] then
			local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
			if targetHumanoid and targetHumanoid.Health > 0 then
				alreadyHit[model] = true
				targetHumanoid:TakeDamage(CONFIG.Damage)
				hitCount += 1
				log(("%s 打中 %s，造成 %d 傷害（剩餘 %.0f）"):format(
					player.Name, model.Name, CONFIG.Damage, targetHumanoid.Health))

				if hitCount >= CONFIG.MaxTargets then
					break
				end
			end
		end
	end

	if hitCount == 0 then
		log(player.Name .. " 揮空（判定框內沒有可攻擊的 Humanoid）")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
end)
