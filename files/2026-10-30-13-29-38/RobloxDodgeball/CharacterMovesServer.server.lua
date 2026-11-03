--[[
	=========================================================
	 CharacterMovesServer   （Script，每個玩家共用一支）
	 放置位置：ServerScriptService
	---------------------------------------------------------
	 工作：
	  1. 建立 RemoteEvent  CharacterMoves.AttackRequest（客戶端 F 攻擊用）
	  2. 建立 BindableEvent CharacterMoves.KnifeHit（通知遊戲主腳本「這個人按了攻擊」）
	  3. 擋掉過度頻繁的攻擊請求（防外掛刷傷害）
	---------------------------------------------------------
	 本專案（躲避球大亂鬥）的傷害判定統一由 DodgeballServer 的刀系統處理，
	 所以 F 攻擊和滑鼠點刀共用同一個 0.45 秒冷卻、同樣 20 傷害，
	 擊殺也照樣算給攻擊者（會拿到金幣獎勵）。
	=========================================================
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--============================ 可調整設定 ============================
local CONFIG = {
	Debug = true,        -- true = 在 Output 印出攻擊請求
	Cooldown = 0.22,     -- 客戶端請求最短間隔（真正的刀冷卻在 DodgeballServer）
}
--====================================================================

local function log(...)
	if CONFIG.Debug then
		print("[CharacterMoves:Server]", ...)
	end
end

-- 建立資料夾 / RemoteEvent / BindableEvent
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

local knifeHitEvent = folder:FindFirstChild("KnifeHit")
if not knifeHitEvent then
	knifeHitEvent = Instance.new("BindableEvent")
	knifeHitEvent.Name = "KnifeHit"
	knifeHitEvent.Parent = folder
end

print("[CharacterMoves] 伺服器腳本已啟動 ✔ (RemoteEvent: CharacterMoves.AttackRequest)")

local cooldowns: {[Player]: number} = {}

;(attackRemote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if now - (cooldowns[player] or 0) < CONFIG.Cooldown then
		return
	end
	cooldowns[player] = now

	log(player.Name .. " 攻擊請求 → 交給刀系統判定")
	knifeHitEvent:Fire(player)
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
end)

