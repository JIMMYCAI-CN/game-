--!strict
-- ============================================================
--  躲避球大亂鬥 · 伺服器主腳本
--  放置位置：ServerScriptService（一般 Script）
--  大廳：軍械庫（買刀皮膚，傷害全部一樣）＋抽獎機
--  競技場：圓形浮空躲避球場（球撞死）＋近戰（砍 5 下殺人）
--  隨機盒子：開出不傷人的效果道具（減速/閃盲/疾跑）
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- DataStore：未發佈的專案取不到，用 pcall 保護（拿不到就純記憶體存檔，不影響遊玩）
local STORE = nil
pcall(function()
	STORE = DataStoreService:GetDataStore("DodgeballSave_v1")
end)

-- ------------------------------------------------------------
-- 設定
-- ------------------------------------------------------------
local MIN_PLAYERS = 1          -- 開局最少人數（設 1 方便自己測試，上線可改 2）
local INTERMISSION = 12        -- 開局倒數（秒）
local KNIFE_DMG = 20           -- 每刀傷害（血量 100 → 砍 5 下死，全部皮膚一樣）
local ROUND_TIME_MAX = 180     -- 回合最長時間
local BALL_EVERY = {3.0, 5.5}  -- 每隔幾秒出一顆球（隨機區間）
local BOX_EVERY = {10, 16}     -- 每隔幾秒出一個盒子
local COIN_KILL = 10           -- 刀殺人獎勵
local COIN_WIN = 50            -- 最後生存獎勵
local GACHA_COST = 150
local GACHA_DUP_REFUND = 100   -- 抽到重複的補償金幣

-- 刀皮膚（傷害全部一樣，純外觀）
-- 刀皮膚（傷害全部一樣，純外觀；越貴 → 揮刀特效越華麗，tier 給客戶端選特效）
local KNIVES = {
	{id = "steel",     name = "鋼鐵",     price = 0,    tier = 1, color = Color3.fromRGB(190, 195, 205), dmg = 25, reach = 22, reflectMul = 1.25, skill = "直線回擊", desc = "標準鋼刃，揮刀反彈速度 +25%"},
	{id = "obsidian",  name = "黑曜石",   price = 250,  tier = 2, color = Color3.fromRGB(45, 38, 55),   dmg = 32, reach = 24, reflectMul = 1.40, skill = "重擊震盪", desc = "黑曜重刃，反彈衝擊波附帶強震"},
	{id = "thunder",   name = "雷霆",     price = 400,  tier = 3, color = Color3.fromRGB(90, 160, 255),  dmg = 40, reach = 25, reflectMul = 1.55, skill = "電漿超載", desc = "電光迅刃，反彈球超高速筆直貫穿"},
	{id = "sakura",    name = "櫻花",     price = 600,  tier = 4, color = Color3.fromRGB(255, 170, 200), dmg = 48, reach = 26, reflectMul = 1.65, skill = "櫻瓣追蹤", desc = "優雅名刀，反彈球弧線微追最近敵人"},
	{id = "frost",     name = "冰霜",     price = 800,  tier = 4, color = Color3.fromRGB(160, 230, 255), dmg = 55, reach = 26, reflectMul = 1.70, skill = "寒冰減速", desc = "砍人減速 3 秒，反彈球附帶霜凍"},
	{id = "astra",     name = "阿斯特拉", price = 1200, tier = 5, color = Color3.fromRGB(120, 255, 180), dmg = 65, reach = 28, reflectMul = 1.85, skill = "雙球並射", desc = "星界神刃，可同時反彈範圍內 2 顆球"},
	{id = "hydra",     name = "九頭蛇",   price = 1600, tier = 5, color = Color3.fromRGB(110, 220, 90),  dmg = 75, reach = 28, reflectMul = 2.00, skill = "劇毒撕裂", desc = "劇毒淬刃，砍中玩家附帶持續流血"},
	{id = "blueflame", name = "藍焰",     price = 2000, tier = 6, color = Color3.fromRGB(60, 160, 255),  dmg = 88, reach = 30, reflectMul = 2.20, skill = "冥火獵犬", desc = "蒼焰索敵，反彈球強力追獵最近目標"},
	{id = "phoenix",   name = "鳳凰",     price = 3000, tier = 6, color = Color3.fromRGB(255, 120, 40),  dmg = 100, reach = 32, reflectMul = 2.50, skill = "涅槃焚天", desc = "至尊神話，一刀必殺，反彈球烈焰爆破"},
}

local KNIFE_BY_ID = {}
for _, k in ipairs(KNIVES) do KNIFE_BY_ID[k.id] = k end

-- 抽獎池（權重：越貴越難抽）
local GACHA_POOL = {
	{id = "steel", w = 20}, {id = "obsidian", w = 18}, {id = "thunder", w = 14},
	{id = "sakura", w = 12}, {id = "frost", w = 10}, {id = "astra", w = 8},
	{id = "hydra", w = 7}, {id = "blueflame", w = 5}, {id = "phoenix", w = 3},
}

-- 效果道具（全部不造成傷害）
local ITEMS = {
	{id = "slowtrap", name = "減速陷阱", desc = "放在地上，踩到的敵人變慢 5 秒", color = Color3.fromRGB(150, 100, 255)},
	{id = "flash",    name = "閃光震撼彈", desc = "讓附近的敵人失明 4 秒",         color = Color3.fromRGB(255, 240, 150)},
	{id = "speed",    name = "疾風神水", desc = "自身移速提升 65% 持續 6 秒",     color = Color3.fromRGB(120, 255, 160)},
	{id = "teleport", name = "次元瞬移", desc = "向視角前方瞬間穿梭 35 格",       color = Color3.fromRGB(100, 200, 255)},
	{id = "swap",     name = "乾坤換位", desc = "與場上一名隨機對手互換位置",     color = Color3.fromRGB(255, 110, 220)},
	{id = "barrier",  name = "無敵金鐘罩", desc = "獲得 3.5 秒能量護盾免傷免撞",   color = Color3.fromRGB(255, 225, 80)},
}

-- ------------------------------------------------------------
-- 地圖系統：5 種形狀 × 3 種地板 = 15 張地圖，大廳踩板投票
-- ------------------------------------------------------------
local SHAPES = {"圓形", "正方形", "三角形", "五邊形", "星星"}
local FLOORS = {
	{id = "stone", name = "石頭", color = Color3.fromRGB(86, 62, 72),  material = Enum.Material.Slate, friction = 0.35},
	{id = "sand",  name = "沙地", color = Color3.fromRGB(216, 190, 130), material = Enum.Material.Sand,  friction = 0.35, speedMul = 0.6},
	{id = "ice",   name = "冰面", color = Color3.fromRGB(170, 220, 245), material = Enum.Material.Ice,   friction = 0.02},
}
local MAPS = {}          -- 15 張：{shape=…, floor=…, name="圓形·石頭"}
for si, sname in ipairs(SHAPES) do
	for fi, f in ipairs(FLOORS) do
		table.insert(MAPS, {shape = si, floor = fi, name = sname .. "·" .. f.name})
	end
end

local votes: {[Player]: number} = {}      -- 每個玩家投的地圖編號
local currentMap = 1                      -- 本回合用的地圖
local slowUntil: {[Player]: number} = {}  -- 減速道具結束時間
local speedUntil: {[Player]: number} = {} -- 疾風藥水結束時間
local spectating: {[Player]: boolean} = {} -- 觀戰名單：不進本回合

-- ------------------------------------------------------------
-- RemoteEvent（單一通道，act 欄位區分動作）
-- ------------------------------------------------------------
local Net = Instance.new("RemoteEvent")
Net.Name = "DodgeNet"
Net.Parent = ReplicatedStorage

local function send(plr: Player?, act: string, data: any?)
	if not plr or not plr:IsA("Player") or not plr.Parent then return end
	Net:FireClient(plr, {act = act, data = data})
end
local function broadcast(act: string, data: any?)
	Net:FireAllClients({act = act, data = data})
end

-- ------------------------------------------------------------
-- 玩家資料（含簡單雲存檔）
-- ------------------------------------------------------------
type PD = {coins: number, kills: number, owned: {[string]: boolean}, equipped: string, items: {string}, loginStreak: number, lastClaimDay: number}
local pData: {[Player]: PD} = {}

local function defaultData(): PD
	return {coins = 250, kills = 0, owned = {steel = true}, equipped = "steel", items = {}, loginStreak = 1, lastClaimDay = 0}
end

local function load(plr: Player)
	local d: PD = defaultData()
	if not STORE then
		pData[plr] = d
		return
	end
	local ok, saved = pcall(function()
		return STORE:GetAsync("u_" .. plr.UserId)
	end)
	if ok and type(saved) == "table" then
		d.coins = tonumber(saved.coins) or 250
		d.kills = tonumber(saved.kills) or 0
		if type(saved.owned) == "table" then
			for id in pairs(saved.owned) do
				if KNIFE_BY_ID[id] then d.owned[id] = true end
			end
		end
		if KNIFE_BY_ID[saved.equipped] and d.owned[saved.equipped] then
			d.equipped = saved.equipped
		end
		d.loginStreak = tonumber(saved.loginStreak) or 1
		d.lastClaimDay = tonumber(saved.lastClaimDay) or 0
	end
	pData[plr] = d
end

local function save(plr: Player)
	local d = pData[plr]
	if not d or not STORE then return end
	pcall(function()
		STORE:SetAsync("u_" .. plr.UserId, {
			coins = d.coins, kills = d.kills, owned = d.owned, equipped = d.equipped,
			loginStreak = d.loginStreak, lastClaimDay = d.lastClaimDay,
		})
	end)
end

local function pd(plr: Player): PD
	return pData[plr] or defaultData()
end

local function syncLeader(plr: Player)
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local c = ls:FindFirstChild("金幣"); if c then c.Value = pd(plr).coins end
		local k = ls:FindFirstChild("擊殺"); if k then k.Value = pd(plr).kills end
	end
end

Players.PlayerAdded:Connect(function(plr)
	load(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local c = Instance.new("IntValue"); c.Name = "金幣"; c.Value = pd(plr).coins; c.Parent = ls
	local k = Instance.new("IntValue"); k.Name = "擊殺"; k.Value = pd(plr).kills; k.Parent = ls
	ls.Parent = plr
	send(plr, "coins", pd(plr).coins)
	local today = math.floor(os.time() / 86400)
	local d = pd(plr)
	if today > (d.lastClaimDay or 0) + 1 then
		d.loginStreak = 1
	end
	send(plr, "daily_status", {
		streak = d.loginStreak or 1,
		canClaim = (today > (d.lastClaimDay or 0)),
		day = math.clamp(d.loginStreak or 1, 1, 7),
	})
	send(plr, "ultimate_charge", 0)
end)

Players.PlayerRemoving:Connect(function(plr)
	save(plr)
	pData[plr] = nil
	votes[plr] = nil :: any
	spectating[plr] = nil :: any
	slowUntil[plr] = nil :: any
	speedUntil[plr] = nil :: any
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do save(plr) end
end)

-- ------------------------------------------------------------
-- 建場景工具
-- ------------------------------------------------------------
local workspace = game:GetService("Workspace")

local Lighting = game:GetService("Lighting")

-- 清掉 Studio 裡手動放的同類特效（名字不同會與腳本建立的重疊，導致畫面過曝）
local KEEP_FX = {
	BloomEffect = "Bloom", ColorCorrectionEffect = "Grade",
	SunRaysEffect = "SunRays", DepthOfFieldEffect = "Depth",
}
for _, c in ipairs(Lighting:GetChildren()) do
	local keep = KEEP_FX[c.ClassName]
	if keep and c.Name ~= keep then
		c:Destroy()
	end
end

local function ensureFx(className: string, name: string)
	local inst = Lighting:FindFirstChild(name)
	if inst and inst.ClassName ~= className then
		inst:Destroy()
		inst = nil
	end
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst
end

local function setupLighting()
	-- 真實光照（Future 有最漂亮的陰影與環境光遮蔽；不支援才退回）
	local futureOk = pcall(function()
		Lighting.Technology = Enum.Technology.Future
		Lighting.Technology = Enum.Technology.Future
	end)
	if not futureOk then
		pcall(function() Lighting.Technology = Enum.Technology.Voxel end)
	end

	-- 黃昏時刻：低角度太陽 → 長影子 + 暖色輪廓光
	Lighting.ClockTime = 17.35
	Lighting.GeographicLatitude = 14
	Lighting.Brightness = 2.35
	Lighting.ExposureCompensation = 0.12
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.42
	Lighting.Ambient = Color3.fromRGB(62, 66, 88)
	Lighting.OutdoorAmbient = Color3.fromRGB(104, 110, 140)
	Lighting.EnvironmentDiffuseScale = 0.62
	Lighting.EnvironmentSpecularScale = 0.72
	Lighting.FogColor = Color3.fromRGB(168, 176, 200)
	Lighting.FogStart = 320
	Lighting.FogEnd = 3200

	-- 大氣：遠景霧氣讓浮空島與競技場有縱深
	local atmo = ensureFx("Atmosphere", "Atmosphere") :: Atmosphere
	atmo.Density = 0.22
	atmo.Offset = 0.16
	atmo.Color = Color3.fromRGB(198, 208, 232)
	atmo.Decay = Color3.fromRGB(104, 110, 152)
	atmo.Glare = 0.4
	atmo.Haze = 1.1

	-- 雲層
	local clouds = Lighting:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		local c2 = clouds :: any
		c2.Name = "Clouds"
		c2.Parent = Lighting
	end
	pcall(function()
		clouds.Cover = 0.58
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(255, 244, 232)
		clouds.Enabled = true
	end)

	-- 泛光：只讓霓虹與高光溢出，材質不會糊
	local bloom = ensureFx("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.9
	bloom.Size = 24
	bloom.Threshold = 0.94

	-- 色彩分級：稍高對比、飽和一點，畫面更有「遊戲感」
	local grade = ensureFx("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	grade.Brightness = 0.015
	grade.Contrast = 0.2
	grade.Saturation = 0.24
	grade.TintColor = Color3.fromRGB(255, 243, 228)

	-- 太陽光暈
	local rays = ensureFx("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.16
	rays.Spread = 0.9

	-- 極輕的景深（只讓極遠景柔化，不影響看球）
	local dof = ensureFx("DepthOfFieldEffect", "Depth") :: DepthOfFieldEffect
	dof.NearIntensity = 0
	dof.FarIntensity = 0.08
	dof.FocusDistance = 120
	dof.InFocusRadius = 90
end

setupLighting()

local function part(props: {[string]: any}, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k2, v in pairs(props) do
		pcall(function()
			(p :: any)[k2] = v
		end)
	end
	p.Parent = parent or workspace
	return p
end

-- ------------------------------------------------------------
-- 大廳（浮空島：草地＋木頭甲板＋鳥居＋軍械庫櫃檯＋抽獎機＋排行板）
-- ------------------------------------------------------------
local LOBBY_CENTER = Vector3.new(0, 50, 0)

-- 清掉範本預設的 Baseplate / 舊出生點，避免玩家出生在下面的平台
for _, nm in ipairs({"Baseplate", "SpawnLocation"}) do
	local obj = workspace:FindFirstChild(nm)
	if obj then obj:Destroy() end
end

-- ------------------------------------------------------------
-- 匯入的 3D 模型（FBX）：找得到模板就用模型，找不到就退回積木版
-- ------------------------------------------------------------
local function findModelTemplate(keys: {string}): Model?
	local function match(n: string): boolean
		local low = string.lower(n)
		for _, k in ipairs(keys) do
			if string.find(low, string.lower(k), 1, true) then return true end
		end
		return false
	end
	local containers: {Instance} = {ReplicatedStorage, game:GetService("ServerStorage")}
	for _, d in ipairs(workspace:GetChildren()) do
		if (d:IsA("Folder") or d:IsA("Model")) and d.Name ~= "Lobby" and d.Name ~= "Arena" then
			table.insert(containers, d)
		end
	end
	for _, c in ipairs(containers) do
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("Model") and match(d.Name) then return d end
		end
	end
	return nil
end

-- 把模型放到 pos（底部貼地）、等比縮放到 height 高、繞包圍盒中心轉 yaw
local function placeModel(tpl: Model, pos: Vector3, height: number, yaw: number): Model?
	local ok, res = pcall(function()
		local m = tpl:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		m.Parent = workspace
		local _, size = m:GetBoundingBox()
		if height > 0 and size.Y > 0.01 then
			m:ScaleTo(height / size.Y)
		end
		local cf, sz = m:GetBoundingBox()
		local center = Vector3.new(pos.X, pos.Y + sz.Y / 2, pos.Z)
		m:PivotTo(m:GetPivot() + (center - cf.Position))
		if yaw ~= 0 then
			local rot = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.new(-center)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then d.CFrame = rot * d.CFrame end
			end
		end
		return m
	end)
	if not ok then
		warn("放置模型失敗：" .. tostring(res))
		return nil
	end
	return res :: any
end

local function buildLobby()
	local oldIsland = workspace:FindFirstChild("Lobby")
	if oldIsland then oldIsland:Destroy() end
	local island = Instance.new("Model")
	island.Name = "Lobby"

	-- ============================================================
	-- 典雅豪氣浮空仙島大廳（直徑 190 格，大氣開闊，白玉大理石+胡桃木+櫻花，絕非刺眼全黃金光）
	-- ============================================================
	local LY_BASE = -2.0      -- 基座底岩頂面 (Y = 48.0)
	local LY_PLAZA = 0.0      -- 中央白玉廣場 (Y = 50.0)
	local LY_DECK = 0.15      -- 東西側胡桃木迴廊步道 (Y = 50.15)
	local LY_DAIS = 0.30      -- 創作者榮譽殿堂、神龕台座 (Y = 50.30)

	-- 1. 浮空島岩體（層疊玄武岩基座，厚重大器）
	part({Name = "CliffBase1", Size = Vector3.new(192, 28, 192), Position = LOBBY_CENTER + Vector3.new(0, LY_BASE - 14, 0),
		Color = Color3.fromRGB(36, 38, 46), Material = Enum.Material.Basalt}, island)
	part({Name = "CliffBase2", Size = Vector3.new(154, 20, 154), Position = LOBBY_CENTER + Vector3.new(0, LY_BASE - 28, 0),
		Color = Color3.fromRGB(28, 30, 36), Material = Enum.Material.Basalt}, island)
	part({Name = "CliffBase3", Size = Vector3.new(108, 18, 108), Position = LOBBY_CENTER + Vector3.new(0, LY_BASE - 40, 0),
		Color = Color3.fromRGB(22, 24, 30), Material = Enum.Material.Basalt}, island)

	-- 2. 外圍自然青翠草坪與護欄台基（直徑 186 格，半徑 93 格）
	part({Name = "OuterGrassRim", Size = Vector3.new(186, 2.0, 186), Position = LOBBY_CENTER + Vector3.new(0, LY_BASE + 1.0, 0),
		Color = Color3.fromRGB(58, 118, 62), Material = Enum.Material.Grass}, island)

	-- 外圍典雅雕花石欄杆（四方環繞，白灰石材+深色扶手）
	local rimR = 91
	for _, side in ipairs({
		{c = Vector3.new(0, LY_DECK + 2, -rimR), sz = Vector3.new(182, 4.0, 1.8)},
		{c = Vector3.new(0, LY_DECK + 2, rimR), sz = Vector3.new(182, 4.0, 1.8)},
		{c = Vector3.new(-rimR, LY_DECK + 2, 0), sz = Vector3.new(1.8, 4.0, 182)},
		{c = Vector3.new(rimR, LY_DECK + 2, 0), sz = Vector3.new(1.8, 4.0, 182)},
	}) do
		part({Name = "RailingWall", Size = side.sz, Position = LOBBY_CENTER + side.c,
			Color = Color3.fromRGB(210, 215, 222), Material = Enum.Material.SmoothPlastic, Transparency = 0.35, CanCollide = true}, island)
		part({Name = "RailingTop", Size = Vector3.new(side.sz.X > 2 and side.sz.X or 2.2, 0.6, side.sz.Z > 2 and side.sz.Z or 2.2),
			Position = LOBBY_CENTER + side.c + Vector3.new(0, side.sz.Y / 2 + 0.3, 0),
			Color = Color3.fromRGB(48, 32, 24), Material = Enum.Material.WoodPlanks, CanCollide = true}, island)
	end

	-- 3. 中央主廣場：白玉大理石同心圓（直徑 72 格，乾淨開闊）
	part({Name = "PlazaBorder", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 74, 74),
		CFrame = CFrame.new(LOBBY_CENTER + Vector3.new(0, LY_PLAZA, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(45, 48, 56), Material = Enum.Material.Slate}, island)
	part({Name = "PlazaMain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.52, 70, 70),
		CFrame = CFrame.new(LOBBY_CENTER + Vector3.new(0, LY_PLAZA + 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(242, 244, 248), Material = Enum.Material.Marble}, island)
	part({Name = "PlazaInnerMedallion", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.54, 38, 38),
		CFrame = CFrame.new(LOBBY_CENTER + Vector3.new(0, LY_PLAZA + 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(225, 230, 238), Material = Enum.Material.Marble}, island)

	-- 4. 出生點（中央溫潤柔白光環，柔和高雅）
	local sp = Instance.new("SpawnLocation")
	sp.Name = "SpawnLocation"
	sp.Size = Vector3.new(16, 0.6, 16)
	sp.Position = LOBBY_CENTER + Vector3.new(0, LY_PLAZA + 0.06, 0)
	sp.Color = Color3.fromRGB(250, 252, 255)
	sp.Material = Enum.Material.SmoothPlastic
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Parent = island

	local spGlow = Instance.new("SelectionBox")
	spGlow.Adornee = sp
	spGlow.Color3 = Color3.fromRGB(180, 215, 255)
	spGlow.SurfaceTransparency = 0.85
	spGlow.Parent = sp

	-- 5. 東西向胡桃木景觀休閒木廊步道
	part({Name = "WestPromenade", Size = Vector3.new(52, 0.45, 26), Position = LOBBY_CENTER + Vector3.new(-54, LY_DECK, 0),
		Color = Color3.fromRGB(72, 48, 36), Material = Enum.Material.WoodPlanks}, island)
	part({Name = "EastPromenade", Size = Vector3.new(52, 0.45, 26), Position = LOBBY_CENTER + Vector3.new(54, LY_DECK, 0),
		Color = Color3.fromRGB(72, 48, 36), Material = Enum.Material.WoodPlanks}, island)

	-- 北向通往地圖投票大殿的神聖白石步道
	part({Name = "NorthWalkway", Size = Vector3.new(24, 0.45, 42), Position = LOBBY_CENTER + Vector3.new(0, LY_DECK, -36),
		Color = Color3.fromRGB(235, 238, 242), Material = Enum.Material.Marble}, island)

	-- 南向通往創作者榮譽殿堂的紅毯木質步道
	part({Name = "SouthWalkway", Size = Vector3.new(26, 0.45, 36), Position = LOBBY_CENTER + Vector3.new(0, LY_DECK, 32),
		Color = Color3.fromRGB(72, 48, 36), Material = Enum.Material.WoodPlanks}, island)
	part({Name = "SouthCarpet", Size = Vector3.new(12, 0.48, 32), Position = LOBBY_CENTER + Vector3.new(0, LY_DECK + 0.03, 32),
		Color = Color3.fromRGB(145, 38, 42), Material = Enum.Material.Fabric}, island)

	-- 6. 真實唯美和風櫻花樹（老幹虯枝、多層次漸層花簇、飄落花瓣粒子與落櫻地毯）
	local function makeSakuraTree(x, z, scale)
		scale = scale or 1.0
		local basePos = LOBBY_CENTER + Vector3.new(x, LY_DECK, z)
		local barkCol = Color3.fromRGB(56, 38, 30)

		-- 樹幹基座（四向盤根）
		part({Name = "RootBase", Size = Vector3.new(3.8 * scale, 1.0 * scale, 3.8 * scale),
			Position = basePos + Vector3.new(0, 0.4 * scale, 0),
			Color = barkCol, Material = Enum.Material.Wood}, island)

		-- 虯曲傾斜主幹（多段自然蒼勁造型）
		local t1 = part({Name = "Trunk1", Size = Vector3.new(2.4 * scale, 5.5 * scale, 2.4 * scale),
			Position = basePos + Vector3.new(0, 3.0 * scale, 0),
			Color = barkCol, Material = Enum.Material.Wood}, island)
		t1.CFrame = CFrame.new(basePos + Vector3.new(0, 3.0 * scale, 0)) * CFrame.Angles(math.rad(4), 0, math.rad(-5))

		local t2 = part({Name = "Trunk2", Size = Vector3.new(2.0 * scale, 5.0 * scale, 2.0 * scale),
			Position = basePos + Vector3.new(-0.4 * scale, 7.5 * scale, 0.3 * scale),
			Color = barkCol, Material = Enum.Material.Wood}, island)
		t2.CFrame = CFrame.new(basePos + Vector3.new(-0.4 * scale, 7.5 * scale, 0.3 * scale)) * CFrame.Angles(math.rad(-6), 0, math.rad(7))

		-- 四向舒展枝椏
		local BRANCHES = {
			{off = Vector3.new(2.2, 9.8, 1.2), sz = Vector3.new(1.2, 4.5, 1.2), ang = CFrame.Angles(math.rad(30), math.rad(25), math.rad(-35))},
			{off = Vector3.new(-2.4, 9.5, -1.0), sz = Vector3.new(1.2, 4.2, 1.2), ang = CFrame.Angles(math.rad(-25), math.rad(-40), math.rad(30))},
			{off = Vector3.new(0.8, 10.5, -2.2), sz = Vector3.new(1.1, 4.0, 1.1), ang = CFrame.Angles(math.rad(-35), math.rad(10), math.rad(-15))},
			{off = Vector3.new(-1.0, 11.2, 2.0), sz = Vector3.new(1.1, 4.2, 1.1), ang = CFrame.Angles(math.rad(28), math.rad(-20), math.rad(20))},
		}
		for _, b in ipairs(BRANCHES) do
			local br = part({Name = "Branch", Size = b.sz * scale,
				Position = basePos + b.off * scale,
				Color = barkCol, Material = Enum.Material.Wood}, island)
			br.CFrame = CFrame.new(basePos + b.off * scale) * b.ang
		end

		-- 多層次雲狀漸層花簇（櫻粉、淡粉、白粉立體交錯）
		local CLUSTERS = {
			{off = Vector3.new(0, 13.5, 0), sz = Vector3.new(10.5, 6.5, 10.5), col = Color3.fromRGB(255, 195, 218)},
			{off = Vector3.new(3.2, 12.0, 1.8), sz = Vector3.new(8.2, 5.5, 8.2), col = Color3.fromRGB(255, 180, 210)},
			{off = Vector3.new(-3.4, 11.8, -1.5), sz = Vector3.new(8.0, 5.2, 8.0), col = Color3.fromRGB(255, 208, 228)},
			{off = Vector3.new(1.2, 12.8, -3.2), sz = Vector3.new(7.6, 5.0, 7.6), col = Color3.fromRGB(250, 175, 205)},
			{off = Vector3.new(-1.5, 13.2, 3.0), sz = Vector3.new(7.8, 5.0, 7.8), col = Color3.fromRGB(255, 215, 235)},
			{off = Vector3.new(2.0, 14.8, -0.8), sz = Vector3.new(6.5, 4.5, 6.5), col = Color3.fromRGB(255, 228, 240)},
			{off = Vector3.new(-1.8, 14.5, 1.0), sz = Vector3.new(6.8, 4.2, 6.8), col = Color3.fromRGB(255, 190, 215)},
		}
		for _, c in ipairs(CLUSTERS) do
			part({Name = "BlossomCrown", Shape = Enum.PartType.Ball,
				Size = c.sz * scale,
				Position = basePos + c.off * scale,
				Color = c.col, Material = Enum.Material.Grass}, island)
		end

		-- 飄落櫻花瓣粒子系統（微風吹拂，斜向旋轉飄落）
		local emitterPart = part({Name = "PetalEmitter", Size = Vector3.new(8 * scale, 1, 8 * scale),
			Position = basePos + Vector3.new(0, 14 * scale, 0),
			Transparency = 1, CanCollide = false}, island)
		local pe = Instance.new("ParticleEmitter")
		pe.Rate = 5
		pe.Lifetime = NumberRange.new(5, 8)
		pe.Speed = NumberRange.new(1.5, 3.0)
		pe.Acceleration = Vector3.new(1.6, -1.8, 0.8)
		pe.SpreadAngle = Vector2.new(50, 50)
		pe.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 235)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 185, 215)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(250, 160, 195))
		})
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45 * scale),
			NumberSequenceKeypoint.new(0.8, 0.38 * scale),
			NumberSequenceKeypoint.new(1, 0.15 * scale)
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(0.8, 0.25),
			NumberSequenceKeypoint.new(1, 1.0)
		})
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-45, 45)
		pe.Parent = emitterPart

		-- 地面落櫻花瓣地毯
		local carpet = part({Name = "PetalCarpet", Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.08, 14 * scale, 14 * scale),
			Position = basePos + Vector3.new(0, 0.05, 0),
			Color = Color3.fromRGB(255, 195, 220), Material = Enum.Material.Sand,
			Transparency = 0.55, CanCollide = false}, island)
		carpet.CFrame = CFrame.new(basePos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- 櫻花樹圍繞在廣場四季景觀四周
	makeSakuraTree(-48, -45, 1.15)
	makeSakuraTree(48, -45, 1.15)
	makeSakuraTree(-68, 38, 1.05)
	makeSakuraTree(68, 38, 1.05)
	makeSakuraTree(-78, -12, 0.95)
	makeSakuraTree(78, -12, 0.95)

	-- ------------------------------------------------------------
	-- 大廳全新場景元素：枯山水庭石景觀、錦鯉木拱橋、軍械庫兵器架
	-- ------------------------------------------------------------
	-- 1. 西北角：枯山水禪意景觀（Zen Rock Garden）
	local zenC = LOBBY_CENTER + Vector3.new(-42, LY_DECK, -26)
	part({Name = "ZenGravel", Size = Vector3.new(22, 0.3, 18), Position = zenC + Vector3.new(0, 0.15, 0),
		Color = Color3.fromRGB(205, 208, 215), Material = Enum.Material.Sand}, island)
	part({Name = "ZenBorder", Size = Vector3.new(23, 0.5, 19), Position = zenC + Vector3.new(0, 0.25, 0),
		Color = Color3.fromRGB(72, 50, 40), Material = Enum.Material.WoodPlanks}, island)
	-- 禪石（高低錯落黑玄武岩石組）
	local r1 = part({Name = "ZenRock1", Size = Vector3.new(4.5, 3.6, 3.8), Position = zenC + Vector3.new(-4, 1.8, -2),
		Color = Color3.fromRGB(48, 52, 60), Material = Enum.Material.Slate}, island)
	r1.CFrame = CFrame.new(zenC + Vector3.new(-4, 1.8, -2)) * CFrame.Angles(math.rad(15), math.rad(35), math.rad(-10))
	local r2 = part({Name = "ZenRock2", Size = Vector3.new(3.2, 2.4, 2.8), Position = zenC + Vector3.new(2, 1.2, 3),
		Color = Color3.fromRGB(60, 64, 72), Material = Enum.Material.Slate}, island)
	r2.CFrame = CFrame.new(zenC + Vector3.new(2, 1.2, 3)) * CFrame.Angles(math.rad(-10), math.rad(-25), math.rad(12))

	-- 2. 東北角：錦鯉木拱橋與幽藍蓮花水景（Koi Stream & Bridge）
	local koiC = LOBBY_CENTER + Vector3.new(42, LY_DECK, -26)
	local water = part({Name = "KoiPond", Size = Vector3.new(20, 0.2, 16), Position = koiC + Vector3.new(0, 0.08, 0),
		Color = Color3.fromRGB(35, 140, 200), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false}, island)
	local waterLt = Instance.new("PointLight")
	waterLt.Color = Color3.fromRGB(80, 190, 255); waterLt.Brightness = 1.2; waterLt.Range = 16; waterLt.Parent = water
	-- 拱橋（弧形木橋）
	for bi = 1, 7 do
		local t = (bi - 4) / 3.0
		local by = math.cos(t * 1.1) * 2.2
		local bAngle = -t * 0.35
		local plank = part({Name = "BridgePlank", Size = Vector3.new(7.5, 0.45, 2.2),
			Position = koiC + Vector3.new(0, by, (bi - 4) * 2.1),
			Color = Color3.fromRGB(135, 45, 38), Material = Enum.Material.WoodPlanks}, island)
		plank.CFrame = CFrame.new(koiC + Vector3.new(0, by, (bi - 4) * 2.1)) * CFrame.Angles(bAngle, 0, 0)
	end

	-- 3. 東側軍械庫：刀劍兵器譜展示架（Weapon Display Racks）
	local rackC = LOBBY_CENTER + Vector3.new(48, LY_DAIS + 0.6, 9)
	part({Name = "WeaponRackFrameL", Size = Vector3.new(0.6, 6.2, 1.2), Position = rackC + Vector3.new(-3.5, 3.1, 0),
		Color = Color3.fromRGB(52, 36, 28), Material = Enum.Material.Wood}, island)
	part({Name = "WeaponRackFrameR", Size = Vector3.new(0.6, 6.2, 1.2), Position = rackC + Vector3.new(3.5, 3.1, 0),
		Color = Color3.fromRGB(52, 36, 28), Material = Enum.Material.Wood}, island)
	for ri = 1, 3 do
		local barY = 1.6 + (ri - 1) * 1.8
		part({Name = "WeaponRackBar", Size = Vector3.new(7.4, 0.3, 0.8), Position = rackC + Vector3.new(0, barY, 0),
			Color = Color3.fromRGB(42, 28, 20), Material = Enum.Material.Wood}, island)
		-- 架上陳列的發光名刀
		local rackBlade = part({Name = "DisplayBlade", Size = Vector3.new(5.5, 0.18, 0.4), Position = rackC + Vector3.new(0, barY + 0.3, 0),
			Color = (ri == 1 and Color3.fromRGB(255, 90, 90)) or (ri == 2 and Color3.fromRGB(120, 210, 255)) or Color3.fromRGB(255, 215, 60),
			Material = Enum.Material.Neon}, island)
	end

	-- 典雅石燈籠（散發柔和溫馨微光，非全屏大黃光）
	local function makeLantern(x, z)
		local baseP = part({Name = "StoneLantern", Size = Vector3.new(1.4, 4.2, 1.4),
			Position = LOBBY_CENTER + Vector3.new(x, LY_DECK + 2.1, z),
			Color = Color3.fromRGB(140, 145, 155), Material = Enum.Material.Slate}, island)
		local lamp = part({Name = "LampCore", Size = Vector3.new(1.1, 1.4, 1.1),
			Position = LOBBY_CENTER + Vector3.new(x, LY_DECK + 4.5, z),
			Color = Color3.fromRGB(255, 246, 220), Material = Enum.Material.Neon}, island)
		local roof = part({Name = "LampRoof", Size = Vector3.new(2.4, 0.6, 2.4),
			Position = LOBBY_CENTER + Vector3.new(x, LY_DECK + 5.4, z),
			Color = Color3.fromRGB(60, 62, 70), Material = Enum.Material.Slate}, island)
		local lt = Instance.new("PointLight")
		lt.Color = Color3.fromRGB(255, 240, 210)
		lt.Brightness = 0.9
		lt.Range = 13
		lt.Parent = lamp
	end

	makeLantern(-22, -18); makeLantern(22, -18)
	makeLantern(-22, 18);  makeLantern(22, 18)
	makeLantern(-54, -14); makeLantern(-54, 14)
	makeLantern(54, -14);  makeLantern(54, 14)

	-- 7. 北方：朱紅宏偉鳥居（通往地圖投票大殿）
	local tZ = -22
	local tP1 = part({Size = Vector3.new(2.4, 17, 2.4), Position = LOBBY_CENTER + Vector3.new(-12, LY_DECK + 8.5, tZ),
		Color = Color3.fromRGB(196, 46, 38), Material = Enum.Material.Wood}, island)
	local tP2 = part({Size = Vector3.new(2.4, 17, 2.4), Position = LOBBY_CENTER + Vector3.new(12, LY_DECK + 8.5, tZ),
		Color = Color3.fromRGB(196, 46, 38), Material = Enum.Material.Wood}, island)
	part({Size = Vector3.new(30, 2.2, 3.2), Position = LOBBY_CENTER + Vector3.new(0, LY_DECK + 17, tZ),
		Color = Color3.fromRGB(196, 46, 38), Material = Enum.Material.Wood}, island)
	part({Size = Vector3.new(34, 1.2, 3.8), Position = LOBBY_CENTER + Vector3.new(0, LY_DECK + 18.4, tZ),
		Color = Color3.fromRGB(32, 34, 40), Material = Enum.Material.SmoothPlastic}, island)

	-- 8. 東側步道：軍械庫神龕（X = 46, Z = 0）
	local shopShrine = Instance.new("Model")
	shopShrine.Name = "ArmoryPavilion"
	local sPlat = part({Size = Vector3.new(18, 1.2, 16), Position = LOBBY_CENTER + Vector3.new(48, LY_DAIS + 0.6, 0),
		Color = Color3.fromRGB(82, 54, 42), Material = Enum.Material.WoodPlanks}, shopShrine)
	local sAltar = part({Size = Vector3.new(6.0, 3.2, 2.6), Position = LOBBY_CENTER + Vector3.new(48, LY_DAIS + 2.4, 0),
		Color = Color3.fromRGB(48, 50, 58), Material = Enum.Material.Slate}, shopShrine)

	local sBlade = part({Size = Vector3.new(0.4, 4.6, 0.9), Position = LOBBY_CENTER + Vector3.new(48, LY_DAIS + 5.5, 0),
		Color = Color3.fromRGB(160, 225, 255), Material = Enum.Material.Neon}, shopShrine)
	local sLight = Instance.new("PointLight")
	sLight.Color = Color3.fromRGB(180, 235, 255); sLight.Brightness = 1.4; sLight.Range = 14; sLight.Parent = sBlade

	local sSign = Instance.new("BillboardGui")
	sSign.Size = UDim2.new(0, 180, 0, 48); sSign.StudsOffset = Vector3.new(0, 3.8, 0); sSign.AlwaysOnTop = true
	local sTxt = Instance.new("TextLabel"); sTxt.Size = UDim2.new(1, 0, 1, 0); sTxt.BackgroundTransparency = 1
	sTxt.Font = Enum.Font.GothamBold; sTxt.Text = "⚔️ 武器軍械庫"; sTxt.TextColor3 = Color3.fromRGB(240, 245, 255)
	sTxt.TextStrokeColor3 = Color3.fromRGB(20, 20, 30); sTxt.TextStrokeTransparency = 0.2; sTxt.TextScaled = true
	sTxt.Parent = sSign; sSign.Parent = sBlade

	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.ActionText = "查看軍械庫"
	shopPrompt.ObjectText = "神兵閣"
	shopPrompt.HoldDuration = 0
	shopPrompt.MaxActivationDistance = 15
	shopPrompt.RequiresLineOfSight = false
	shopPrompt.Parent = sAltar
	shopShrine.Parent = island

	-- 9. 西側步道：幸運扭蛋神殿（X = -46, Z = 0）
	local gachaShrine = Instance.new("Model")
	gachaShrine.Name = "GachaPavilion"
	local gPlat = part({Size = Vector3.new(18, 1.2, 16), Position = LOBBY_CENTER + Vector3.new(-48, LY_DAIS + 0.6, 0),
		Color = Color3.fromRGB(82, 54, 42), Material = Enum.Material.WoodPlanks}, gachaShrine)
	local gBase = part({Size = Vector3.new(5.0, 3.2, 4.0), Position = LOBBY_CENTER + Vector3.new(-48, LY_DAIS + 2.4, 0),
		Color = Color3.fromRGB(185, 45, 50), Material = Enum.Material.SmoothPlastic}, gachaShrine)
	local gGlobe = part({Shape = Enum.PartType.Ball, Size = Vector3.new(4.2, 4.2, 4.2), Position = LOBBY_CENTER + Vector3.new(-48, LY_DAIS + 5.6, 0),
		Color = Color3.fromRGB(255, 220, 235), Material = Enum.Material.Glass, Transparency = 0.3}, gachaShrine)

	local gSign = Instance.new("BillboardGui")
	gSign.Size = UDim2.new(0, 180, 0, 48); gSign.StudsOffset = Vector3.new(0, 3.6, 0); gSign.AlwaysOnTop = true
	local gTxt = Instance.new("TextLabel"); gTxt.Size = UDim2.new(1, 0, 1, 0); gTxt.BackgroundTransparency = 1
	gTxt.Font = Enum.Font.GothamBold; gTxt.Text = "🎁 幸運扭蛋機"; gTxt.TextColor3 = Color3.fromRGB(255, 180, 210)
	gTxt.TextStrokeColor3 = Color3.fromRGB(30, 20, 25); gTxt.TextStrokeTransparency = 0.2; gTxt.TextScaled = true
	gTxt.Parent = gSign; gSign.Parent = gGlobe

	local gachaPrompt = Instance.new("ProximityPrompt")
	gachaPrompt.ActionText = "抽獎 (¥100)"
	gachaPrompt.ObjectText = "幸運扭蛋"
	gachaPrompt.HoldDuration = 0
	gachaPrompt.MaxActivationDistance = 15
	gachaPrompt.RequiresLineOfSight = false
	gachaPrompt.Parent = gBase
	gachaShrine.Parent = island

	-- 10. 南方：三位創作者榮譽殿堂（Z = 46，大氣尊貴，絕不刪除！）
	local creatorDais = Instance.new("Model")
	creatorDais.Name = "CreatorDais"
	part({Name = "DaisPlat", Size = Vector3.new(42, 1.6, 22), Position = LOBBY_CENTER + Vector3.new(0, LY_DAIS + 0.8, 52),
		Color = Color3.fromRGB(240, 242, 248), Material = Enum.Material.Marble}, creatorDais)
	part({Name = "DaisBorder", Size = Vector3.new(43, 0.4, 23), Position = LOBBY_CENTER + Vector3.new(0, LY_DAIS + 1.6, 52),
		Color = Color3.fromRGB(48, 52, 62), Material = Enum.Material.Slate}, creatorDais)

	-- 榮譽殿堂典雅屏風照壁
	part({Name = "ScreenWall", Size = Vector3.new(38, 9, 1.8), Position = LOBBY_CENTER + Vector3.new(0, LY_DAIS + 5.5, 62),
		Color = Color3.fromRGB(74, 48, 38), Material = Enum.Material.WoodPlanks}, creatorDais)
	local screenSign = part({Name = "HallSign", Size = Vector3.new(24, 2.4, 0.4), Position = LOBBY_CENTER + Vector3.new(0, LY_DAIS + 8.5, 61),
		Color = Color3.fromRGB(32, 34, 42), Material = Enum.Material.SmoothPlastic}, creatorDais)

	local hSignBb = Instance.new("BillboardGui")
	hSignBb.Size = UDim2.new(0, 360, 0, 56); hSignBb.StudsOffset = Vector3.new(0, 0, 0); hSignBb.AlwaysOnTop = true
	local hSignTxt = Instance.new("TextLabel"); hSignTxt.Size = UDim2.new(1, 0, 1, 0); hSignTxt.BackgroundTransparency = 1
	hSignTxt.Font = Enum.Font.GothamBold; hSignTxt.Text = "★ 遊戲創作者榮譽殿堂 ★"; hSignTxt.TextColor3 = Color3.fromRGB(255, 235, 140)
	hSignTxt.TextStrokeColor3 = Color3.fromRGB(20, 20, 30); hSignTxt.TextStrokeTransparency = 0.2; hSignTxt.TextScaled = true
	hSignTxt.Parent = hSignBb; hSignBb.Parent = screenSign
	creatorDais.Parent = island

	-- 三位創作者 NPC 生成（抓取真實頭像，放大 1.4 倍，莊嚴迎客）
	task.spawn(function()
		local facePos = LOBBY_CENTER + Vector3.new(0, LY_DAIS + 3, 0)   -- 面對出生點中央
		local creators = {
			{name = "jimmycai27", label = "創作者 jimmy", off = Vector3.new(-10, LY_DAIS + 1.6, 52)},
			{name = "leo5546668ddddd", label = "創作者 leo", off = Vector3.new(0, LY_DAIS + 1.6, 54)},
			{name = "noobKeb", label = "創作者 noob", off = Vector3.new(10, LY_DAIS + 1.6, 52)},
		}
		for _, def in ipairs(creators) do
			local ok, err = pcall(function()
				local uid = Players:GetUserIdFromNameAsync(def.name)
				local desc = Players:GetHumanoidDescriptionFromUserId(uid)
				local m = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
				m.Name = "Creator_" .. def.name
				m:ScaleTo(1.4)
				for _, p2 in ipairs(m:GetDescendants()) do
					if p2:IsA("BasePart") then
						p2.Anchored = true
						p2.CanCollide = false
					end
				end
				local hum = m:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.WalkSpeed = 0
					hum.DisplayName = def.label
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				end
				m:PivotTo(CFrame.lookAt(LOBBY_CENTER + def.off + Vector3.new(0, 3.8, 0), facePos))
				m.Parent = island

				local head = m:FindFirstChild("Head")
				if head then
					local bb = Instance.new("BillboardGui")
					bb.Name = "CreatorTag"
					bb.Size = UDim2.new(0, 220, 0, 52)
					bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
					bb.AlwaysOnTop = true
					bb.MaxDistance = 500
					bb.LightInfluence = 0
					bb.Parent = head
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.new(1, 0, 1, 0)
					tl.BackgroundTransparency = 1
					tl.Font = Enum.Font.GothamBold
					tl.TextSize = 22
					tl.TextColor3 = Color3.fromRGB(255, 235, 140)
					tl.TextStrokeColor3 = Color3.fromRGB(20, 20, 30)
					tl.TextStrokeTransparency = 0.2
					tl.Text = "👑 " .. def.label
					tl.Parent = bb
				end
			end)
			if not ok then
				warn("[Lobby] 載入創作者 NPC 失敗: " .. def.name .. " -> " .. tostring(err))
			end
		end
	end)


	-- ============================================================
	-- 12. 休閒設施：長椅、櫻花鞦韆、沙發（均帶 Roblox Seat，坐下自動播放動作 110976420397279）
	-- ============================================================
	local furnFolder = Instance.new("Folder")
	furnFolder.Name = "Furniture"
	furnFolder.Parent = island

	local function makeBench(cf: CFrame)
		local bench = Instance.new("Model")
		bench.Name = "ParkBench"

		-- 鑄鐵椅架
		for _, xOff in ipairs({-2.2, 2.2}) do
			local leg = Instance.new("Part")
			leg.Name = "IronLeg"
			leg.Size = Vector3.new(0.3, 1.4, 1.8)
			leg.Color = Color3.fromRGB(38, 40, 44)
			leg.Material = Enum.Material.Metal
			leg.Anchored = true; leg.CanCollide = true
			leg.CFrame = cf * CFrame.new(xOff, 0.7, 0)
			leg.Parent = bench

			local arm = Instance.new("Part")
			arm.Name = "Armrest"
			arm.Size = Vector3.new(0.35, 0.25, 1.9)
			arm.Color = Color3.fromRGB(48, 52, 58)
			arm.Material = Enum.Material.Metal
			arm.Anchored = true; arm.CanCollide = true
			arm.CFrame = cf * CFrame.new(xOff, 1.45, -0.05)
			arm.Parent = bench
		end

		-- 木質坐墊板條
		for i = 1, 4 do
			local slat = Instance.new("Part")
			slat.Name = "SeatSlat" .. i
			slat.Size = Vector3.new(4.4, 0.18, 0.36)
			slat.Color = Color3.fromRGB(115, 75, 48)
			slat.Material = Enum.Material.WoodPlanks
			slat.Anchored = true; slat.CanCollide = true
			slat.CFrame = cf * CFrame.new(0, 1.15, -0.6 + i * 0.4)
			slat.Parent = bench
		end

		-- 木質靠背
		for i = 1, 3 do
			local back = Instance.new("Part")
			back.Name = "BackSlat" .. i
			back.Size = Vector3.new(4.4, 0.32, 0.18)
			back.Color = Color3.fromRGB(125, 82, 54)
			back.Material = Enum.Material.WoodPlanks
			back.Anchored = true; back.CanCollide = true
			back.CFrame = cf * CFrame.new(0, 1.5 + i * 0.38, -0.7) * CFrame.Angles(math.rad(-10), 0, 0)
			back.Parent = bench
		end

		local seat = Instance.new("Seat")
		seat.Name = "Seat"
		seat.Size = Vector3.new(4.2, 0.3, 1.5)
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CFrame = cf * CFrame.new(0, 1.25, 0.15) * CFrame.Angles(0, math.pi, 0)
		seat.Parent = bench

		bench.Parent = furnFolder
		return bench
	end

	local function makeSwing(cf: CFrame)
		local swing = Instance.new("Model")
		swing.Name = "CherryBlossomSwing"

		local topBeam = Instance.new("Part")
		topBeam.Name = "TopBeam"
		topBeam.Size = Vector3.new(8.0, 0.6, 0.6)
		topBeam.Color = Color3.fromRGB(75, 46, 32)
		topBeam.Material = Enum.Material.Wood
		topBeam.Anchored = true; topBeam.CanCollide = true
		topBeam.CFrame = cf * CFrame.new(0, 6.2, 0)
		topBeam.Parent = swing

		for _, xSide in ipairs({-3.6, 3.6}) do
			for _, zAng in ipairs({-18, 18}) do
				local post = Instance.new("Part")
				post.Name = "SwingPost"
				post.Size = Vector3.new(0.5, 6.6, 0.5)
				post.Color = Color3.fromRGB(85, 52, 36)
				post.Material = Enum.Material.Wood
				post.Anchored = true; post.CanCollide = true
				post.CFrame = cf * CFrame.new(xSide, 3.1, 0) * CFrame.Angles(0, 0, math.rad(xSide > 0 and -8 or 8)) * CFrame.Angles(math.rad(zAng), 0, 0)
				post.Parent = swing
			end
		end

		for _, xOff in ipairs({-2.0, 2.0}) do
			for _, zOff in ipairs({-0.45, 0.45}) do
				local chain = Instance.new("Part")
				chain.Name = "SwingChain"
				chain.Size = Vector3.new(0.08, 4.2, 0.08)
				chain.Color = Color3.fromRGB(180, 180, 190)
				chain.Material = Enum.Material.Metal
				chain.Anchored = true; chain.CanCollide = false
				chain.CFrame = cf * CFrame.new(xOff, 3.8, zOff)
				chain.Parent = swing
			end
		end

		local seatPlank = Instance.new("Part")
		seatPlank.Name = "SwingPlank"
		seatPlank.Size = Vector3.new(4.8, 0.25, 1.6)
		seatPlank.Color = Color3.fromRGB(140, 90, 58)
		seatPlank.Material = Enum.Material.WoodPlanks
		seatPlank.Anchored = true; seatPlank.CanCollide = true
		seatPlank.CFrame = cf * CFrame.new(0, 1.6, 0)
		seatPlank.Parent = swing

		local seatBack = Instance.new("Part")
		seatBack.Name = "SwingBack"
		seatBack.Size = Vector3.new(4.8, 0.9, 0.2)
		seatBack.Color = Color3.fromRGB(140, 90, 58)
		seatBack.Material = Enum.Material.WoodPlanks
		seatBack.Anchored = true; seatBack.CanCollide = true
		seatBack.CFrame = cf * CFrame.new(0, 2.15, -0.7)
		seatBack.Parent = swing

		local sL = Instance.new("Seat")
		sL.Name = "SeatL"
		sL.Size = Vector3.new(2.1, 0.25, 1.4)
		sL.Transparency = 1; sL.Anchored = true; sL.CanCollide = false
		sL.CFrame = cf * CFrame.new(-1.2, 1.75, 0) * CFrame.Angles(0, math.pi, 0)
		sL.Parent = swing

		local sR = Instance.new("Seat")
		sR.Name = "SeatR"
		sR.Size = Vector3.new(2.1, 0.25, 1.4)
		sR.Transparency = 1; sR.Anchored = true; sR.CanCollide = false
		sR.CFrame = cf * CFrame.new(1.2, 1.75, 0) * CFrame.Angles(0, math.pi, 0)
		sR.Parent = swing

		swing.Parent = furnFolder
		return swing
	end

	-- 擺放 4 張景觀長椅（面向大廳廣場）
	makeBench(CFrame.new(LOBBY_CENTER + Vector3.new(0, LY_DECK, -46)) * CFrame.Angles(0, math.rad(0), 0))
	makeBench(CFrame.new(LOBBY_CENTER + Vector3.new(46, LY_DECK, -30)) * CFrame.Angles(0, math.rad(-125), 0))
	makeBench(CFrame.new(LOBBY_CENTER + Vector3.new(-46, LY_DECK, -30)) * CFrame.Angles(0, math.rad(125), 0))
	makeBench(CFrame.new(LOBBY_CENTER + Vector3.new(-45, LY_DECK, 34)) * CFrame.Angles(0, math.rad(45), 0))

	-- 擺放浪漫櫻花樹下雙人鞦韆（西南花園）
	makeSwing(CFrame.new(LOBBY_CENTER + Vector3.new(-38, LY_DECK, 46)) * CFrame.Angles(0, math.rad(30), 0))

	-- 擺放用戶模型（憤怒鳥、沙發、茶几、排行榜等）
	local deco = game:GetService("ServerStorage"):FindFirstChild("LobbyDeco")
	if deco then
		local function spawnDecoModel(name: string, targetX: number, targetFloorY: number, targetZ: number, scaleMultiplier: number?)
			local tpl = deco:FindFirstChild(name)
			if not tpl then return nil end
			local m = tpl:Clone()
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = true
				end
			end
			if scaleMultiplier and scaleMultiplier ~= 1.0 and m:IsA("Model") then
				pcall(function() m:ScaleTo(scaleMultiplier) end)
			end

			-- 面向大廳中心 (0, 50, 0)，絕不面壁思過！
			local pos = Vector3.new(targetX, targetFloorY, targetZ)
			local lookCF = CFrame.lookAt(pos, Vector3.new(LOBBY_CENTER.X, pos.Y, LOBBY_CENTER.Z))

			if m:IsA("Model") then
				m:PivotTo(lookCF)
				local cf, sz = m:GetBoundingBox()
				local bottomY = cf.Position.Y - sz.Y / 2
				local deltaY = (targetFloorY + 0.05) - bottomY
				local finalPos = Vector3.new(targetX, cf.Position.Y + deltaY, targetZ)
				m:PivotTo(CFrame.new(finalPos) * lookCF.Rotation)
			elseif m:IsA("BasePart") then
				local sz = m.Size
				m.CFrame = CFrame.new(targetX, targetFloorY + sz.Y / 2 + 0.05, targetZ) * lookCF.Rotation
			end
			m.Parent = island
			return m
		end

		local floorY = LOBBY_CENTER.Y + LY_DECK
		local daisY = LOBBY_CENTER.Y + LY_DAIS

		-- 東側休閒茶歇區（Loveseat 沙發帶 Seat、茶几與收音機、憤怒鳥 Chuck、Matilda、Minion Pig）
		local sofa = spawnDecoModel("Loveseat_Dark stone grey", LOBBY_CENTER.X + 58, floorY, LOBBY_CENTER.Z + 6)
		if sofa then
			local s1 = Instance.new("Seat")
			s1.Name = "SofaSeatL"; s1.Size = Vector3.new(2.2, 0.4, 2.2); s1.Transparency = 1; s1.Anchored = true; s1.CanCollide = false
			s1.CFrame = CFrame.new(LOBBY_CENTER.X + 56.5, floorY + 1.2, LOBBY_CENTER.Z + 6) * CFrame.Angles(0, math.pi, 0)
			s1.Parent = sofa

			local s2 = Instance.new("Seat")
			s2.Name = "SofaSeatR"; s2.Size = Vector3.new(2.2, 0.4, 2.2); s2.Transparency = 1; s2.Anchored = true; s2.CanCollide = false
			s2.CFrame = CFrame.new(LOBBY_CENTER.X + 59.5, floorY + 1.2, LOBBY_CENTER.Z + 6) * CFrame.Angles(0, math.pi, 0)
			s2.Parent = sofa
		end

		local tableModel = spawnDecoModel("Table", LOBBY_CENTER.X + 58, floorY, LOBBY_CENTER.Z + 12)
		if tableModel then
			local radio = tableModel:FindFirstChild("Radio", true)
			local mainPart: BasePart? = nil
			if radio then
				for _, d in ipairs(radio:GetDescendants()) do
					if d:IsA("BasePart") then mainPart = d; break end
				end
			end
			if not mainPart and tableModel.PrimaryPart then mainPart = tableModel.PrimaryPart end
			if mainPart then
				local PLAYLIST = {
					{name = "Lo-Fi 沉思", id = "rbxassetid://1837879082"},
					{name = "街機躍動", id = "rbxassetid://1843404009"},
					{name = "櫻花竹笛", id = "rbxassetid://9043887091"},
					{name = "木吉他黃昏", id = "rbxassetid://1840683641"},
				}
				local bgm = Instance.new("Sound")
				bgm.Name = "RadioBGM"
				bgm.Volume = 0.65
				bgm.Looped = true
				bgm.RollOffMaxDistance = 85
				bgm.RollOffMinDistance = 12
				bgm.RollOffMode = Enum.RollOffMode.InverseTapered
				bgm.Parent = mainPart

				local bb = Instance.new("BillboardGui")
				bb.Name = "RadioDisplay"
				bb.Size = UDim2.new(0, 150, 0, 48)
				bb.StudsOffset = Vector3.new(0, 2.2, 0)
				bb.AlwaysOnTop = true
				bb.MaxDistance = 45

				local frame = Instance.new("Frame")
				frame.Size = UDim2.new(1, 0, 1, 0)
				frame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
				frame.BackgroundTransparency = 0.25
				frame.BorderSizePixel = 0
				local uic = Instance.new("UICorner"); uic.CornerRadius = UDim.new(0, 8); uic.Parent = frame

				local titleLbl = Instance.new("TextLabel")
				titleLbl.Size = UDim2.new(1, -8, 0, 22); titleLbl.Position = UDim2.new(0, 4, 0, 3)
				titleLbl.BackgroundTransparency = 1; titleLbl.Text = "📻 復古收音機"
				titleLbl.TextColor3 = Color3.fromRGB(255, 215, 100); titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 14; titleLbl.Parent = frame

				local trackLbl = Instance.new("TextLabel")
				trackLbl.Size = UDim2.new(1, -8, 0, 20); trackLbl.Position = UDim2.new(0, 4, 0, 24)
				trackLbl.BackgroundTransparency = 1; trackLbl.Text = "🎶 " .. PLAYLIST[1].name
				trackLbl.TextColor3 = Color3.fromRGB(120, 255, 180); trackLbl.Font = Enum.Font.SourceSans; trackLbl.TextSize = 13; trackLbl.Parent = frame
				frame.Parent = bb; bb.Parent = mainPart

				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "RadioPrompt"
				prompt.ActionText = "切換下一首 ⏭"
				prompt.ObjectText = "復古收音機"
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 14
				prompt.RequiresLineOfSight = false
				prompt.Parent = mainPart

				local currentIdx = 1
				bgm.SoundId = PLAYLIST[1].id
				bgm:Play()

				prompt.Triggered:Connect(function(plr)
					currentIdx = (currentIdx + 1) % (#PLAYLIST + 1)
					if currentIdx == 0 then
						bgm:Stop()
						trackLbl.Text = "⏸ 已靜音（點擊播放）"
						trackLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
						prompt.ActionText = "開啟音樂 🎵"
					else
						local track = PLAYLIST[currentIdx]
						bgm.SoundId = track.id
						bgm:Play()
						trackLbl.Text = "🎶 " .. track.name
						trackLbl.TextColor3 = Color3.fromRGB(120, 255, 180)
						prompt.ActionText = "切換下一首 ⏭"
					end
				end)
			end
		end

		-- 擺放憤怒鳥與豬豬（動態算底部對齊 + 全部面朝中央廣場，生動活潑）
		spawnDecoModel("Chuck the Angry Bird", LOBBY_CENTER.X + 50, floorY, LOBBY_CENTER.Z + 14)
		spawnDecoModel("Matilda", LOBBY_CENTER.X + 64, floorY, LOBBY_CENTER.Z + 16)
		spawnDecoModel("Minion Pig", LOBBY_CENTER.X + 62, floorY, LOBBY_CENTER.Z + 5)

		-- 西側萌鳥漫步區
		spawnDecoModel("Red", LOBBY_CENTER.X - 56, floorY, LOBBY_CENTER.Z + 6)
		spawnDecoModel("The Blues", LOBBY_CENTER.X - 62, floorY, LOBBY_CENTER.Z + 13)
		spawnDecoModel("pig bored", LOBBY_CENTER.X - 52, floorY, LOBBY_CENTER.Z + 10)
		spawnDecoModel("Bomb", LOBBY_CENTER.X - 52, floorY, LOBBY_CENTER.Z - 14)

		-- 南側守護神獸（King Pig 與 Terence 特倫斯巨鳥）
		spawnDecoModel("King Pig", LOBBY_CENTER.X - 26, daisY, LOBBY_CENTER.Z + 48, 0.85)
		spawnDecoModel("Terence", LOBBY_CENTER.X + 26, daisY, LOBBY_CENTER.Z + 48, 0.9)

		-- 東北角排行榜展台
		spawnDecoModel("Leaderboard", LOBBY_CENTER.X + 34, floorY, LOBBY_CENTER.Z - 42)
	end



	-- ------------------------------------------------------------
	-- 1. 大廳隨機刷新金幣（3 枚隨機分佈，拾取 +10 金幣並於 10 秒後重刷）
	-- ------------------------------------------------------------
	
	-- ============================================================
	-- 憤怒鳥棲息地與放置掛機產金農場（Angry Birds Roost Tycoon）
	-- 玩家可抱起大廳憤怒鳥放入專屬鳥巢，小鳥歡快上下浮動，每幾秒自動為主人產出金幣！
	-- ============================================================
	local carriedBirds: {[Player]: Instance} = {}
	local nestOccupants: {[Part]: {bird: Instance, owner: Player, rate: number, interval: number, total: number, name: string}} = {}

	local BIRD_RATES: {[string]: {rate: number, interval: number, name: string}} = {
		["Red"] = {rate = 5, interval = 5, name = "胖紅 (Red)"},
		["The Blues"] = {rate = 6, interval = 4, name = "藍弟弟 (The Blues)"},
		["Chuck the Angry Bird"] = {rate = 8, interval = 4, name = "飛鏢黃 (Chuck)"},
		["Matilda"] = {rate = 10, interval = 4, name = "白姑娘 (Matilda)"},
		["Bomb"] = {rate = 12, interval = 4, name = "炸彈黑 (Bomb)"},
		["Terence"] = {rate = 20, interval = 3, name = "大紅 (Terence)"},
		["King Pig"] = {rate = 30, interval = 3, name = "綠豬王 (King Pig)"},
		["Minion Pig"] = {rate = 4, interval = 5, name = "普通豬豬"},
		["pig bored"] = {rate = 4, interval = 5, name = "無聊豬豬"},
	}

	local function setupAngryBirdsRoost(islandModel: Model)
		local roostFolder = Instance.new("Folder")
		roostFolder.Name = "AngryBirdsRoost"
		roostFolder.Parent = islandModel

		local floorY = LOBBY_CENTER.Y + LY_DECK
		local ROOST_CENTER = Vector3.new(LOBBY_CENTER.X + 46, floorY, LOBBY_CENTER.Z + 32)

		-- 棲息地標牌
		local signPost = Instance.new("Part")
		signPost.Name = "RoostSignPost"
		signPost.Size = Vector3.new(0.8, 7.5, 0.8)
		signPost.Color = Color3.fromRGB(110, 75, 45)
		signPost.Material = Enum.Material.Wood
		signPost.Anchored = true
		signPost.CFrame = CFrame.new(ROOST_CENTER + Vector3.new(0, 3.75, -11))
		signPost.Parent = roostFolder

		local signBoard = Instance.new("Part")
		signBoard.Name = "RoostSignBoard"
		signBoard.Size = Vector3.new(14, 2.8, 0.6)
		signBoard.Color = Color3.fromRGB(135, 90, 50)
		signBoard.Material = Enum.Material.WoodPlanks
		signBoard.Anchored = true
		signBoard.CFrame = signPost.CFrame * CFrame.new(0, 2.2, 0)
		signBoard.Parent = roostFolder

		local signBB = Instance.new("BillboardGui")
		signBB.Name = "SignTitle"
		signBB.Size = UDim2.new(0, 340, 0, 72)
		signBB.StudsOffset = Vector3.new(0, 1.8, 0)
		signBB.AlwaysOnTop = true
		signBB.MaxDistance = 90
		signBB.Adornee = signBoard

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, 0, 0.58, 0)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBlack
		titleLbl.Text = "🐦 憤怒鳥棲息農場 · 放置自刷金幣 💰"
		titleLbl.TextColor3 = Color3.fromRGB(255, 225, 75)
		titleLbl.TextStrokeColor3 = Color3.fromRGB(30, 20, 10)
		titleLbl.TextStrokeTransparency = 0.2
		titleLbl.TextScaled = true
		titleLbl.Parent = signBB

		local subLbl = Instance.new("TextLabel")
		subLbl.Size = UDim2.new(1, 0, 0.42, 0)
		subLbl.Position = UDim2.new(0, 0, 0.58, 0)
		subLbl.BackgroundTransparency = 1
		subLbl.Font = Enum.Font.GothamMedium
		subLbl.Text = "走近抱起大廳小鳥放入鳥巢，離線掛機持續自動刷錢！"
		subLbl.TextColor3 = Color3.fromRGB(220, 255, 230)
		subLbl.TextStrokeColor3 = Color3.fromRGB(30, 20, 10)
		subLbl.TextStrokeTransparency = 0.3
		subLbl.TextScaled = true
		subLbl.Parent = signBB
		signBB.Parent = signBoard

		-- 4 座溫馨木造鳥窩（Nest 1 ~ 4）
		local NEST_OFFSETS = {
			Vector3.new(-7.5, 0, -4),
			Vector3.new(7.5, 0, -4),
			Vector3.new(-7.5, 0, 6.5),
			Vector3.new(7.5, 0, 6.5),
		}

		for idx, off in ipairs(NEST_OFFSETS) do
			local nPos = ROOST_CENTER + off

			-- 窩底托盤
			local nestBase = Instance.new("Part")
			nestBase.Name = "NestBase_" .. idx
			nestBase.Shape = Enum.PartType.Cylinder
			nestBase.Size = Vector3.new(0.6, 5.2, 5.2)
			nestBase.Color = Color3.fromRGB(130, 85, 50)
			nestBase.Material = Enum.Material.WoodPlanks
			nestBase.Anchored = true
			nestBase.CFrame = CFrame.new(nPos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
			nestBase.Parent = roostFolder

			-- 窩草軟墊
			local nestCushion = Instance.new("Part")
			nestCushion.Name = "NestCushion_" .. idx
			nestCushion.Shape = Enum.PartType.Cylinder
			nestCushion.Size = Vector3.new(0.4, 4.4, 4.4)
			nestCushion.Color = Color3.fromRGB(220, 185, 95)
			nestCushion.Material = Enum.Material.Grass
			nestCushion.Anchored = true
			nestCushion.CFrame = CFrame.new(nPos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
			nestCushion.Parent = roostFolder

			-- 柔和光暈
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 215, 120)
			light.Range = 10
			light.Brightness = 0.8
			light.Parent = nestCushion

			-- 3D 浮動資訊面板
			local bb = Instance.new("BillboardGui")
			bb.Name = "NestDisplay"
			bb.Size = UDim2.new(0, 190, 0, 56)
			bb.StudsOffset = Vector3.new(0, 3.2, 0)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 50
			bb.Adornee = nestCushion

			local title = Instance.new("TextLabel")
			title.Name = "Title"
			title.Size = UDim2.new(1, 0, 0.52, 0)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.GothamBlack
			title.Text = "🪺 空閒鳥巢 #" .. idx
			title.TextColor3 = Color3.fromRGB(225, 235, 245)
			title.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
			title.TextStrokeTransparency = 0.3
			title.TextScaled = true
			title.Parent = bb

			local desc = Instance.new("TextLabel")
			desc.Name = "Desc"
			desc.Size = UDim2.new(1, 0, 0.48, 0)
			desc.Position = UDim2.new(0, 0, 0.52, 0)
			desc.BackgroundTransparency = 1
			desc.Font = Enum.Font.GothamMedium
			desc.Text = "💡 抱小鳥放入，開啟自動掛機刷錢！"
			desc.TextColor3 = Color3.fromRGB(255, 215, 100)
			desc.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
			desc.TextStrokeTransparency = 0.4
			desc.TextScaled = true
			desc.Parent = bb
			bb.Parent = nestCushion

			-- 互動提示
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "NestPrompt"
			prompt.ActionText = "派遣小鳥入駐掛機 💤"
			prompt.ObjectText = "鳥巢 #" .. idx
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = nestCushion

			prompt.Triggered:Connect(function(plr)
				local occ = nestOccupants[nestCushion]
				if occ then
					-- 已有小鳥：若是主人或訪客，可抱回小鳥
					local bird = occ.bird
					nestOccupants[nestCushion] = nil
					carriedBirds[plr] = bird

					local ch = plr.Character
					local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
					if hrp and bird then
						if bird:IsA("Model") then
							bird:PivotTo(hrp.CFrame * CFrame.new(0, 2.5, 0))
						elseif bird:IsA("BasePart") then
							bird.CFrame = hrp.CFrame * CFrame.new(0, 2.5, 0)
						end
					end

					title.Text = "🪺 空閒鳥巢 #" .. idx
					title.TextColor3 = Color3.fromRGB(225, 235, 245)
					desc.Text = "💡 抱小鳥放入，開啟自動掛機刷錢！"
					desc.TextColor3 = Color3.fromRGB(255, 215, 100)
					prompt.ActionText = "派遣小鳥入駐掛機 💤"
					prompt.ObjectText = "鳥巢 #" .. idx
					send(plr, "toast", "已抱回小鳥【" .. occ.name .. "】！")
				else
					-- 空巢：檢查玩家是否抱著小鳥
					local bird = carriedBirds[plr]
					if not bird then
						send(plr, "toast", "你手上還沒有小鳥！先走去大廳抱起一隻小鳥吧~")
						return
					end

					carriedBirds[plr] = nil
					local birdName = bird.Name
					local info = BIRD_RATES[birdName] or {rate = 5, interval = 5, name = birdName}

					local roostPos = nPos + Vector3.new(0, 1.2, 0)
					if bird:IsA("Model") then
						bird:PivotTo(CFrame.new(roostPos) * CFrame.Angles(0, math.rad(-90), 0))
					elseif bird:IsA("BasePart") then
						bird.CFrame = CFrame.new(roostPos) * CFrame.Angles(0, math.rad(-90), 0)
					end

					nestOccupants[nestCushion] = {
						bird = bird,
						owner = plr,
						rate = info.rate,
						interval = info.interval,
						total = 0,
						name = info.name,
					}

					title.Text = "🐦 " .. info.name .. " 棲息中"
					title.TextColor3 = Color3.fromRGB(120, 255, 180)
					desc.Text = "💤 +" .. info.rate .. " 金幣 / " .. info.interval .. "秒 (主人: " .. plr.DisplayName .. ")"
					desc.TextColor3 = Color3.fromRGB(255, 225, 80)
					prompt.ActionText = "抱回小鳥 🐦"
					prompt.ObjectText = info.name

					send(plr, "toast", "🎉 成功派遣【" .. info.name .. "】入駐！正在自動刷錢...")
				end
			end)
		end

		-- 小鳥全域掛機產金循環
		task.spawn(function()
			local tickCounter = 0
			while true do
				task.wait(1)
				tickCounter += 1

				for nestPart, occ in pairs(nestOccupants) do
					local owner = occ.owner
					local bird = occ.bird
					if owner and owner.Parent and bird and bird.Parent then
						-- 歡樂浮動呼吸動畫
						local basePos = nestPart.Position + Vector3.new(0, 0.7, 0)
						local bob = math.sin(tickCounter * 2.5) * 0.25
						local curCF = CFrame.new(basePos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, math.rad(-90) + math.sin(tickCounter * 1.5) * 0.15, 0)
						if bird:IsA("Model") then
							bird:PivotTo(curCF)
						elseif bird:IsA("BasePart") then
							bird.CFrame = curCF
						end

						-- 週期產出金幣
						if tickCounter % occ.interval == 0 then
							local od = pd(owner)
							od.coins += occ.rate
							occ.total += occ.rate
							syncLeader(owner)
							send(owner, "coins", od.coins)
							send(owner, "coinpopup", {pos = nestPart.Position + Vector3.new(0, 2.5, 0), amt = occ.rate})

							-- 更新告示板累計產出
							local bb = nestPart:FindFirstChild("NestDisplay") :: BillboardGui?
							if bb then
								local desc = bb:FindFirstChild("Desc") :: TextLabel?
								if desc then
									desc.Text = "💤 +" .. occ.rate .. " 幣/" .. occ.interval .. "s (累計產出: " .. occ.total .. " ¥)"
								end
							end
						end
					else
						-- 主人離開伺服器，保留小鳥在巢穴供其他人認領
						if not (owner and owner.Parent) then
							occ.owner = nil :: any
							local bb = nestPart:FindFirstChild("NestDisplay") :: BillboardGui?
							if bb then
								local desc = bb:FindFirstChild("Desc") :: TextLabel?
								if desc then desc.Text = "💤 小鳥在此休息 (點擊即可認領)" end
							end
						end
					end
				end
			end
		end)

		-- 為大廳全部現存小鳥加上「抱起小鳥」互動提示
		local function hookBirdPrompt(bird: Instance)
			if not (bird:IsA("Model") or bird:IsA("BasePart")) then return end
			local pPart = bird:IsA("Model") and (bird.PrimaryPart or bird:FindFirstChildOfClass("BasePart")) or bird :: BasePart
			if not pPart or pPart:FindFirstChild("BirdPrompt") then return end

			local bp = Instance.new("ProximityPrompt")
			bp.Name = "BirdPrompt"
			bp.ActionText = "抱起小鳥 🐦"
			bp.ObjectText = bird.Name
			bp.HoldDuration = 0
			bp.MaxActivationDistance = 14
			bp.RequiresLineOfSight = false
			bp.Parent = pPart

			bp.Triggered:Connect(function(plr)
				if carriedBirds[plr] then
					send(plr, "toast", "你手上已經抱著一隻小鳥了！先將它放到鳥巢吧~")
					return
				end
				carriedBirds[plr] = bird
				send(plr, "toast", "你抱起了【" .. bird.Name .. "】！快帶去鳥巢掛機產幣吧 🪺")
			end)
		end

		task.delay(1.5, function()
			for _, ch in ipairs(islandModel:GetDescendants()) do
				if BIRD_RATES[ch.Name] then
					hookBirdPrompt(ch)
				end
			end
		end)
	end


local function setupLobbyCoins(islandModel: Model)
		local coinFolder = Instance.new("Folder")
		coinFolder.Name = "LobbyCoins"
		coinFolder.Parent = islandModel

		local SPOTS = {
			Vector3.new(0, 52.4, -26),      -- 北側大門鳥居前
			Vector3.new(38, 52.2, -18),     -- 東側櫻花樹下
			Vector3.new(-38, 52.2, -18),    -- 西側花園長椅邊
			Vector3.new(-48, 52.2, 26),     -- 西南小鳥林蔭道
			Vector3.new(46, 52.2, 26),      -- 東南茶寮前木廊
			Vector3.new(0, 52.6, 36),       -- 南側創作者榮譽壇前
			Vector3.new(-22, 52.0, -10),    -- 西北庭園石燈旁
			Vector3.new(22, 52.0, -10),     -- 東北庭園石燈旁
		}

		local activeCoins = {}

		local function spawnOneCoin(pos: Vector3)
			local coin = Instance.new("Part")
			coin.Name = "LobbyCoin"
			coin.Shape = Enum.PartType.Cylinder
			coin.Size = Vector3.new(0.45, 2.2, 2.2)
			coin.Color = Color3.fromRGB(255, 215, 0)
			coin.Material = Enum.Material.Neon
			coin.Anchored = true
			coin.CanCollide = false
			coin.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))

			local sp = Instance.new("Sparkles")
			sp.SparkleColor = Color3.fromRGB(255, 230, 80)
			sp.Parent = coin

			local bb = Instance.new("BillboardGui")
			bb.Name = "CoinDisplay"
			bb.Size = UDim2.new(0, 80, 0, 36)
			bb.StudsOffset = Vector3.new(0, 1.8, 0)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 60

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = Enum.Font.GothamBold
			lbl.Text = "💰 +10"
			lbl.TextColor3 = Color3.fromRGB(255, 235, 90)
			lbl.TextStrokeColor3 = Color3.fromRGB(30, 20, 0)
			lbl.TextStrokeTransparency = 0.2
			lbl.TextScaled = true
			lbl.Parent = bb
			bb.Parent = coin

			coin.Parent = coinFolder
			activeCoins[coin] = true

			local t0 = os.clock()
			local spinConn
			spinConn = RunService.Heartbeat:Connect(function()
				if not coin.Parent then
					if spinConn then spinConn:Disconnect() end
					return
				end
				local dt = os.clock() - t0
				coin.CFrame = CFrame.new(pos + Vector3.new(0, math.sin(dt * 3) * 0.25, 0))
					* CFrame.Angles(0, dt * 2.5, math.rad(90))
			end)

			local collected = false
			local function tryCollect(hit: Instance)
				if collected or not coin.Parent then return end
				local ch = hit:FindFirstAncestorOfClass("Model")
				local plr = ch and Players:GetPlayerFromCharacter(ch)
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if plr and hum and hum.Health > 0 then
					collected = true
					activeCoins[coin] = nil
					if spinConn then spinConn:Disconnect() end

					local chime = Instance.new("Sound")
					chime.SoundId = "rbxassetid://1872746013"
					chime.Volume = 1.35
					chime.PlaybackSpeed = 1.12 + math.random() * 0.1
					chime.Parent = workspace
					chime:Play()
					game:GetService("Debris"):AddItem(chime, 2.0)

					local d = pd(plr)
					d.coins += 10
					syncLeader(plr)
					send(plr, "coins", d.coins)
					send(plr, "coinpopup", {pos = coin.Position, amt = 10})
					send(plr, "toast", "💰 撿到了大廳幸運金幣！+10 金幣！")

					ballBurst(coin.Position, Color3.fromRGB(255, 215, 0), 1.8)

					-- 撿完立即銷毀實例（0秒延遲徹底消失，絕無殘留判定與火花）
					coin:Destroy()

					-- 隔一段隨機時間（10~15秒）後，在空閒隨機點位重新出現
					task.delay(math.random(10, 15), function()
						local avail = {}
						for _, spot in ipairs(SPOTS) do
							local near = false
							for ac in pairs(activeCoins) do
								if ac.Parent and (ac.Position - spot).Magnitude < 4 then near = true; break end
							end
							if not near then table.insert(avail, spot) end
						end
						if #avail > 0 then
							spawnOneCoin(avail[math.random(1, #avail)])
						end
					end)
				end
			end

			coin.Touched:Connect(tryCollect)

			-- 輔助心跳偵測（防止網路延遲/穿透漏判定）
			task.spawn(function()
				while coin.Parent and not collected do
					task.wait(0.18)
					if collected or not coin.Parent then break end
					for _, p in ipairs(Players:GetPlayers()) do
						local c = p.Character
						local r = c and c:FindFirstChild("HumanoidRootPart")
						if r and (r.Position - pos).Magnitude <= 4.2 then
							tryCollect(r)
							break
						end
					end
				end
			end)
		end

		local shuffled = {}
		for _, s in ipairs(SPOTS) do table.insert(shuffled, s) end
		for i = #shuffled, 2, -1 do
			local j = math.random(1, i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		for i = 1, math.min(3, #shuffled) do
			spawnOneCoin(shuffled[i])
		end
	end

	-- ------------------------------------------------------------
	-- 2. 刺客小茶寮 & 咖啡店（購買飲品，飲用獲得幸運道具）
	-- ------------------------------------------------------------
	local function buildAssassinsCafe(islandModel: Model)
		local cafe = Instance.new("Model")
		cafe.Name = "AssassinsCafe"

		local floorY = LOBBY_CENTER.Y + LY_DECK
		local cf = CFrame.new(LOBBY_CENTER.X + 44, floorY, LOBBY_CENTER.Z + 38) * CFrame.Angles(0, math.rad(-135), 0)

		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10.5, 3.4, 2.6)
		counter.Color = Color3.fromRGB(72, 45, 30)
		counter.Material = Enum.Material.WoodPlanks
		counter.Anchored = true; counter.CanCollide = true
		counter.CFrame = cf * CFrame.new(0, 1.7, 0)
		counter.Parent = cafe

		local counterTop = Instance.new("Part")
		counterTop.Name = "CounterTop"
		counterTop.Size = Vector3.new(11.2, 0.45, 3.2)
		counterTop.Color = Color3.fromRGB(235, 230, 220)
		counterTop.Material = Enum.Material.Marble
		counterTop.Anchored = true; counterTop.CanCollide = true
		counterTop.CFrame = cf * CFrame.new(0, 3.5, 0)
		counterTop.Parent = cafe

		local awning = Instance.new("Part")
		awning.Name = "Awning"
		awning.Size = Vector3.new(12.0, 0.4, 6.0)
		awning.Color = Color3.fromRGB(150, 28, 28)
		awning.Material = Enum.Material.SmoothPlastic
		awning.Anchored = true; awning.CanCollide = true
		awning.CFrame = cf * CFrame.new(0, 7.2, 0.8) * CFrame.Angles(math.rad(10), 0, 0)
		awning.Parent = cafe

		for _, xOff in ipairs({-5.2, 5.2}) do
			for _, zOff in ipairs({-1.2, 1.2}) do
				local post = Instance.new("Part")
				post.Name = "Pillar"
				post.Size = Vector3.new(0.5, 7.2, 0.5)
				post.Color = Color3.fromRGB(55, 35, 22)
				post.Material = Enum.Material.Wood
				post.Anchored = true; post.CanCollide = true
				post.CFrame = cf * CFrame.new(xOff, 3.6, zOff)
				post.Parent = cafe
			end
		end

		for _, xOff in ipairs({-2.6, 2.6}) do
			local stool = Instance.new("Part")
			stool.Name = "BarStool"
			stool.Shape = Enum.PartType.Cylinder
			stool.Size = Vector3.new(1.8, 1.6, 1.6)
			stool.Color = Color3.fromRGB(90, 56, 38)
			stool.Material = Enum.Material.Wood
			stool.Anchored = true; stool.CanCollide = true
			stool.CFrame = cf * CFrame.new(xOff, 0.9, 2.8) * CFrame.Angles(0, 0, math.rad(90))
			stool.Parent = cafe

			local stSeat = Instance.new("Seat")
			stSeat.Name = "Seat"
			stSeat.Size = Vector3.new(1.6, 0.2, 1.6)
			stSeat.Transparency = 1; stSeat.Anchored = true; stSeat.CanCollide = false
			stSeat.CFrame = cf * CFrame.new(xOff, 1.9, 2.8)
			stSeat.Parent = cafe
		end

		local cup = Instance.new("Part")
		cup.Name = "CoffeeCup"
		cup.Shape = Enum.PartType.Cylinder
		cup.Size = Vector3.new(0.8, 0.7, 0.7)
		cup.Color = Color3.fromRGB(240, 240, 245)
		cup.Material = Enum.Material.SmoothPlastic
		cup.Anchored = true; cup.CanCollide = false
		cup.CFrame = cf * CFrame.new(1.8, 4.0, 0) * CFrame.Angles(0, 0, math.rad(90))
		cup.Parent = cafe

		local steam = Instance.new("ParticleEmitter")
		steam.Name = "Steam"
		steam.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
		steam.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.2)})
		steam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1)})
		steam.Lifetime = NumberRange.new(0.8, 1.5)
		steam.Speed = NumberRange.new(0.8, 1.6)
		steam.Rate = 6
		steam.SpreadAngle = Vector2.new(15, 15)
		steam.Acceleration = Vector3.new(0, 1.2, 0)
		steam.Parent = cup

		local signBoard = Instance.new("Part")
		signBoard.Name = "SignBoard"
		signBoard.Size = Vector3.new(7.0, 1.4, 0.3)
		signBoard.Color = Color3.fromRGB(35, 25, 20)
		signBoard.Material = Enum.Material.WoodPlanks
		signBoard.Anchored = true; signBoard.CanCollide = false
		signBoard.CFrame = cf * CFrame.new(0, 6.4, 1.4)
		signBoard.Parent = cafe

		local signBb = Instance.new("BillboardGui")
		signBb.Name = "SignGui"
		signBb.Size = UDim2.new(0, 240, 0, 64)
		signBb.StudsOffset = Vector3.new(0, 0.5, 0.3)
		signBb.AlwaysOnTop = true
		signBb.MaxDistance = 55
		signBb.Adornee = signBoard

		local signLbl = Instance.new("TextLabel")
		signLbl.Size = UDim2.new(1, 0, 0.55, 0)
		signLbl.BackgroundTransparency = 1
		signLbl.Font = Enum.Font.GothamBlack
		signLbl.Text = "🍵 刺客茶寮 · Assassin's Café ☕"
		signLbl.TextColor3 = Color3.fromRGB(255, 220, 100)
		signLbl.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
		signLbl.TextStrokeTransparency = 0.2
		signLbl.TextScaled = true
		signLbl.Parent = signBb

		local signSub = Instance.new("TextLabel")
		signSub.Size = UDim2.new(1, 0, 0.45, 0)
		signSub.Position = UDim2.new(0, 0, 0.55, 0)
		signSub.BackgroundTransparency = 1
		signSub.Font = Enum.Font.GothamMedium
		signSub.Text = "特調飲品 50 金幣 | 飲用送幸運箱神秘道具"
		signSub.TextColor3 = Color3.fromRGB(200, 245, 255)
		signSub.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
		signSub.TextStrokeTransparency = 0.3
		signSub.TextScaled = true
		signSub.Parent = signBb
		signBb.Parent = signBoard

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "購買刺客特調飲品 (50 金幣)"
		prompt.ObjectText = "🍵 刺客茶寮"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 10
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.Parent = counterTop

		local function giveDrinkTool(plr: Player)
			local bp = plr:FindFirstChild("Backpack")
			if not bp then return end

			local FLAVORS = {
				{name = "🍵 刺客特調抹茶", color = Color3.fromRGB(110, 195, 100)},
				{name = "☕ 暗影濃縮咖啡", color = Color3.fromRGB(105, 65, 45)},
				{name = "🧋 幻影黑糖奶茶", color = Color3.fromRGB(205, 150, 105)},
			}
			local flv = FLAVORS[math.random(1, #FLAVORS)]

			local tool = Instance.new("Tool")
			tool.Name = flv.name
			tool.RequiresHandle = true
			tool.CanBeDropped = false

			local h = Instance.new("Part")
			h.Name = "Handle"
			h.Shape = Enum.PartType.Cylinder
			h.Size = Vector3.new(0.9, 0.65, 0.65)
			h.Color = flv.color
			h.Material = Enum.Material.SmoothPlastic
			h.CFrame = CFrame.Angles(0, 0, math.rad(90))
			h.Parent = tool

			local sp = Instance.new("Sparkles")
			sp.SparkleColor = flv.color
			sp.Parent = h

			local drank = false
			tool.Activated:Connect(function()
				if drank then return end
				drank = true

				local ch = plr.Character
				local hum = ch and ch:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + 25)
				end

				local drinkSnd = Instance.new("Sound")
				drinkSnd.SoundId = "rbxassetid://303102434"
				drinkSnd.Volume = 1.3
				drinkSnd.Parent = h
				drinkSnd:Play()

				if ch and ch:FindFirstChild("Head") then
					local burst = Instance.new("ParticleEmitter")
					burst.Color = ColorSequence.new(Color3.fromRGB(255, 140, 180), Color3.fromRGB(255, 230, 120))
					burst.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)})
					burst.Lifetime = NumberRange.new(0.6, 1.2)
					burst.Speed = NumberRange.new(3, 7)
					burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					burst.Parent = ch.Head
					burst:Emit(25)
					game:GetService("Debris"):AddItem(burst, 1.5)
				end

				local d = pd(plr)
				if #d.items < 2 then
					local it = ITEMS[math.random(1, #ITEMS)]
					table.insert(d.items, it.id)
					send(plr, "itemget", {id = it.id, name = it.name, desc = it.desc, color = it.color, items = d.items})
					send(plr, "toast", "✨ 喝完特調神清氣爽！獲得幸運道具【" .. it.name .. "】！")
				else
					d.coins += 40
					syncLeader(plr)
					send(plr, "coins", d.coins)
					send(plr, "toast", "✨ 喝完特調！道具欄已滿，特調化作 40 金幣返還！")
				end

				task.delay(0.4, function()
					if tool.Parent then tool:Destroy() end
				end)
			end)

			tool.Parent = bp
		end

		prompt.Triggered:Connect(function(plr)
			local d = pd(plr)
			if d.coins < 50 then
				send(plr, "toast", "❌ 金幣不足！特調飲品需要 50 金幣（大廳隨處可撿金幣哦）")
				return
			end
			d.coins -= 50
			syncLeader(plr)
			send(plr, "coins", d.coins)
			giveDrinkTool(plr)
			send(plr, "toast", "🍵 購買成功！飲品已放入背包，點擊飲用可獲戰鬥神技道具！")
		end)

		cafe.Parent = islandModel
		return cafe
	end

	-- ------------------------------------------------------------
	-- 3. 練刀木人樁（大廳互動：揮砍彈簧晃動、爆火花與傷害飄字）
	-- ------------------------------------------------------------
	local function buildTrainingDummy(islandModel: Model)
		local dummy = Instance.new("Model")
		dummy.Name = "TrainingDummy"

		local floorY = LOBBY_CENTER.Y + LY_DECK
		local cf = CFrame.new(LOBBY_CENTER.X - 38, floorY, LOBBY_CENTER.Z - 36) * CFrame.Angles(0, math.rad(45), 0)

		local base = Instance.new("Part")
		base.Name = "DummyBase"
		base.Shape = Enum.PartType.Cylinder
		base.Size = Vector3.new(0.6, 4.2, 4.2)
		base.Color = Color3.fromRGB(48, 50, 56)
		base.Material = Enum.Material.Slate
		base.Anchored = true; base.CanCollide = true
		base.CFrame = cf * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
		base.Parent = dummy

		local torso = Instance.new("Part")
		torso.Name = "Torso"
		torso.Shape = Enum.PartType.Cylinder
		torso.Size = Vector3.new(4.2, 2.2, 2.2)
		torso.Color = Color3.fromRGB(165, 115, 75)
		torso.Material = Enum.Material.Wood
		torso.Anchored = true; torso.CanCollide = true
		torso.CFrame = cf * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, 0, math.rad(90))
		torso.Parent = dummy
		dummy.PrimaryPart = torso
		dummy:SetAttribute("OrigCF", torso.CFrame)

		local arm = Instance.new("Part")
		arm.Name = "DummyArms"
		arm.Size = Vector3.new(4.6, 0.45, 0.45)
		arm.Color = Color3.fromRGB(140, 95, 60)
		arm.Material = Enum.Material.Wood
		arm.Anchored = false; arm.CanCollide = true
		arm.CFrame = cf * CFrame.new(0, 3.4, 0)
		local armWeld = Instance.new("WeldConstraint")
		armWeld.Part0 = torso; armWeld.Part1 = arm; armWeld.Parent = torso
		arm.Parent = dummy

		local head = Instance.new("Part")
		head.Name = "DummyHead"
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(1.8, 1.8, 1.8)
		head.Color = Color3.fromRGB(180, 130, 85)
		head.Material = Enum.Material.Wood
		head.Anchored = false; head.CanCollide = true
		head.CFrame = cf * CFrame.new(0, 5.2, 0)
		local headWeld = Instance.new("WeldConstraint")
		headWeld.Part0 = torso; headWeld.Part1 = head; headWeld.Parent = torso
		head.Parent = dummy

		local hat = Instance.new("Part")
		hat.Name = "StrawHat"
		hat.Size = Vector3.new(3.4, 0.4, 3.4)
		hat.Color = Color3.fromRGB(220, 190, 120)
		hat.Material = Enum.Material.Fabric
		hat.Anchored = false; hat.CanCollide = false
		hat.CFrame = cf * CFrame.new(0, 6.0, 0)
		local hatWeld = Instance.new("WeldConstraint")
		hatWeld.Part0 = torso; hatWeld.Part1 = hat; hatWeld.Parent = torso
		hat.Parent = dummy

		local bb = Instance.new("BillboardGui")
		bb.Name = "TargetDisplay"
		bb.Size = UDim2.new(0, 150, 0, 48)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 50
		bb.Adornee = head

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0.6, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBlack
		lbl.Text = "🎯 練刀木人樁"
		lbl.TextColor3 = Color3.fromRGB(255, 215, 60)
		lbl.TextStrokeColor3 = Color3.fromRGB(25, 20, 10)
		lbl.TextStrokeTransparency = 0.2
		lbl.TextScaled = true
		lbl.Parent = bb

		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0.4, 0)
		sub.Position = UDim2.new(0, 0, 0.6, 0)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamMedium
		sub.Text = "砍我試試手感！連斬手感極爽"
		sub.TextColor3 = Color3.fromRGB(225, 245, 255)
		sub.TextStrokeColor3 = Color3.fromRGB(25, 20, 10)
		sub.TextStrokeTransparency = 0.3
		sub.TextScaled = true
		sub.Parent = bb
		bb.Parent = head

		dummy.Parent = islandModel
		return dummy
	end

	-- 呼叫大廳新活動元件
	setupLobbyCoins(island)
	setupAngryBirdsRoost(island)
	buildAssassinsCafe(island)
	buildTrainingDummy(island)

	island.Parent = workspace
	return {shopPrompt = shopPrompt, gachaPrompt = gachaPrompt}
end

local lobbyRefs = buildLobby()

-- ------------------------------------------------------------
-- 地圖選擇板（大廳：每輪從 15 張隨機抽 3 張，站上去 = 投那一張）
-- ------------------------------------------------------------
local ARENA_CENTER = Vector3.new(0, 0, -600)
local ARENA_R = 62
local mapCandidates: {number} = {}   -- 本輪開放投票的 3 張地圖編號
local mapPads: {{pad: Part, sign: TextLabel, idx: number, preview: Model?}} = {}

-- 迷你地圖預覽：照 buildArena 的形狀邏輯等比縮小，浮在板子上方當「預覽圖」
local PREVIEW_S = 0.09
local function buildMiniMap(mapIdx: number, center: Vector3): Model
	local map = MAPS[mapIdx]
	local shape: number = map.shape
	local floorDef: any = FLOORS[map.floor]
	local s = PREVIEW_S

	local m = Instance.new("Model")
	m.Name = "MapPreview"

	local function pp(props: {[string]: any})
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CastShadow = false
		for k, v in pairs(props) do (p :: any)[k] = v end
		p.Parent = m
		return p
	end

	local function apotheim(): number
		if shape == 1 then return ARENA_R end
		if shape == 5 then return ARENA_R * 0.42 end
		local n = (shape == 2 and 4) or (shape == 3 and 3) or 5
		return ARENA_R * math.cos(math.pi / n)
	end
	local aIn = apotheim()

	-- 核心地板
	pp({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, aIn * 2 * s, aIn * 2 * s),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = floorDef.color, Material = floorDef.material})

	-- 多邊形邊帶 / 星星手臂＋霓虹外框
	local edgeDefs: {{number}} = {}
	if shape == 2 or shape == 3 or shape == 4 then
		local n = (shape == 2 and 4) or (shape == 3 and 3) or 5
		local edgeLen = 2 * ARENA_R * math.sin(math.pi / n)
		for k = 0, n - 1 do
			table.insert(edgeDefs, {math.rad(k * (360 / n) + 180 / n), edgeLen, aIn})
		end
	elseif shape == 5 then
		for k = 0, 4 do
			table.insert(edgeDefs, {math.rad(k * 72), aIn * 0.9, aIn})
		end
	end
	for _, e in ipairs(edgeDefs) do
		local midAng, edgeLen, innerR = e[1], e[2], e[3]
		local bandLen = ARENA_R - innerR + 3
		local dir = Vector3.new(math.cos(midAng), 0, math.sin(midAng))
		local pos = center + dir * ((innerR + bandLen / 2 - 1.5) * s)
		pp({Size = Vector3.new(edgeLen * s, 0.6, bandLen * s),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Color = floorDef.color, Material = floorDef.material})
		local npos = center + dir * (ARENA_R + 1) * s
		pp({Size = Vector3.new(edgeLen * s, 0.25, 2.4 * s),
			CFrame = CFrame.lookAt(npos, npos + dir),
			Color = Color3.fromRGB(120, 190, 255), Material = Enum.Material.Neon})
	end
	-- 圓形的霓虹外圈
	if shape == 1 then
		pp({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, ARENA_R * 2 * s + 0.5, ARENA_R * 2 * s + 0.5),
			CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 190, 255), Material = Enum.Material.Neon})
	end
	-- 示範障礙物（典雅白大理石柱與石台）
	for i = 1, 4 do
		local ang = math.rad(i * 90 + math.random(-20, 20))
		local rr = aIn * 0.75 * s * (0.3 + math.random() * 0.7)
		pp({Size = Vector3.new(0.8, 0.6 + math.random() * 0.6, 0.8),
			Position = center + Vector3.new(math.cos(ang) * rr, 0.5, math.sin(ang) * rr),
			Color = Color3.fromRGB(220, 225, 235), Material = Enum.Material.Marble})
	end
	m.Parent = workspace
	return m
end

local boardC = LOBBY_CENTER + Vector3.new(0, 0, -38)
local padY = LOBBY_CENTER.Y + 0.45
local PAD_COLORS = {
	Color3.fromRGB(0, 225, 255),   -- 地圖 1：賽博霓虹青藍
	Color3.fromRGB(255, 215, 60),  -- 地圖 2：帝皇金芒
	Color3.fromRGB(235, 65, 225),  -- 地圖 3：霓虹紫紅
}
local mapFloatingBillboards: {BillboardGui} = {}

local function buildMapBoard()
	-- 木框平台
	part({Size = Vector3.new(62, 0.4, 34), Position = boardC + Vector3.new(0, 1.2, 0),
		Color = Color3.fromRGB(72, 48, 36), Material = Enum.Material.WoodPlanks})
	part({Size = Vector3.new(64, 1.2, 36), Position = boardC + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(45, 48, 56), Material = Enum.Material.Slate})

	-- 標題告示牌
	local sign = part({Size = Vector3.new(34, 3.8, 0.6), Position = boardC + Vector3.new(0, 5.4, -16.2),
		Color = Color3.fromRGB(36, 38, 46), Material = Enum.Material.Slate})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(700, 100); sg.Parent = sign
	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
	st.Text = "🗺️ 地圖投票：請踩入對應光柱進行投票 🗺️"
	st.TextColor3 = Color3.fromRGB(255, 230, 120); st.TextScaled = true
	st.Font = Enum.Font.GothamBold; st.Parent = sg

	-- 3 塊投票板（極顯眼立體光柱 + 3D 浮空投票標題 + 票數）
	for k = 1, 3 do
		local px = -18 + (k - 1) * 18
		local padCol = PAD_COLORS[k] or Color3.fromRGB(255, 255, 255)
		local pad = part({Size = Vector3.new(13, 0.4, 11),
			Position = Vector3.new(boardC.X + px, padY, boardC.Z + 3),
			Color = Color3.fromRGB(35, 38, 46), Material = Enum.Material.Slate})

		-- 霓虹外發光邊框
		part({Size = Vector3.new(13.8, 0.25, 11.8),
			Position = Vector3.new(boardC.X + px, padY - 0.1, boardC.Z + 3),
			Color = padCol, Material = Enum.Material.Neon, CanCollide = false})

		-- 沖天發光圓柱光柱（Light Pillar Beacon）
		local beacon = Instance.new("Part")
		beacon.Name = "VoteBeacon"
		beacon.Shape = Enum.PartType.Cylinder
		beacon.Size = Vector3.new(18, 10, 10)
		beacon.CFrame = CFrame.new(Vector3.new(boardC.X + px, padY + 9, boardC.Z + 3)) * CFrame.Angles(0, 0, math.rad(90))
		beacon.Color = padCol
		beacon.Material = Enum.Material.Neon
		beacon.Transparency = 0.76
		beacon.CanCollide = false
		beacon.Anchored = true
		beacon.Parent = pad

		local bLight = Instance.new("PointLight")
		bLight.Color = padCol
		bLight.Brightness = 1.6
		bLight.Range = 16
		bLight.Parent = beacon

		-- 地面投票文字 SurfaceGui
		local floorSg = Instance.new("SurfaceGui")
		floorSg.Face = Enum.NormalId.Top
		floorSg.CanvasSize = Vector2.new(400, 300)
		floorSg.Parent = pad
		local flTxt = Instance.new("TextLabel")
		flTxt.Size = UDim2.new(1, 0, 1, 0)
		flTxt.BackgroundTransparency = 1
		flTxt.Font = Enum.Font.GothamBold
		flTxt.Text = "★ 站此處投票 ★\n[ 踩入光柱 ]"
		flTxt.TextColor3 = padCol
		flTxt.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
		flTxt.TextStrokeTransparency = 0.2
		flTxt.TextScaled = true
		flTxt.Parent = floorSg

		-- 立體 3D 浮空告示看板（高掛於預覽地圖上方，無論從大廳何處均極為清晰！）
		local bb = Instance.new("BillboardGui")
		bb.Name = "VoteDisplayBB"
		bb.Size = UDim2.new(0, 240, 0, 80)
		bb.StudsOffset = Vector3.new(0, 9.8, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.Parent = pad

		local bbBox = Instance.new("Frame")
		bbBox.Size = UDim2.new(1, 0, 1, 0)
		bbBox.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
		bbBox.BackgroundTransparency = 0.25
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 10)
		bc.Parent = bbBox
		local bs = Instance.new("UIStroke")
		bs.Color = padCol
		bs.Thickness = 2
		bs.Parent = bbBox
		bbBox.Parent = bb

		local titleLbl = Instance.new("TextLabel")
		titleLbl.Size = UDim2.new(1, -8, 0.45, 0)
		titleLbl.Position = UDim2.new(0, 4, 0, 2)
		titleLbl.BackgroundTransparency = 1
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.TextColor3 = padCol
		titleLbl.TextStrokeTransparency = 0.3
		titleLbl.TextScaled = true
		titleLbl.Text = "地圖投票"
		titleLbl.Parent = bbBox

		local voteLbl = Instance.new("TextLabel")
		voteLbl.Size = UDim2.new(1, -8, 0.50, 0)
		voteLbl.Position = UDim2.new(0, 4, 0.45, 0)
		voteLbl.BackgroundTransparency = 1
		voteLbl.Font = Enum.Font.GothamBlack
		voteLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		voteLbl.TextStrokeTransparency = 0.2
		voteLbl.TextScaled = true
		voteLbl.Text = "👤 0 票"
		voteLbl.Parent = bbBox

		table.insert(mapFloatingBillboards, bb)

		-- 後方告示板
		local sp = part({Size = Vector3.new(13, 3.2, 0.5),
			Position = Vector3.new(boardC.X + px, padY + 2.1, boardC.Z + 3 - 6.2),
			Color = Color3.fromRGB(35, 38, 48), Material = Enum.Material.SmoothPlastic})
		local pg = Instance.new("SurfaceGui")
		pg.Face = Enum.NormalId.Back; pg.CanvasSize = Vector2.new(480, 130); pg.Parent = sp
		local lb = Instance.new("TextLabel")
		lb.Size = UDim2.new(1, -8, 1, -8); lb.Position = UDim2.new(0, 4, 0, 4)
		lb.BackgroundColor3 = Color3.fromRGB(20, 22, 28); lb.BackgroundTransparency = 0.15
		lb.TextColor3 = Color3.new(1, 1, 1); lb.TextScaled = true
		lb.Font = Enum.Font.GothamBold
		lb.Text = ""
		lb.Parent = pg
		table.insert(mapPads, {pad = pad, sign = lb, idx = -1, preview = nil :: any, bbTitle = titleLbl, bbVote = voteLbl})
	end
end

buildMapBoard()

-- 換一組候選地圖（3 張不重複）＋重建預覽
local function pickCandidates()
	local pool: {number} = {}
	for i = 1, #MAPS do table.insert(pool, i) end
	for i = #pool, 2, -1 do
		local j = math.random(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	mapCandidates = {pool[1], pool[2], pool[3]}
	table.clear(votes)
	for k = 1, 3 do
		local mp = mapPads[k]
		if mp.preview then mp.preview:Destroy(); mp.preview = nil end
		mp.idx = mapCandidates[k]
		mp.preview = buildMiniMap(mp.idx, Vector3.new(mp.pad.Position.X, padY + 6.2, mp.pad.Position.Z))
		mp.sign.Text = MAPS[mp.idx].name .. "\n👤 0"
		mp.sign.TextColor3 = Color3.new(1, 1, 1)
		mp.sign.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
		if mp.bbTitle then mp.bbTitle.Text = "【 " .. MAPS[mp.idx].name .. " 】" end
		if mp.bbVote then mp.bbVote.Text = "👤 0 票" end
	end
end

pickCandidates()

-- 預覽慢慢旋轉（全息投影感）
task.spawn(function()
	while true do
		local dt = task.wait(0.05)
		for _, mp in ipairs(mapPads) do
			if mp.preview and mp.preview.Parent then
				mp.preview:PivotTo(mp.preview:GetPivot() * CFrame.Angles(0, dt * 0.5, 0))
			end
		end
	end
end)

-- 站上哪塊板就投那張地圖（每 0.25 秒偵測一次，精準判定半徑覆蓋整個光圈光柱）
task.spawn(function()
	while true do
		task.wait(0.25)
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if hrp and math.abs(hrp.Position.Y - padY) < 7.5 then
				for _, mp in ipairs(mapPads) do
					if mp.idx >= 1 then
						local p = mp.pad.Position
						local d2D = Vector2.new(hrp.Position.X - p.X, hrp.Position.Z - p.Z).Magnitude
						if d2D <= 7.2 then
							if votes[plr] ~= mp.idx then
								votes[plr] = mp.idx
								send(plr, "toast", "🗳️ 已為 【" .. MAPS[mp.idx].name .. "】 投出一票！")
								local chime = Instance.new("Sound")
								chime.SoundId = "rbxassetid://1872746013"
								chime.Volume = 1.1
								chime.Parent = mp.pad
								chime:Play()
								game:GetService("Debris"):AddItem(chime, 1.5)
							end
							break
						end
					end
				end
			end
		end
	end
end)

-- 告示牌票數顯示（每秒更新，最多票的金色）
task.spawn(function()
	while true do
		task.wait(1)
		local tally: {[number]: number} = {}
		local bestN = 0
		for plr, idx in pairs(votes) do
			if plr.Parent and table.find(mapCandidates, idx) then
				tally[idx] = (tally[idx] or 0) + 1
				if tally[idx] > bestN then bestN = tally[idx] end
			end
		end
		for _, mp in ipairs(mapPads) do
			if mp.idx >= 1 then
				local n = tally[mp.idx] or 0
				mp.sign.Text = MAPS[mp.idx].name .. "\n👤 " .. n
				if mp.bbVote then
					mp.bbVote.Text = "👤 " .. n .. " 票"
					if bestN > 0 and n == bestN then
						mp.bbVote.TextColor3 = Color3.fromRGB(255, 220, 80)
					else
						mp.bbVote.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
				if bestN > 0 and n == bestN then
					mp.sign.TextColor3 = Color3.fromRGB(255, 215, 90)
					mp.sign.BackgroundColor3 = Color3.fromRGB(70, 55, 15)
				elseif n > 0 then
					mp.sign.TextColor3 = Color3.fromRGB(160, 255, 170)
					mp.sign.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
				else
					mp.sign.TextColor3 = Color3.new(1, 1, 1)
					mp.sign.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- 競技場（圓形浮空躲避球場）
-- ------------------------------------------------------------
local arenaBlocks: {{c: Vector3, half: number, top: number}} = {}   -- 本回合紅色方塊（給神秘盒子避讓用）

local function buildArena(mapIdx: number)
	local map = MAPS[mapIdx]
	local shape: number = map.shape
	local floorDef: any = FLOORS[map.floor]

	if workspace:FindFirstChild("Arena") then
		workspace.Arena:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"

	local iceProps = PhysicalProperties.new(0.7, floorDef.friction, 0.3, 10, 1)
	local floorProps = (floorDef.friction < 0.1) and iceProps or nil
	local floorY = -1   -- 地板中心 y（厚 2，表面 y=0）

	-- 內切圓半徑（地板核心圓柱用）
	local function apotheim(): number
		if shape == 1 then return ARENA_R end
		if shape == 5 then return ARENA_R * 0.42 end       -- 星星：核心較小
		local n = (shape == 2 and 4) or (shape == 3 and 3) or 5
		return ARENA_R * math.cos(math.pi / n)
	end
	local aIn = apotheim()

	-- 核心地板（圓柱）
	part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, aIn * 2, aIn * 2),
		CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, floorY, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = floorDef.color, Material = floorDef.material, CustomPhysicalProperties = floorProps}, arena)

	-- 多邊形：內切圓 + 每條邊一片「邊帶」地板 → 拼出完整多邊形輪廓；星星：5 隻手臂
	local edgeDefs: {{number}} = {}   -- {midAngle, edgeLen, innerR}
	if shape == 2 or shape == 3 or shape == 4 then
		local n = (shape == 2 and 4) or (shape == 3 and 3) or 5
		local edgeLen = 2 * ARENA_R * math.sin(math.pi / n)
		for k = 0, n - 1 do
			table.insert(edgeDefs, {math.rad(k * (360 / n) + 180 / n), edgeLen, aIn})
		end
	elseif shape == 5 then
		for k = 0, 4 do
			table.insert(edgeDefs, {math.rad(k * 72), aIn * 0.9, aIn})
		end
	end

	for si, e in ipairs(edgeDefs) do
		local midAng, edgeLen, innerR = e[1], e[2], e[3]
		local dir = Vector3.new(math.cos(midAng), 0, math.sin(midAng))
		if shape == 5 then
			-- 星星手臂（手臂之間的縫隙本來就是造型）
			local bandLen = ARENA_R - innerR + 3
			local pos = ARENA_CENTER + dir * (innerR + bandLen / 2 - 1.5) + Vector3.new(0, floorY, 0)
			part({Size = Vector3.new(edgeLen, 2, bandLen),
				CFrame = CFrame.lookAt(pos, pos + dir),
				Color = floorDef.color, Material = floorDef.material, CustomPhysicalProperties = floorProps}, arena)
		else
			-- 多邊形：N 片「從圓心到邊」的整片地板（寬度＝邊長），剛好拼滿整個多邊形，角落不再破洞
			-- 相鄰地磚在中央區域會重疊，Y 交錯 2 公分避免閃面
			local yOff = (si % 2 == 0) and -0.02 or -0.04
			local pos = ARENA_CENTER + dir * (aIn / 2) + Vector3.new(0, floorY + yOff, 0)
			part({Size = Vector3.new(edgeLen, 2, aIn),
				CFrame = CFrame.lookAt(pos, pos + dir),
				Color = floorDef.color, Material = floorDef.material, CustomPhysicalProperties = floorProps}, arena)
		end
		-- 橘色霓虹邊條（沉在地板下只露一線）
		local npos = ARENA_CENTER + dir * (ARENA_R + 1) + Vector3.new(0, -0.55, 0)
		part({Size = Vector3.new(edgeLen, 0.4, 2.4),
			CFrame = CFrame.lookAt(npos, npos + dir),
			Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon, CanCollide = false}, arena)
	end

	-- 圓形霓虹外圈
	if shape == 1 then
		part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, ARENA_R * 2 + 3, ARENA_R * 2 + 3),
			CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, -0.55, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon}, arena)
	end

	-- 底座岩
	local rockR = math.max(aIn * 0.9, ARENA_R * 0.5)
	part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, rockR * 2, rockR * 2),
		CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, -9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(60, 45, 55), Material = Enum.Material.Slate}, arena)

	-- 內圈橘線＋場中央道具生成標記
	part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 22, 22),
		CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon, CanCollide = false}, arena)
	part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 10, 10),
		CFrame = CFrame.new(ARENA_CENTER + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 220, 100), Material = Enum.Material.Neon, CanCollide = false}, arena)

	-- 典雅競技場障礙物（參差不齊：大理石古遺跡神柱、水晶方尖碑、戰術石階，完全取代醜陋紅方塊）
	local blockR = aIn * 0.92
	local minGap = math.max(8.0, math.sqrt(blockR * blockR * math.pi / 18) * 0.90)
	arenaBlocks = {}
	local placed: {Vector3} = {}
	local attempts = 0
	while #placed < 18 and attempts < 600 do
		attempts += 1
		local ang = math.rad(math.random() * 360)
		local rr = blockR * (0.16 + math.random() * 0.84)
		if rr < 11 then rr = 11 + math.random() * 4 end   -- 避開中央出生區
		local pos = Vector3.new(math.cos(ang) * rr, 0, math.sin(ang) * rr)
		local ok = true
		for _, q in ipairs(placed) do
			if (q - pos).Magnitude < minGap then ok = false break end
		end
		if ok then
			table.insert(placed, pos)
			local style = #placed % 3
			local tier = (#placed - 1) % 4
			local h = 3.2 + tier * 2.2 + math.random() * 1.5   -- 高度參差不齊：3.2 ~ 11.3 格

			if style == 0 then
				-- 款式 1：古希臘大理石雕花圓柱（圓柱主體 + 上下底座）
				local rad = 2.4 + math.random() * 1.0
				local col = part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, rad * 2, rad * 2),
					CFrame = CFrame.new(ARENA_CENTER + pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(235, 238, 245), Material = Enum.Material.Marble}, arena)
				part({Size = Vector3.new(rad * 2.4, 0.8, rad * 2.4),
					Position = ARENA_CENTER + pos + Vector3.new(0, h + 0.4, 0),
					Color = Color3.fromRGB(215, 218, 225), Material = Enum.Material.Marble}, arena)
				table.insert(arenaBlocks, {c = ARENA_CENTER + pos, half = rad + 0.5, top = h + 0.8})

			elseif style == 1 then
				-- 款式 2：黑曜石賽博霓虹水晶方尖碑
				local w = 4.5 + math.random() * 2.0
				local obs = part({Size = Vector3.new(w, h, w),
					Position = ARENA_CENTER + pos + Vector3.new(0, h / 2, 0),
					Color = Color3.fromRGB(35, 32, 42), Material = Enum.Material.Basalt}, arena)
				-- 頂部發光能量晶核
				local core = part({Size = Vector3.new(w * 0.8, 1.2, w * 0.8),
					Position = ARENA_CENTER + pos + Vector3.new(0, h + 0.6, 0),
					Color = Color3.fromRGB(60, 190, 255), Material = Enum.Material.Neon}, arena)
				table.insert(arenaBlocks, {c = ARENA_CENTER + pos, half = w / 2, top = h + 1.2})

			else
				-- 款式 3：雙層戰術石階踏板（可跳躍攀爬戰術掩體）
				local w = 7.0 + math.random() * 2.5
				part({Size = Vector3.new(w, h * 0.55, w),
					Position = ARENA_CENTER + pos + Vector3.new(0, (h * 0.55) / 2, 0),
					Color = Color3.fromRGB(90, 75, 70), Material = Enum.Material.Cobblestone}, arena)
				part({Size = Vector3.new(w * 0.6, h * 0.45, w * 0.6),
					Position = ARENA_CENTER + pos + Vector3.new(0, h * 0.55 + (h * 0.45) / 2, 0),
					Color = Color3.fromRGB(115, 95, 85), Material = Enum.Material.Cobblestone}, arena)
				table.insert(arenaBlocks, {c = ARENA_CENTER + pos, half = w / 2, top = h})
			end
		end
	end

	-- 邊緣雕花護柱（高度 18，帶霓虹頂燈）
	local pillarCount = (shape == 1 and 8) or (shape == 2 and 4) or (shape == 3 and 3) or 5
	for i = 0, pillarCount - 1 do
		local ang = math.rad(i * (360 / pillarCount))
		local ppos = ARENA_CENTER + Vector3.new(math.cos(ang) * (ARENA_R - 4), 9, math.sin(ang) * (ARENA_R - 4))
		part({Size = Vector3.new(3.8, 18, 3.8), Position = ppos, Color = Color3.fromRGB(65, 55, 70), Material = Enum.Material.Slate}, arena)
		local plamp = part({Size = Vector3.new(2.4, 2.4, 2.4), Position = ppos + Vector3.new(0, 10, 0), Color = Color3.fromRGB(255, 180, 60), Material = Enum.Material.Neon}, arena)
		local plight = Instance.new("PointLight"); plight.Color = Color3.fromRGB(255, 180, 60); plight.Range = 22; plight.Brightness = 2; plight.Parent = plamp
	end
	-- （完全移除四周無用的 14 顆黑色浮空球）

	arena.Parent = workspace
	return arena
end

-- 海面（很下面，全地圖共用，只建一次）
part({Name = "Ocean", Size = Vector3.new(2000, 4, 2000), Position = ARENA_CENTER + Vector3.new(0, -60, 0),
	Color = Color3.fromRGB(45, 130, 200), Material = Enum.Material.Grass})

-- ------------------------------------------------------------
-- 回合狀態
-- ------------------------------------------------------------
local roundActive = false
local inRound: {[Player]: boolean} = {}
local alive: {[Player]: boolean} = {}
-- 觀戰名單 spectating 聲明已提前至頂部
local lastAttacker: {[Player]: Player} = {}
local roundTag = 0

-- 相互引用函式前置宣告（避免在定義前呼叫導致 attempt to call a nil value 造成遊戲無法開始）
local clearBots: () -> ()
local spawnBot: (idx: number, spawnPos: Vector3) -> ()
local makeKnifeTool: (skinId: string) -> Tool
local knifeHit: (attacker: Player) -> ()
local giveKnife: (plr: Player) -> ()
local ballBurst: (pos: Vector3, color: Color3, scale: number) -> ()
local reflectBall: (attacker: Player?, ball: BasePart, look: Vector3, t: any) -> ()
local breakBall: (attacker: Player, ball: BasePart, t: any) -> ()
local swordSweepBalls: ((attacker: Player, look: Vector3) -> number)?
local spawnBall: (kindId: string?) -> ()
local spawnBox: () -> ()
local BALL_BY_ID: {[string]: any} = {}

-- 清掉上一回合留下的球／盒子／陷阱（全部直接掛在 Workspace 上，用屬性標記）
local function clearRoundObjects()
	clearBots()
	for _, ch in ipairs(workspace:GetChildren()) do
		if ch:GetAttribute("RoundTag") ~= nil then
			ch:Destroy()
		end
	end
end

local function tagObject(obj: BasePart)
	obj:SetAttribute("RoundTag", roundTag)
	obj:SetAttribute("KillBall", nil)
end

local function setStatus(txt: string)
	broadcast("status", txt)
end

local function playerCount(): number
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do n += 1 end
	return n
end

-- ------------------------------------------------------------
-- 刀（Tool）
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 機器人陪玩系統（單人或少人時自動加入 AI 武者）
-- ------------------------------------------------------------
local activeBots: {Model} = {}
local BOT_NAMES = {"[AI] 影武者·零式", "[AI] 疾風武者", "[AI] 烈火劍客"}
local BOT_COLORS = {Color3.fromRGB(60, 180, 255), Color3.fromRGB(255, 90, 90), Color3.fromRGB(255, 200, 50)}

clearBots = function()
	for _, b in ipairs(activeBots) do
		if b and b.Parent then b:Destroy() end
	end
	table.clear(activeBots)
end

spawnBot = function(idx: number, spawnPos: Vector3)
	local BOT_OUTFITS = {
		{shirt = 398633812, pants = 398633842, hair = "37652735", color = Color3.fromRGB(35, 38, 48)},
		{shirt = 607785314, pants = 607785368, hair = "62234425", color = Color3.fromRGB(160, 48, 45)},
		{shirt = 144076358, pants = 144076760, hair = "16630147", color = Color3.fromRGB(45, 95, 165)},
	}
	local outfit = BOT_OUTFITS[idx] or BOT_OUTFITS[1]

	local desc = Instance.new("HumanoidDescription")
	desc.Shirt = outfit.shirt
	desc.Pants = outfit.pants
	desc.HairAccessory = outfit.hair
	desc.HeadColor = Color3.fromRGB(240, 235, 230)
	desc.TorsoColor = outfit.color
	desc.LeftArmColor = Color3.fromRGB(240, 235, 230)
	desc.RightArmColor = Color3.fromRGB(240, 235, 230)
	desc.LeftLegColor = Color3.fromRGB(30, 32, 40)
	desc.RightLegColor = Color3.fromRGB(30, 32, 40)

	local bot = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	bot.Name = BOT_NAMES[idx] or ("[AI] 武者 " .. idx)
	tagObject(bot)

	local hum = bot:FindFirstChildOfClass("Humanoid")
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Parent = bot
	end
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = math.random(17, 21)
	hum.DisplayName = bot.Name
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged

	local hrp = bot:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then hrp = bot.PrimaryPart :: BasePart end

	bot:PivotTo(CFrame.new(spawnPos + Vector3.new(0, 3, 0)))

	local botSkins = {"steel", "thunder", "sakura", "frost", "astra"}
	local chosenSkin = botSkins[idx] or "steel"
	local tool = makeKnifeTool(chosenSkin)
	tool.Parent = bot

	-- 確保武器與人機右手緊密鎖合
	local rightHand = bot:FindFirstChild("RightHand") :: BasePart?
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if rightHand and handle then
		local grip = rightHand:FindFirstChild("RightGrip")
		if not grip then
			local w = Instance.new("Motor6D")
			w.Name = "RightGrip"
			w.Part0 = rightHand
			w.Part1 = handle
			w.C0 = CFrame.new(0, -0.15, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			w.Parent = rightHand
		end
	end

	-- ============================================================
	-- 人機全套真人動作系統（行走、奔跑、呼吸待機、三段連貫斬擊）
	-- ============================================================
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local function loadBotAnim(id: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
		local ok, res = pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = id
			local trk = animator:LoadAnimation(a)
			trk.Priority = priority
			trk.Looped = looped
			return trk
		end)
		if ok and res then return res :: any end
		return nil
	end

	local idleTrack = loadBotAnim("rbxassetid://507766666", Enum.AnimationPriority.Idle, true)
	local walkTrack = loadBotAnim("rbxassetid://507777826", Enum.AnimationPriority.Movement, true)
	local runTrack = loadBotAnim("rbxassetid://507767714", Enum.AnimationPriority.Movement, true)

	local slashTracks = {
		loadBotAnim("rbxassetid://522635533", Enum.AnimationPriority.Action3, false),
		loadBotAnim("rbxassetid://522638767", Enum.AnimationPriority.Action3, false),
		loadBotAnim("rbxassetid://113532863616074", Enum.AnimationPriority.Action4, false),
	}

	if idleTrack then idleTrack:Play(0.1) end

	-- 動態腳步步頻與跑步動作監聽
	hum.Running:Connect(function(speed)
		if speed > 18 then
			if runTrack and not runTrack.IsPlaying then
				if walkTrack then walkTrack:Stop(0.15) end
				runTrack:Play(0.15)
			end
			if runTrack then runTrack:AdjustSpeed(math.clamp(speed / 20, 0.9, 1.4)) end
		elseif speed > 0.8 then
			if walkTrack and not walkTrack.IsPlaying then
				if runTrack then runTrack:Stop(0.15) end
				walkTrack:Play(0.15)
			end
			if walkTrack then walkTrack:AdjustSpeed(math.clamp(speed / 16, 0.85, 1.3)) end
		else
			if runTrack and runTrack.IsPlaying then runTrack:Stop(0.2) end
			if walkTrack and walkTrack.IsPlaying then walkTrack:Stop(0.2) end
			if idleTrack and not idleTrack.IsPlaying then idleTrack:Play(0.2) end
		end
	end)

	local comboIdx = 1
	local function botSlash()
		local trk = slashTracks[comboIdx]
		comboIdx = (comboIdx % #slashTracks) + 1
		if trk then
			trk:Play(0.05)
		end
		local slashSnd = Instance.new("Sound")
		slashSnd.SoundId = "rbxassetid://12222225"
		slashSnd.Volume = 1.15
		slashSnd.PlaybackSpeed = 0.98 + math.random() * 0.15
		slashSnd.Parent = hrp
		slashSnd:Play()
		game:GetService("Debris"):AddItem(slashSnd, 1.2)

		for _, p in ipairs(Players:GetPlayers()) do
			send(p, "bot_swingfx", {
				botName = bot.Name,
				skin = chosenSkin,
				pos = hrp and hrp.Position or bot:GetPivot().Position
			})
		end
	end

	bot.Parent = workspace
	table.insert(activeBots, bot)

	hum.Died:Connect(function()
		broadcast("killfeed", {killer = "", victim = bot.Name, by = "died"})
		if idleTrack then idleTrack:Stop(0.1) end
		if walkTrack then walkTrack:Stop(0.1) end
		if runTrack then runTrack:Stop(0.1) end
		for i, b in ipairs(activeBots) do
			if b == bot then table.remove(activeBots, i); break end
		end
		task.delay(1.5, function() if bot.Parent then bot:Destroy() end end)
	end)

	-- 智慧 AI 決策迴圈（防墜崖約束、近距離精準反彈殺向對手、安全時拾取技能盒子）
	task.spawn(function()
		local botSwingCd = 0
		local currentTargetEntity: any = nil
		local isTargetBot = false
		local targetSwitchClock = 0

		local function clampArena(target: Vector3): Vector3
			local off = target - ARENA_CENTER
			local flat = Vector3.new(off.X, 0, off.Z)
			local maxR = ARENA_R - 14
			if flat.Magnitude > maxR then
					flat = flat.Unit * maxR
			end
			return ARENA_CENTER + Vector3.new(flat.X, 1.5, flat.Z)
		end

		while bot.Parent and hum.Health > 0 and roundActive do
			local bPos = hrp and hrp.Position or bot:GetPivot().Position
			if bPos.Y < (ARENA_CENTER.Y - 35) then
				hum.Health = 0
				break
			end

			local now = os.clock()

			-- 0. 構建全場目標池（包含人類玩家與所有人機機器人）
			local validTargets = {}
			for p, a in pairs(alive) do
				if a and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Character:FindFirstChild("Humanoid") then
					local phum = p.Character.Humanoid :: Humanoid
					if phum.Health > 0 then
						table.insert(validTargets, {
							entity = p,
							isBot = false,
							name = p.DisplayName,
							pos = (p.Character.HumanoidRootPart :: BasePart).Position,
							hum = phum,
							hrp = p.Character.HumanoidRootPart :: BasePart
						})
					end
				end
			end
			for _, ob in ipairs(activeBots) do
				if ob ~= bot and ob.Parent and ob.PrimaryPart and ob:FindFirstChild("Humanoid") then
					local ohum = ob.Humanoid :: Humanoid
					if ohum.Health > 0 then
						table.insert(validTargets, {
							entity = ob,
							isBot = true,
							name = ob.Name,
							pos = ob.PrimaryPart.Position,
							hum = ohum,
							hrp = ob.PrimaryPart
						})
					end
				end
			end

			-- 目標選擇與鎖定（擬人化：維持鎖定 4~7 秒，避免鬼畜切換；且人機之間會高機率互相決鬥，防止圍毆單一玩家）
			local targetObj = nil
			if currentTargetEntity then
				for _, vt in ipairs(validTargets) do
					if vt.entity == currentTargetEntity then targetObj = vt; break end
				end
			end

			if not targetObj or now > targetSwitchClock then
				if #validTargets > 0 then
					local botTargets = {}
					local humanTargets = {}
					for _, vt in ipairs(validTargets) do
						if vt.isBot then table.insert(botTargets, vt) else table.insert(humanTargets, vt) end
					end

					-- 70% 機率人機互打決鬥，30% 機率打玩家（徹底解決全體人機圍攻玩家的體驗問題）
					if #botTargets > 0 and (math.random() < 0.70 or #humanTargets == 0) then
						targetObj = botTargets[math.random(1, #botTargets)]
					elseif #humanTargets > 0 then
						targetObj = humanTargets[math.random(1, #humanTargets)]
					else
						targetObj = validTargets[math.random(1, #validTargets)]
					end
					currentTargetEntity = targetObj.entity
					isTargetBot = targetObj.isBot
					targetSwitchClock = now + math.random(4, 7)
				else
					currentTargetEntity = nil
				end
			end

			local targetPos = targetObj and targetObj.pos or nil
			local targetDist = targetPos and (targetPos - bPos).Magnitude or 999

			-- 1. 優先級一：威脅感知——偵測 28 格內飛來的閃避球並揮刀反彈（85% 成功率，15% 擬人化失誤）
			local dangerBall: BasePart? = nil
			local minBallDist = 28
			for _, obj in ipairs(workspace:GetChildren()) do
				if obj:IsA("BasePart") and (obj:GetAttribute("KillBall") or obj:GetAttribute("BallKind")) then
					local dist = (obj.Position - bPos).Magnitude
					if dist < minBallDist then
						minBallDist = dist
						dangerBall = obj
					end
				end
			end

			if dangerBall and now > botSwingCd then
				botSwingCd = now + 0.55
				-- 15% 擬人化失誤率：偶爾揮空或沒打中球，產生真實博弈感
				local misses = (math.random() < 0.15)
				if not misses then
					local reflectDir = targetPos and (targetPos - bPos).Unit or -(dangerBall.Position - bPos).Unit
					if hrp then
						hrp.CFrame = CFrame.lookAt(bPos, bPos + Vector3.new(reflectDir.X, 0, reflectDir.Z))
					end
					botSlash()
					local kind = dangerBall:GetAttribute("BallKind")
					local t = kind and BALL_BY_ID[kind :: string] or nil
					if t and reflectBall then
						reflectBall(nil, dangerBall, reflectDir, t)
						ballBurst(dangerBall.Position, Color3.fromRGB(255, 215, 60), 2.5)
					end
				else
					if hrp then
						hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(math.random(-45, 45)), 0)
					end
				end
			else
				-- 2. 優先級二：爭奪場上隨機掉落的神秘技能箱（MysteryBox）
				local closestBox: BasePart? = nil
				local closestBoxDist = 60
				for _, obj in ipairs(workspace:GetChildren()) do
					if obj:IsA("BasePart") and obj.Name == "MysteryBox" and obj:GetAttribute("BoxActive") ~= false then
						local dist = (obj.Position - bPos).Magnitude
						if dist < closestBoxDist then
							closestBoxDist = dist
							closestBox = obj
						end
					end
				end

				if closestBox and closestBoxDist > 4 and targetDist > 18 then
					hum:MoveTo(clampArena(closestBox.Position))
				elseif targetObj and targetDist <= 11 and now > botSwingCd then
					-- 3. 優先級三：近戰連擊——在 11 格內斬殺對手（玩家或其他人機均可遭受打擊！）
					botSwingCd = now + 0.60
					if hrp then
						hrp.CFrame = CFrame.lookAt(bPos, bPos + Vector3.new(targetPos.X - bPos.X, 0, targetPos.Z - bPos.Z))
					end
					botSlash()

					-- 判定打擊：目標是玩家
					if not targetObj.isBot then
						local p = targetObj.entity :: Player
						local phum = targetObj.hum :: Humanoid
						phum:TakeDamage(25)
						send(p, "hurt", {dmg = 25, attacker = bot.Name})
						ballBurst(targetObj.pos, Color3.fromRGB(255, 75, 75), 1.8)
						if phum.Health <= 0 then
							broadcast("killfeed", {killer = bot.Name, victim = p.DisplayName, by = "knife"})
						end
					else
						-- 目標是其他人機（人機之間互砍決鬥！）
						local ohum = targetObj.hum :: Humanoid
						ohum:TakeDamage(25)
						ballBurst(targetObj.pos, Color3.fromRGB(255, 120, 60), 1.8)
						if ohum.Health <= 0 then
							broadcast("killfeed", {killer = bot.Name, victim = targetObj.name, by = "knife"})
						end
					end
				elseif targetObj then
					-- 4. 戰術走位：蛇形微繞側翼突進（避免直線死衝，呈現忍者刺客步法）
					local strafeAngle = (os.clock() * 2) % (math.pi * 2)
					local strafeOffset = Vector3.new(math.cos(strafeAngle) * 6, 0, math.sin(strafeAngle) * 6)
					local approachTarget = targetPos + strafeOffset
					hum:MoveTo(clampArena(approachTarget))
				else
					local ang = math.random() * math.pi * 2
					local dist = math.random(5, ARENA_R - 20)
					hum:MoveTo(ARENA_CENTER + Vector3.new(math.cos(ang) * dist, 0, math.sin(ang) * dist))
				end
			end
			task.wait(0.20)
		end
	end)
end



-- ============================================================
-- 9 款頂級神兵專屬 3D 幾何模型（每把刀輪廓、結構、特效完全獨一無二，越貴越帥）
-- ============================================================
local function buildKnifeParts(parent: Instance, skinId: string, isTool: boolean): BasePart
	local root = Instance.new("Part")
	root.Name = isTool and "Handle" or "Root"
	root.Size = Vector3.new(0.24, 1.2, 0.24)
	root.Color = Color3.fromRGB(40, 40, 44)
	root.Material = Enum.Material.Metal
	root.CanCollide = false
	root.Anchored = not isTool
	root.Parent = parent

	local function addPart(name: string, sz: Vector3, cfOffset: CFrame, col: Color3, mat: Enum.Material, shape: Enum.PartType?, trans: number?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = sz
		if shape then p.Shape = shape end
		p.Color = col
		p.Material = mat
		p.Transparency = trans or 0
		p.CanCollide = false
		p.Anchored = not isTool
		p.CFrame = root.CFrame * cfOffset
		p.Parent = parent
		if isTool then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = root
		end
		return p
	end

	if skinId == "steel" then
		-- 精鋼之刃 (T1): 經典戰術刺客匕首 / 短刀
		addPart("Grip", Vector3.new(0.28, 0.9, 0.28), CFrame.new(0, -0.1, 0), Color3.fromRGB(25, 25, 28), Enum.Material.Rubber)
		addPart("PommelRing", Vector3.new(0.32, 0.12, 0.32), CFrame.new(0, -0.65, 0), Color3.fromRGB(180, 185, 195), Enum.Material.Metal)
		addPart("Guard", Vector3.new(0.75, 0.12, 0.26), CFrame.new(0, 0.6, 0), Color3.fromRGB(150, 155, 165), Enum.Material.Metal)
		addPart("Blade", Vector3.new(0.1, 2.2, 0.44), CFrame.new(0, 1.75, 0), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
		addPart("Edge", Vector3.new(0.12, 2.1, 0.08), CFrame.new(0, 1.75, -0.23), Color3.fromRGB(240, 245, 255), Enum.Material.Metal)
	elseif skinId == "obsidian" then
		-- 黑曜石刺 (T2): 鋒銳暗黑火山琉璃刺
		addPart("Grip", Vector3.new(0.3, 0.95, 0.3), CFrame.new(0, -0.1, 0), Color3.fromRGB(22, 18, 28), Enum.Material.Slate)
		addPart("Pommel", Vector3.new(0.35, 0.2, 0.35), CFrame.new(0, -0.65, 0), Color3.fromRGB(130, 45, 200), Enum.Material.Neon)
		addPart("GuardL", Vector3.new(0.4, 0.12, 0.22), CFrame.new(-0.35, 0.65, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(35, 30, 45), Enum.Material.Glass)
		addPart("GuardR", Vector3.new(0.4, 0.12, 0.22), CFrame.new(0.35, 0.65, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(35, 30, 45), Enum.Material.Glass)
		addPart("Blade", Vector3.new(0.14, 2.5, 0.42), CFrame.new(0, 1.9, 0), Color3.fromRGB(35, 28, 50), Enum.Material.Glass, nil, 0.15)
		addPart("RuneSpine", Vector3.new(0.16, 2.3, 0.12), CFrame.new(0, 1.9, 0), Color3.fromRGB(170, 60, 255), Enum.Material.Neon)
	elseif skinId == "thunder" then
		-- 雷霆之薙 (T3): 鋸齒閃電彎刀 / 電磁叉護手
		addPart("Grip", Vector3.new(0.26, 1.0, 0.26), CFrame.new(0, -0.1, 0), Color3.fromRGB(20, 30, 50), Enum.Material.Fabric)
		addPart("PommelBolt", Vector3.new(0.35, 0.3, 0.2), CFrame.new(0, -0.7, 0), Color3.fromRGB(255, 215, 60), Enum.Material.Neon)
		addPart("GuardL", Vector3.new(0.5, 0.14, 0.24), CFrame.new(-0.4, 0.65, 0) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(90, 170, 255), Enum.Material.Neon)
		addPart("GuardR", Vector3.new(0.5, 0.14, 0.24), CFrame.new(0.4, 0.65, 0) * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(90, 170, 255), Enum.Material.Neon)
		addPart("BladeSeg1", Vector3.new(0.12, 1.0, 0.5), CFrame.new(0, 1.15, 0), Color3.fromRGB(90, 170, 255), Enum.Material.Neon)
		addPart("BladeSeg2", Vector3.new(0.12, 1.0, 0.44), CFrame.new(0.1, 2.05, 0) * CFrame.Angles(0, 0, math.rad(-10)), Color3.fromRGB(130, 205, 255), Enum.Material.Neon)
		addPart("BladeSeg3", Vector3.new(0.12, 0.9, 0.36), CFrame.new(-0.05, 2.9, 0) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(200, 240, 255), Enum.Material.Neon)
	elseif skinId == "sakura" then
		-- 櫻花武士刀 (T4): 正統和風野太刀 / 金色櫻花刀鐔
		addPart("Grip", Vector3.new(0.24, 1.3, 0.24), CFrame.new(0, -0.15, 0), Color3.fromRGB(240, 235, 235), Enum.Material.SmoothPlastic)
		addPart("ItoWrap", Vector3.new(0.26, 1.1, 0.26), CFrame.new(0, -0.15, 0), Color3.fromRGB(180, 50, 90), Enum.Material.Fabric)
		addPart("PommelCap", Vector3.new(0.3, 0.15, 0.3), CFrame.new(0, -0.75, 0), Color3.fromRGB(240, 195, 70), Enum.Material.Metal)
		addPart("Tsuba", Vector3.new(0.12, 0.78, 0.78), CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(240, 195, 70), Enum.Material.Metal, Enum.PartType.Cylinder)
		addPart("Blade", Vector3.new(0.08, 3.1, 0.36), CFrame.new(0, 2.2, 0), Color3.fromRGB(255, 185, 215), Enum.Material.SmoothPlastic)
		addPart("Hamon", Vector3.new(0.1, 3.0, 0.1), CFrame.new(0, 2.2, -0.16), Color3.fromRGB(255, 230, 240), Enum.Material.Neon)
	elseif skinId == "frost" then
		-- 霜之哀傷 (T4): 冰晶重劍 / 惡魔冰角護手與兩側突刺
		addPart("Grip", Vector3.new(0.28, 1.2, 0.28), CFrame.new(0, -0.1, 0), Color3.fromRGB(30, 45, 60), Enum.Material.Metal)
		addPart("PommelIce", Vector3.new(0.4, 0.28, 0.4), CFrame.new(0, -0.75, 0), Color3.fromRGB(160, 230, 255), Enum.Material.Ice)
		addPart("GuardHoriz", Vector3.new(1.3, 0.2, 0.38), CFrame.new(0, 0.62, 0), Color3.fromRGB(60, 95, 130), Enum.Material.Metal)
		addPart("GuardHornL", Vector3.new(0.2, 0.5, 0.2), CFrame.new(-0.6, 0.85, 0) * CFrame.Angles(0, 0, math.rad(30)), Color3.fromRGB(160, 230, 255), Enum.Material.Ice)
		addPart("GuardHornR", Vector3.new(0.2, 0.5, 0.2), CFrame.new(0.6, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(160, 230, 255), Enum.Material.Ice)
		addPart("BladeMain", Vector3.new(0.14, 3.2, 0.68), CFrame.new(0, 2.25, 0), Color3.fromRGB(170, 235, 255), Enum.Material.Ice, nil, 0.1)
		addPart("Spike1L", Vector3.new(0.35, 0.16, 0.12), CFrame.new(-0.45, 1.8, 0) * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(200, 245, 255), Enum.Material.Neon)
		addPart("Spike1R", Vector3.new(0.35, 0.16, 0.12), CFrame.new(0.45, 1.8, 0) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(200, 245, 255), Enum.Material.Neon)
		addPart("Spike2L", Vector3.new(0.3, 0.14, 0.12), CFrame.new(-0.42, 2.6, 0) * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(200, 245, 255), Enum.Material.Neon)
		addPart("Spike2R", Vector3.new(0.3, 0.14, 0.12), CFrame.new(0.42, 2.6, 0) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(200, 245, 255), Enum.Material.Neon)
	elseif skinId == "astra" then
		-- 星軌重刃 (T5): 未來星界斬艦刀 / 環形星盤與分叉雙刃頭
		addPart("Grip", Vector3.new(0.26, 1.3, 0.26), CFrame.new(0, -0.15, 0), Color3.fromRGB(25, 35, 35), Enum.Material.Metal)
		addPart("PommelCore", Vector3.new(0.38, 0.38, 0.38), CFrame.new(0, -0.85, 0), Color3.fromRGB(120, 255, 180), Enum.Material.Neon)
		addPart("AstroRing1", Vector3.new(0.12, 1.1, 1.1), CFrame.new(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 255, 180), Enum.Material.Neon, Enum.PartType.Cylinder, 0.3)
		addPart("AstroRing2", Vector3.new(0.1, 0.8, 0.8), CFrame.new(0, 0.65, 0) * CFrame.Angles(math.rad(45), 0, math.rad(90)), Color3.fromRGB(200, 255, 230), Enum.Material.Neon, Enum.PartType.Cylinder, 0.4)
		addPart("CleaverBody", Vector3.new(0.16, 3.4, 0.84), CFrame.new(0, 2.4, 0), Color3.fromRGB(35, 45, 50), Enum.Material.Metal)
		addPart("CleaverEdge", Vector3.new(0.18, 3.4, 0.15), CFrame.new(0, 2.4, -0.45), Color3.fromRGB(120, 255, 180), Enum.Material.Neon)
		addPart("SplitTipL", Vector3.new(0.16, 0.6, 0.35), CFrame.new(0, 4.2, -0.25) * CFrame.Angles(0, 0, math.rad(-15)), Color3.fromRGB(120, 255, 180), Enum.Material.Neon)
		addPart("SplitTipR", Vector3.new(0.16, 0.6, 0.35), CFrame.new(0, 4.2, 0.25) * CFrame.Angles(0, 0, math.rad(15)), Color3.fromRGB(120, 255, 180), Enum.Material.Neon)
	elseif skinId == "hydra" then
		-- 九頭蛇牙鐮 (T5): 劇毒三刃戰鐮 / 蛇鱗長柄
		addPart("Grip", Vector3.new(0.24, 1.8, 0.24), CFrame.new(0, -0.3, 0), Color3.fromRGB(30, 45, 30), Enum.Material.Slate)
		addPart("SnakePommel", Vector3.new(0.36, 0.4, 0.36), CFrame.new(0, -1.25, 0), Color3.fromRGB(100, 220, 80), Enum.Material.Neon)
		addPart("ShaftTop", Vector3.new(0.3, 0.5, 0.3), CFrame.new(0, 0.75, 0), Color3.fromRGB(50, 75, 50), Enum.Material.Metal)
		addPart("ScytheBlade1", Vector3.new(0.14, 0.5, 1.2), CFrame.new(0, 0.95, -0.6) * CFrame.Angles(math.rad(25), 0, 0), Color3.fromRGB(100, 220, 80), Enum.Material.Neon)
		addPart("ScytheBlade2", Vector3.new(0.14, 0.45, 1.6), CFrame.new(0, 1.3, -1.5) * CFrame.Angles(math.rad(55), 0, 0), Color3.fromRGB(130, 255, 110), Enum.Material.Neon)
		addPart("ScytheTip", Vector3.new(0.14, 0.35, 1.0), CFrame.new(0, 1.35, -2.5) * CFrame.Angles(math.rad(95), 0, 0), Color3.fromRGB(180, 255, 150), Enum.Material.Neon)
		addPart("SubFang1", Vector3.new(0.12, 0.3, 0.6), CFrame.new(0, 0.7, 0.35) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(100, 220, 80), Enum.Material.Neon)
		addPart("SubFang2", Vector3.new(0.12, 0.25, 0.5), CFrame.new(0, 0.5, 0.75) * CFrame.Angles(math.rad(-65), 0, 0), Color3.fromRGB(130, 255, 110), Enum.Material.Neon)
	elseif skinId == "blueflame" then
		-- 青焰冥皇劍 (T6): 皇家雙手巨劍 / 波狀焰刃與龍翼展翅
		addPart("Grip", Vector3.new(0.28, 1.6, 0.28), CFrame.new(0, -0.2, 0), Color3.fromRGB(20, 25, 40), Enum.Material.Fabric)
		addPart("PommelRoyal", Vector3.new(0.42, 0.3, 0.42), CFrame.new(0, -1.05, 0), Color3.fromRGB(240, 200, 60), Enum.Material.Metal)
		addPart("GuardCenter", Vector3.new(0.5, 0.25, 0.4), CFrame.new(0, 0.65, 0), Color3.fromRGB(240, 200, 60), Enum.Material.Metal)
		addPart("WingL", Vector3.new(0.7, 0.2, 0.25), CFrame.new(-0.55, 0.75, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(60, 160, 255), Enum.Material.Neon)
		addPart("WingR", Vector3.new(0.7, 0.2, 0.25), CFrame.new(0.55, 0.75, 0) * CFrame.Angles(0, 0, math.rad(25)), Color3.fromRGB(60, 160, 255), Enum.Material.Neon)
		addPart("Flamberge1", Vector3.new(0.16, 1.3, 0.7), CFrame.new(0.08, 1.35, 0) * CFrame.Angles(0, 0, math.rad(-6)), Color3.fromRGB(60, 160, 255), Enum.Material.Neon)
		addPart("Flamberge2", Vector3.new(0.16, 1.3, 0.65), CFrame.new(-0.08, 2.5, 0) * CFrame.Angles(0, 0, math.rad(7)), Color3.fromRGB(90, 185, 255), Enum.Material.Neon)
		addPart("Flamberge3", Vector3.new(0.16, 1.2, 0.5), CFrame.new(0.05, 3.65, 0) * CFrame.Angles(0, 0, math.rad(-5)), Color3.fromRGB(150, 215, 255), Enum.Material.Neon)
	elseif skinId == "phoenix" then
		-- 鳳凰神滅神刀 (T6): 滅世涅槃神刃 / 鳳羽翼鍔與熾陽光環
		addPart("Grip", Vector3.new(0.28, 1.6, 0.28), CFrame.new(0, -0.2, 0), Color3.fromRGB(45, 18, 12), Enum.Material.Wood)
		addPart("SunHaloPommel", Vector3.new(0.12, 0.7, 0.7), CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 190, 40), Enum.Material.Neon, Enum.PartType.Cylinder)
		addPart("GuardCore", Vector3.new(0.6, 0.3, 0.4), CFrame.new(0, 0.65, 0), Color3.fromRGB(255, 190, 40), Enum.Material.Metal)
		addPart("PhoenixWingL1", Vector3.new(0.8, 0.2, 0.25), CFrame.new(-0.65, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color3.fromRGB(255, 100, 30), Enum.Material.Neon)
		addPart("PhoenixWingR1", Vector3.new(0.8, 0.2, 0.25), CFrame.new(0.65, 0.8, 0) * CFrame.Angles(0, 0, math.rad(30)), Color3.fromRGB(255, 100, 30), Enum.Material.Neon)
		addPart("PhoenixWingL2", Vector3.new(0.5, 0.15, 0.2), CFrame.new(-1.15, 1.1, 0) * CFrame.Angles(0, 0, math.rad(-50)), Color3.fromRGB(255, 190, 40), Enum.Material.Neon)
		addPart("PhoenixWingR2", Vector3.new(0.5, 0.15, 0.2), CFrame.new(1.15, 1.1, 0) * CFrame.Angles(0, 0, math.rad(50)), Color3.fromRGB(255, 190, 40), Enum.Material.Neon)
		addPart("SunBladeMain", Vector3.new(0.14, 3.8, 0.65), CFrame.new(0, 2.6, 0), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		addPart("SunEdge", Vector3.new(0.16, 3.7, 0.14), CFrame.new(0, 2.6, -0.35), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
		addPart("DragonRidge1", Vector3.new(0.15, 0.5, 0.2), CFrame.new(0, 1.8, 0.38) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(255, 190, 40), Enum.Material.Metal)
		addPart("DragonRidge2", Vector3.new(0.15, 0.5, 0.2), CFrame.new(0, 2.6, 0.38) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(255, 190, 40), Enum.Material.Metal)
		addPart("DragonRidge3", Vector3.new(0.15, 0.5, 0.2), CFrame.new(0, 3.4, 0.38) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(255, 190, 40), Enum.Material.Metal)
	end

	if isTool then
		parent.PrimaryPart = root
	elseif parent:IsA("Model") then
		parent.PrimaryPart = root
	end
	return root
end

makeKnifeTool = function(skinId: string): Tool
	local skin = KNIFE_BY_ID[skinId] or KNIVES[1]
	local tier = skin.tier or 1
	local tool = Instance.new("Tool")
	tool.Name = skin.name .. "之刃"
	tool.ToolTip = "點擊 / F 揮刀：砍人掉血，亦可反彈或砍碎閃避球"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("Skin", skin.id)
	tool:SetAttribute("Tier", tier)
	tool:SetAttribute("BladeColor", skin.color)

	local handle = buildKnifeParts(tool, skin.id, true)
	tool.Grip = CFrame.new(0, 0.78, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(-10))
	return tool
end


local swingCd: {[Player]: number} = {}

-- 球的判定寫在下方「球」段落，已在頂部宣告
knifeHit = function(attacker: Player)
	local now = os.clock()
	if (swingCd[attacker] or 0) > now then return end
	swingCd[attacker] = now + 0.38

	local char = attacker.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local look = hrp.CFrame.LookVector

	local equipId = pd(attacker).equipped
	local equipSkin = KNIFE_BY_ID[equipId] or KNIVES[1]
	send(attacker, "swing", {skin = equipSkin.id, tier = equipSkin.tier or 1})

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= attacker then
			send(other, "swingfx", {userId = attacker.UserId, skin = equipSkin.id, tier = equipSkin.tier or 1})
		end
	end

	-- 練刀木人樁判定（大廳亦可隨心練刀測試打擊手感！）
	local dummy = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("TrainingDummy")
	if dummy then
		local dPart = dummy:FindFirstChild("Torso") or dummy.PrimaryPart
		if dPart and (dPart.Position - hrp.Position).Magnitude <= 14 and look:Dot((dPart.Position - hrp.Position).Unit) > -0.15 then
			local origCF = dummy:GetAttribute("OrigCF") :: CFrame?
			if not origCF then
				dummy:SetAttribute("OrigCF", dPart.CFrame)
				origCF = dPart.CFrame
			end
			local hitBackCF = origCF * CFrame.Angles(math.rad(-18), 0, 0)
			TweenService:Create(dPart, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = hitBackCF}):Play()
			task.delay(0.08, function()
				TweenService:Create(dPart, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {CFrame = origCF}):Play()
			end)
			local isCrit = math.random() < 0.35
			local practiceDmg = math.random(25, 45) + (equipSkin.dmg or 25)
			dummyHits += 1
			lastDummyHit = os.clock()
			chargeUltimate(attacker, 15)

			local curHits = dummyHits
			local rank = (curHits >= 50 and "SSS") or (curHits >= 30 and "SS") or (curHits >= 20 and "S") or (curHits >= 15 and "A") or (curHits >= 10 and "B") or (curHits >= 5 and "C") or "D"
			local bb = dummy:FindFirstChild("TargetDisplay", true) :: BillboardGui?
			if bb then
				local lbl = bb:FindFirstChildOfClass("TextLabel")
				if lbl then
					lbl.Text = "🔥 COMBO: " .. curHits .. " HITS! [" .. rank .. "級]"
					lbl.TextColor3 = (rank == "SSS" and Color3.fromRGB(255, 60, 60)) or (rank == "SS" and Color3.fromRGB(255, 140, 40)) or (rank == "S" and Color3.fromRGB(255, 215, 50)) or Color3.fromRGB(120, 255, 180)
				end
			end
			task.delay(2.6, function()
				if os.clock() - lastDummyHit >= 2.5 and dummyHits == curHits then
					dummyHits = 0
					if bb then
						local lbl = bb:FindFirstChildOfClass("TextLabel")
						if lbl then
							lbl.Text = "🎯 練刀木人樁"
							lbl.TextColor3 = Color3.fromRGB(255, 215, 60)
						end
					end
				end
			end)

			send(attacker, "hitsuccess", {
				dmg = practiceDmg,
				victim = "練刀木人樁",
				pos = dPart.Position + Vector3.new(0, 1, 0),
				isCrit = isCrit,
				skin = equipSkin.id
			})
			ballBurst(dPart.Position + Vector3.new(0, 1.2, 0), equipSkin.color, 2.0)
		end
	end

	-- 記錄揮刀時間，並判定貼身拼刀（Sword Clash）
	lastSlashTime[attacker] = os.clock()
	for otherPlr in pairs(alive) do
		if otherPlr ~= attacker and alive[otherPlr] then
			local oChar = otherPlr.Character
			local oHrp = oChar and oChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if oHrp and (oHrp.Position - hrp.Position).Magnitude <= 7.5 then
				if os.clock() - (lastSlashTime[otherPlr] or 0) < 0.22 then
					local mid = (hrp.Position + oHrp.Position) * 0.5
					send(attacker, "swordclash", {pos = mid})
					send(otherPlr, "swordclash", {pos = mid})
					hrp.AssemblyLinearVelocity = -look * 28
					oHrp.AssemblyLinearVelocity = look * 28
					ballBurst(mid, Color3.fromRGB(255, 230, 90), 2.8)
					return
				end
			end
		end
	end
	for _, b in ipairs(activeBots) do
		if b and b.PrimaryPart and (b.PrimaryPart.Position - hrp.Position).Magnitude <= 7.5 then
			if os.clock() - (lastSlashTime[b] or 0) < 0.22 then
				local mid = (hrp.Position + b.PrimaryPart.Position) * 0.5
				send(attacker, "swordclash", {pos = mid})
				hrp.AssemblyLinearVelocity = -look * 28
				b.PrimaryPart.AssemblyLinearVelocity = look * 28
				ballBurst(mid, Color3.fromRGB(255, 230, 90), 2.8)
				return
			end
		end
	end

	-- 若不在回合中，大廳揮刀/練刀在此結束
	if not roundActive or not inRound[attacker] or not alive[attacker] then return end

	-- 砍人（傷害隨刀提升，判定距離放大至 12~18 格，覆蓋 180 度扇形）
	local dmg = equipSkin.dmg or 25
	local meleeReach = (equipSkin.reach or 22) * 0.55
	for target in pairs(alive) do
		if target ~= attacker and alive[target] then
			local tchar = target.Character
			local thrp = tchar and (tchar:FindFirstChild("HumanoidRootPart") :: BasePart?)
			local thum = tchar and (tchar:FindFirstChild("Humanoid") :: Humanoid?)
			if thrp and thum and thum.Health > 0 then
				if (thrp:GetAttribute("InvincibleUntil") or 0) > os.clock() then
					continue
				end
				local off = thrp.Position - hrp.Position
				if off.Magnitude <= meleeReach and look:Dot(off.Unit) > -0.15 then
					lastAttacker[target] = attacker
					thum:TakeDamage(dmg)
					local isCrit = (dmg >= 45) or (math.random() < 0.25)
					send(attacker, "hitsuccess", {
						dmg = dmg,
						victim = target.DisplayName,
						pos = thrp.Position,
						isCrit = isCrit,
						skin = equipSkin.id
					})
					send(target, "hurt", {dmg = dmg, attacker = attacker.DisplayName})
					ballBurst(thrp.Position, equipSkin.color, 2.0)

					if equipSkin.skill == "寒冰減速" then
						applySlow(target)
					elseif equipSkin.skill == "劇毒撕裂" then
						task.spawn(function()
							for _ = 1, 3 do
								task.wait(1)
								if thum and thum.Health > 0 and roundActive then
									thum:TakeDamage(9)
									send(target, "hurt", {dmg = 9})
								end
							end
						end)
					end

					if thum.Health <= 0 then
						local kd = pd(attacker)
						kd.coins += COIN_KILL
						kd.kills += 1
						syncLeader(attacker)
						send(attacker, "coins", kd.coins)
						broadcast("killfeed", {killer = attacker.DisplayName, victim = target.DisplayName, by = "knife"})
					end
				end
			end
		end
	end

	-- 砍機器人
	for _, bot in ipairs(activeBots) do
		if bot and bot.PrimaryPart and bot:FindFirstChild("Humanoid") then
			local bHum = bot.Humanoid :: Humanoid
			if bHum.Health > 0 then
				local off = bot.PrimaryPart.Position - hrp.Position
				if off.Magnitude <= meleeReach and look:Dot(off.Unit) > -0.15 then
					bHum:TakeDamage(dmg)
					local isCrit = (dmg >= 45) or (math.random() < 0.25)
					send(attacker, "hitsuccess", {
						dmg = dmg,
						victim = bot.Name,
						pos = bot.PrimaryPart.Position,
						isCrit = isCrit,
						skin = equipSkin.id
					})
					ballBurst(bot.PrimaryPart.Position, equipSkin.color, 2.0)
					if bHum.Health <= 0 then
						local kd = pd(attacker)
						kd.coins += 10
						send(attacker, "coins", kd.coins)
						broadcast("killfeed", {killer = attacker.DisplayName, victim = bot.Name, by = "knife"})
					end
				end
			end
		end
	end

	-- 砍球：可砍碎或反彈
	if swordSweepBalls then
		swordSweepBalls(attacker, look)
	end
end

-- 給玩家發刀
giveKnife = function(plr: Player)
	local char = plr.Character
	if not char then return end
	local backpack = plr:FindFirstChild("Backpack")
	if not backpack then return end
	-- 移除舊刀
	for _, t in ipairs(backpack:GetChildren()) do
		if t:IsA("Tool") then t:Destroy() end
	end
	local chTool = char:FindFirstChildOfClass("Tool")
	if chTool then chTool:Destroy() end
	local tool = makeKnifeTool(pd(plr).equipped)
	tool.Parent = backpack
	tool.Activated:Connect(function()
		knifeHit(plr)
	end)
end

-- ------------------------------------------------------------
-- 死亡處理（前向宣告，供 CharacterAdded 使用）
-- ------------------------------------------------------------
local onCharacterDeath: (Player) -> ()

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid") :: Humanoid
		hum.WalkSpeed = 16
		hum:SetAttribute("SpeedMul", 1)
		hum.MaxHealth = 100
		hum.Health = 100
		task.wait(0.3)
		giveKnife(plr)
		-- 不在回合中的玩家一定站在大廳出生點
		if not inRound[plr] then
			char:PivotTo(CFrame.new(LOBBY_CENTER + Vector3.new(0, 4, 10)))
		end
		hum.Died:Connect(function()
			onCharacterDeath(plr)
		end)
	end)
end)

function onCharacterDeath(plr: Player)
	if not roundActive or not inRound[plr] then return end
	if not alive[plr] then return end -- 已由球/其他方式判定過，避免重複播報
	alive[plr] = false
	local killer = lastAttacker[plr]
	if killer and killer ~= plr and killer.Parent then
		local d = pd(killer)
		d.coins += COIN_KILL
		d.kills += 1
		syncLeader(killer)
		send(killer, "coins", d.coins)
		broadcast("killfeed", {killer = killer.DisplayName, victim = plr.DisplayName, by = "knife"})
	else
		broadcast("killfeed", {killer = "", victim = plr.DisplayName, by = "unknown"})
	end
	lastAttacker[plr] = nil :: any
end

-- ------------------------------------------------------------
-- 球：9 種球型，撞到即死；揮刀可以「砍碎」或「反彈」回去
-- ------------------------------------------------------------
local BALL_TYPES = {
	{
		id = "standard", name = "標準球", color = Color3.fromRGB(255, 122, 40), edge = Color3.fromRGB(255, 214, 130),
		size = 6.0, spd = {55, 85}, track = 0.70, homing = 0.09, hp = 1, coin = 3,
		weight = 34, from = 0.00, glow = 0.7, material = Enum.Material.Neon, trail = true,
	},
	{
		id = "heavy", name = "巨岩球", color = Color3.fromRGB(122, 110, 100), edge = Color3.fromRGB(196, 182, 156),
		size = 9.2, spd = {34, 50}, track = 0.30, homing = 0.04, hp = 0, coin = 2,
		weight = 12, from = 0.06, glow = 0.0, material = Enum.Material.Slate, reflectMul = 1.45,
	},
	{
		id = "quick", name = "疾風球", color = Color3.fromRGB(120, 235, 255), edge = Color3.fromRGB(240, 255, 255),
		size = 4.2, spd = {96, 128}, track = 0.85, homing = 0.12, hp = 1, coin = 4,
		weight = 16, from = 0.10, glow = 0.8, material = Enum.Material.Neon, trail = true,
	},
	{
		id = "split", name = "分裂球", color = Color3.fromRGB(255, 90, 200), edge = Color3.fromRGB(255, 200, 245),
		size = 6.4, spd = {58, 78}, track = 0.55, homing = 0.08, hp = 1, coin = 5,
		weight = 12, from = 0.18, glow = 0.7, material = Enum.Material.Neon, trail = true, split = true,
	},
	{
		id = "ghost", name = "幽靈球", color = Color3.fromRGB(178, 120, 255), edge = Color3.fromRGB(235, 215, 255),
		size = 6.0, spd = {62, 84}, track = 0.75, homing = 0.10, hp = 0, coin = 2,
		weight = 10, from = 0.22, glow = 0.5, material = Enum.Material.ForceField, alpha = 0.35, trail = true,
	},
	{
		id = "fire", name = "烈焰球", color = Color3.fromRGB(255, 70, 20), edge = Color3.fromRGB(255, 200, 60),
		size = 6.0, spd = {76, 98}, track = 0.70, homing = 0.09, hp = 1, coin = 4,
		weight = 12, from = 0.14, glow = 1.0, material = Enum.Material.Neon, trail = true, spark = true,
	},
	{
		id = "frost", name = "極寒球", color = Color3.fromRGB(150, 225, 255), edge = Color3.fromRGB(255, 255, 255),
		size = 6.0, spd = {56, 76}, track = 0.60, homing = 0.08, hp = 1, coin = 4,
		weight = 10, from = 0.20, glow = 0.8, material = Enum.Material.Ice, trail = true, spark = true,
	},
	{
		id = "thunder", name = "雷電球", color = Color3.fromRGB(255, 235, 90), edge = Color3.fromRGB(255, 255, 200),
		size = 5.4, spd = {65, 82}, track = 0.75, homing = 0.11, hp = 1, coin = 5,
		weight = 9, from = 0.28, glow = 1.0, material = Enum.Material.Neon, trail = true, spark = true,
	},
	{
		id = "gold", name = "黃金球", color = Color3.fromRGB(255, 200, 60), edge = Color3.fromRGB(255, 250, 200),
		size = 5.0, spd = {42, 58}, track = 0.45, homing = 0.06, hp = 2, coin = 40,
		weight = 4, from = 0.32, glow = 1.2, material = Enum.Material.Neon, trail = true, spark = true,
	},
}

-- BALL_BY_ID 已在頂部宣告
for _, t in ipairs(BALL_TYPES) do BALL_BY_ID[t.id] = t end

local roundStartClock = os.clock()
local reflectImmune: {[Instance]: {plr: Player, exp: number}} = {}
local ballHitCd: {[Instance]: number} = {}

-- 依回合進度抽球種（越後期越多花樣）
local function pickBallKind(progress: number)
	local total = 0
	local pool = {}
	for _, t in ipairs(BALL_TYPES) do
		if progress >= t.from then
			total += t.weight
			table.insert(pool, {t = t, w = t.weight})
		end
	end
	if total <= 0 then return BALL_TYPES[1] end
	local roll = math.random() * total
	for _, e in ipairs(pool) do
		roll -= e.w
		if roll <= 0 then return e.t end
	end
	return pool[#pool].t
end

-- 爆開：核心球 + 碎片（給所有人看得到）
ballBurst = function(pos: Vector3, color: Color3, scale: number)
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(scale * 0.55, scale * 0.55, scale * 0.55)
	core.Position = pos
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Material = Enum.Material.Neon
	core.Color = color
	core.Transparency = 0.1
	core.Name = "BallBurst"
	core.Parent = workspace
	TweenService:Create(core, TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(scale * 2.4, scale * 2.4, scale * 2.4),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		if core.Parent then core:Destroy() end
	end)

	for _ = 1, 6 do
		local d = Instance.new("Part")
		d.Size = Vector3.new(0.34, 0.34, 0.34)
		d.Position = pos
		d.Color = color
		d.Material = Enum.Material.Neon
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.Anchored = false
		d.Name = "BallShard"
		d.Parent = workspace
		d.AssemblyLinearVelocity = Vector3.new(math.random(-28, 28), math.random(6, 30), math.random(-28, 28))
		task.delay(0.65, function()
			if d.Parent then d:Destroy() end
		end)
	end
end

-- 球的外觀：發光 / 拖尾 / 火花
-- 輔助：附加裝飾組件（無碰撞/無質量/跟隨本體）
local function attachVisualPart(parent: BasePart, props: {[string]: any}): BasePart
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	for k, v in pairs(props) do
		if k == "CFrame" or k == "Position" then
			-- set below
		else
			(p :: any)[k] = v
		end
	end
	if props.CFrame then
		p.CFrame = props.CFrame
	elseif props.Position then
		p.Position = props.Position
	else
		p.CFrame = parent.CFrame
	end
	p.Parent = parent
	local w = Instance.new("WeldConstraint")
	w.Part0 = parent
	w.Part1 = p
	w.Parent = p
	return p
end

-- 球的外觀：9 種球各有獨特幾何造型、專屬粒子與視覺特效
local function makeBallLook(ball: BasePart, t)
	local size = ball.Size.X
	local col = t.color
	local edgeCol = t.edge or col

	-- 1. 基礎點光源
	if t.glow and t.glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = col
		light.Brightness = t.glow * 2.2
		light.Range = size * 2.8
		light.Parent = ball
	end

	-- 2. 基礎拖尾
	if t.trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, size * 0.45, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -size * 0.45, 0)
		a1.Parent = ball
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Color = ColorSequence.new(col, edgeCol)
		tr.Lifetime = t.id == "quick" and 0.48 or 0.28
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.08),
		})
		tr.Parent = ball
	end

	-- 3. 專屬球種幾何造型與專屬粒子
	if t.id == "standard" then
		-- 【標準球】赤道霓虹光環：旋轉薄圓盤環繞
		attachVisualPart(ball, {
			Name = "BallRing",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.32, size * 1.38, size * 1.38),
			Color = edgeCol,
			Material = Enum.Material.Neon,
			Transparency = 0.25,
			CFrame = ball.CFrame * CFrame.Angles(0, 0, math.rad(90)),
		})

	elseif t.id == "heavy" then
		-- 【巨岩球】粗獷隕石刺球：6 個正交方位凸出的暗黑玄武岩稜角 + 滾動塵土
		ball.Material = Enum.Material.Slate
		local offsets = {
			Vector3.new(size * 0.42, 0, 0),
			Vector3.new(-size * 0.42, 0, 0),
			Vector3.new(0, size * 0.42, 0),
			Vector3.new(0, -size * 0.42, 0),
			Vector3.new(0, 0, size * 0.42),
			Vector3.new(0, 0, -size * 0.42),
		}
		for idx, off in ipairs(offsets) do
			attachVisualPart(ball, {
				Name = "RockSpike" .. idx,
				Shape = Enum.PartType.Block,
				Size = Vector3.new(size * 0.45, size * 0.45, size * 0.45),
				Color = Color3.fromRGB(75, 68, 62),
				Material = Enum.Material.Basalt,
				CFrame = ball.CFrame * CFrame.new(off) * CFrame.Angles(math.rad(idx * 35), math.rad(idx * 45), math.rad(idx * 25)),
			})
		end
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(110, 95, 80))
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, size * 0.7)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.4, 0.7)
		pe.Rate = 25
		pe.Speed = NumberRange.new(2, 6)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Parent = ball

	elseif t.id == "quick" then
		-- 【疾風球】風刃手裡劍：三枚 120° 旋轉的青色霓虹風刃 + 高速氣旋
		for idx = 0, 2 do
			local ang = math.rad(idx * 120)
			local cRot = CFrame.Angles(0, ang, 0)
			attachVisualPart(ball, {
				Name = "WindBlade" .. idx,
				Shape = Enum.PartType.Block,
				Size = Vector3.new(size * 0.15, size * 0.3, size * 1.6),
				Color = edgeCol,
				Material = Enum.Material.Neon,
				Transparency = 0.2,
				CFrame = ball.CFrame * cRot * CFrame.new(0, 0, size * 0.65) * CFrame.Angles(0, math.rad(25), 0),
			})
		end
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(180, 250, 255))
		pe.LightEmission = 0.9
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.3), NumberSequenceKeypoint.new(1, 0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.2, 0.35)
		pe.Rate = 50
		pe.Speed = NumberRange.new(8, 16)
		pe.SpreadAngle = Vector2.new(60, 60)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = ball

	elseif t.id == "split" then
		-- 【分裂球】聚束母體炸彈：四顆正四面體環繞懸浮的能量子核
		local dist = size * 0.68
		local subOffsets = {
			Vector3.new(dist, dist, dist).Unit * dist,
			Vector3.new(-dist, -dist, dist).Unit * dist,
			Vector3.new(-dist, dist, -dist).Unit * dist,
			Vector3.new(dist, -dist, -dist).Unit * dist,
		}
		for idx, off in ipairs(subOffsets) do
			attachVisualPart(ball, {
				Name = "SubCore" .. idx,
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size * 0.35, size * 0.35, size * 0.35),
				Color = edgeCol,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CFrame = ball.CFrame * CFrame.new(off),
			})
		end

	elseif t.id == "ghost" then
		-- 【幽靈球】幽冥魂火：外層 ForceField 靈體 + 內部紫光魂核 + 升騰魂火
		ball.Material = Enum.Material.ForceField
		ball.Transparency = 0.55
		attachVisualPart(ball, {
			Name = "SoulCore",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size * 0.55, size * 0.55, size * 0.55),
			Color = Color3.fromRGB(220, 160, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CFrame = ball.CFrame,
		})
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(200, 140, 255), Color3.fromRGB(90, 30, 180))
		pe.LightEmission = 0.85
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.45), NumberSequenceKeypoint.new(1, 0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.4, 0.7)
		pe.Rate = 35
		pe.Speed = NumberRange.new(2, 5)
		pe.Acceleration = Vector3.new(0, 14, 0)
		pe.SpreadAngle = Vector2.new(120, 120)
		pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
		pe.Parent = ball

	elseif t.id == "fire" then
		-- 【烈焰球】燃燒烈焰火球：真實 Roblox 火焰與黑煙
		local fire = Instance.new("Fire")
		fire.Size = math.clamp(size * 1.8, 6, 25)
		fire.Heat = 20
		fire.Color = Color3.fromRGB(255, 95, 20)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 60)
		fire.Parent = ball

		local smoke = Instance.new("Smoke")
		smoke.Size = math.clamp(size * 0.6, 2, 8)
		smoke.Color = Color3.fromRGB(45, 30, 25)
		smoke.Opacity = 0.35
		smoke.RiseVelocity = 6
		smoke.Parent = ball

	elseif t.id == "frost" then
		-- 【極寒球】六角冰晶彗星：6 根銳利冰晶尖刺刺穿球體 + 寒霜粒子
		ball.Material = Enum.Material.Ice
		local dirs = {
			Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0), Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
		}
		for idx, dir in ipairs(dirs) do
			attachVisualPart(ball, {
				Name = "IceSpike" .. idx,
				Shape = Enum.PartType.Block,
				Size = Vector3.new(size * 0.25, size * 0.25, size * 0.75),
				Color = Color3.fromRGB(215, 245, 255),
				Material = Enum.Material.Ice,
				Transparency = 0.2,
				CFrame = CFrame.lookAt(ball.Position + dir * (size * 0.55), ball.Position + dir * (size * 1.3)),
			})
		end
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
		pe.LightEmission = 0.7
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.2), NumberSequenceKeypoint.new(1, 0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.3, 0.6)
		pe.Rate = 40
		pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = ball

	elseif t.id == "thunder" then
		-- 【雷電球】電漿雷暴：高亮描邊 + 狂暴電火花
		local hl = Instance.new("Highlight")
		hl.Adornee = ball
		hl.FillColor = Color3.fromRGB(255, 245, 120)
		hl.FillTransparency = 0.6
		hl.OutlineColor = Color3.fromRGB(255, 255, 200)
		hl.OutlineTransparency = 0.05
		hl.Parent = ball

		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 255, 120), Color3.fromRGB(255, 200, 40))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, 0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.12, 0.28)
		pe.Rate = 70
		pe.Speed = NumberRange.new(6, 14)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = ball

	elseif t.id == "gold" then
		-- 【黃金球】神聖黃金天球：頭頂懸浮黃金天使光環 + 全身金光璀璨 + 金幣閃光
		attachVisualPart(ball, {
			Name = "GoldHalo",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.28, size * 1.25, size * 1.25),
			Color = Color3.fromRGB(255, 225, 80),
			Material = Enum.Material.Neon,
			CFrame = ball.CFrame * CFrame.new(0, size * 0.65, 0) * CFrame.Angles(math.rad(15), 0, math.rad(90)),
		})

		local hl = Instance.new("Highlight")
		hl.Adornee = ball
		hl.FillColor = Color3.fromRGB(255, 215, 0)
		hl.FillTransparency = 0.45
		hl.OutlineColor = Color3.fromRGB(255, 255, 220)
		hl.OutlineTransparency = 0.0
		hl.Parent = ball

		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 255, 220))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size * 0.28), NumberSequenceKeypoint.new(1, 0)})
		pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
		pe.Lifetime = NumberRange.new(0.35, 0.7)
		pe.Rate = 50
		pe.Speed = NumberRange.new(3, 8)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = ball
	end
end

local function createBall(t, pos: Vector3, vel: Vector3, opts: {track: boolean?, hp: number?, life: number?, mini: boolean?}?)
	local size = t.size
	if opts and opts.mini then size = t.size * 0.58 end
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(size, size, size)
	ball.Position = pos
	ball.Color = t.color
	ball.Material = t.material
	ball.Transparency = (t.alpha or 0)
	ball.CanCollide = false
	ball.Anchored = false
	ball.Name = "DodgeBall"
	tagObject(ball)
	ball:SetAttribute("KillBall", true)
	ball:SetAttribute("BallKind", t.id)
	ball:SetAttribute("BallName", t.name)
	ball:SetAttribute("BallHp", (opts and opts.hp) or t.hp or 1)
	ball:SetAttribute("Track", (opts and opts.track) or false)
	ball.Parent = workspace
	if opts and opts.mini then
		ball:SetAttribute("NoSplit", true)
		ball:SetAttribute("Mini", true)
	end

	makeBallLook(ball, t)

	-- 反重力：讓球筆直穿過場地，不會掉出世界
	local antiG = Instance.new("BodyForce")
	antiG.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity, 0)
	antiG.Parent = ball

	ball.AssemblyLinearVelocity = vel

	local spin = Instance.new("BodyAngularVelocity")
	spin.AngularVelocity = Vector3.new(math.random(-4, 4), math.random(-4, 4), math.random(-4, 4))
	spin.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
	spin.Parent = ball

	ball.Destroying:Connect(function()
		ballHitCd[ball] = nil
		reflectImmune[ball] = nil
	end)

	local dead = false
	ball.Touched:Connect(function(other)
		if dead then return end
		local hum = other.Parent and other.Parent:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local plr = Players:GetPlayerFromCharacter(other.Parent)
		if not plr then return end
		if not (roundActive and inRound[plr] and alive[plr]) then return end
		-- 剛反彈的球有短暫時間打不到反彈者
		local im = reflectImmune[ball]
		if im and im.plr == plr and os.clock() < im.exp then return end
		dead = true
		alive[plr] = false
		lastAttacker[plr] = nil :: any
		hum.Health = 0
		broadcast("killfeed", {killer = "", victim = plr.DisplayName, by = "ball"})
		ballBurst(ball.Position, t.color, size)
		if ball.Parent then ball:Destroy() end
	end)

	-- 追蹤：依球種機率轉向最近的存活玩家
	if opts and opts.track then
		local born = os.clock()
		local homing = t.homing or 0.09
		task.spawn(function()
			while ball.Parent and not dead and os.clock() - born < 7.5 do
				local noTrack = ball:GetAttribute("NoTrack")
				if not (noTrack and os.clock() < noTrack) then
					local best, bestDist = nil, math.huge
					for plr, a in pairs(alive) do
						local c = plr.Character
						local hrp = c and c:FindFirstChild("HumanoidRootPart")
						if a and hrp then
							local d = ((hrp :: BasePart).Position - ball.Position).Magnitude
							if d < bestDist then
								bestDist = d
								best = (hrp :: BasePart).Position + Vector3.new(0, 1, 0)
							end
						end
					end
					if best then
						local v = ball.AssemblyLinearVelocity
						local speed = math.max(v.Magnitude, 45)
						local dir = v.Magnitude > 1 and v.Unit or ((best :: Vector3) - ball.Position).Unit
						local desired = ((best :: Vector3) - ball.Position).Unit
						local newDir = dir:Lerp(desired, homing)
						if newDir.Magnitude < 0.05 then newDir = desired end
						ball.AssemblyLinearVelocity = newDir.Unit * speed
					end
				end
				task.wait(0.1)
			end
		end)
	end

	task.delay((opts and opts.life) or 9, function()
		if ball.Parent then ball:Destroy() end
	end)
	return ball
end

-- 砍碎後反彈：越貴的刀把球染成刀的顏色，速度也更快

-- ============================================================
-- 登頂 Roblox 第一名戰鬥核心系統：必殺能量槽、拼刀僵直、木人連擊
-- ============================================================
local ultimateCharge: {[Player]: number} = {}
local lastSlashTime: {[any]: number} = {}
local dummyHits = 0
local lastDummyHit = 0

local function chargeUltimate(plr: Player, amt: number)
	local cur = math.clamp((ultimateCharge[plr] or 0) + amt, 0, 100)
	ultimateCharge[plr] = cur
	send(plr, "ultimate_charge", cur)
end

reflectBall = function(attacker: Player?, ball: BasePart, look: Vector3, t)
	local skin = (attacker and KNIFE_BY_ID[pd(attacker).equipped]) or KNIVES[1]
	local mult = (skin.reflectMul or 1.3) * (t.reflectMul or 1.0)
	local isPerfect = false
	if attacker and attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart") then
		local hrp = attacker.Character.HumanoidRootPart :: BasePart
		local dist = (ball.Position - hrp.Position).Magnitude
		local relVel = ball.AssemblyLinearVelocity:Dot(look)
		if dist <= 14 and relVel < -0.15 then
			isPerfect = true
			mult *= 1.85 -- 完美彈反：超音速 1.85x 反彈加速度
		end
	end
	local speed = math.max(ball.AssemblyLinearVelocity.Magnitude, 55) * mult

	local dir = (look + Vector3.new(0, 0.05, 0)).Unit
	-- 特殊技能：櫻瓣追蹤 / 冥火獵犬 / 涅槃焚天 → 強制自動轉向鎖定最近對手！
	if skin.skill == "櫻瓣追蹤" or skin.skill == "冥火獵犬" or skin.skill == "涅槃焚天" then
		local best, bestDist = nil, 160
		for target, a in pairs(alive) do
			if target ~= attacker and a and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
				local d = ((target.Character.HumanoidRootPart :: BasePart).Position - ball.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = target.Character.HumanoidRootPart.Position + Vector3.new(0, 1, 0)
				end
			end
		end
		for _, bot in ipairs(activeBots) do
			if bot and bot.PrimaryPart and bot:FindFirstChild("Humanoid") and (bot.Humanoid :: Humanoid).Health > 0 then
				local d = (bot.PrimaryPart.Position - ball.Position).Magnitude
				if d < bestDist then
					bestDist = d
					best = bot.PrimaryPart.Position + Vector3.new(0, 1, 0)
				end
			end
		end
		if best then
			dir = ((best :: Vector3) - ball.Position).Unit
		end
	end

	ball.AssemblyLinearVelocity = dir * math.min(speed, 220)
	ball:SetAttribute("NoTrack", os.clock() + 2.2)
	ball:SetAttribute("Reflected", true)
	if attacker then
		reflectImmune[ball] = {plr = attacker, exp = os.clock() + 0.65}
	end
	ball.Color = skin.color
	for _, c in ipairs(ball:GetChildren()) do
		if c:IsA("PointLight") then
			c.Color = skin.color
		elseif c:IsA("Trail") then
			c.Color = ColorSequence.new(skin.color, Color3.fromRGB(255, 255, 255))
		elseif c:IsA("BasePart") then
			c.Color = skin.color
			c.Material = Enum.Material.Neon
		elseif c:IsA("Highlight") then
			c.FillColor = skin.color
			c.OutlineColor = Color3.fromRGB(255, 255, 255)
		elseif c:IsA("Fire") then
			c.Color = skin.color
			c.SecondaryColor = Color3.fromRGB(255, 255, 255)
		elseif c:IsA("ParticleEmitter") then
			c.Color = ColorSequence.new(skin.color, Color3.fromRGB(255, 255, 255))
		end
	end

	ballBurst(ball.Position, skin.color, 2.6)

	if attacker then
		local d = pd(attacker)
		local bonusCoin = isPerfect and 5 or 1
		d.coins += bonusCoin
		syncLeader(attacker)
		send(attacker, "coins", d.coins)
		chargeUltimate(attacker, isPerfect and 35 or 20)

		if isPerfect then
			send(attacker, "perfectparry", {pos = ball.Position})
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= attacker then
					send(other, "effect", {kind = "perfectparry", pos = ball.Position})
				end
			end
		end

		send(attacker, "ballhit", {
			kind = isPerfect and "perfect" or "reflect",
			pos = ball.Position,
			color = isPerfect and Color3.fromRGB(255, 220, 50) or skin.color,
			coin = bonusCoin,
			name = t.name,
			skin = skin.id,
		})
	end
end

local spawnMiniBall: (Vector3, Vector3, string, any) -> ()

breakBall = function(attacker: Player, ball: BasePart, t)
	local pos = ball.Position
	ballBurst(pos, t.color, t.size)

	-- 分裂球：砍碎後炸成兩顆小的
	if t.split and ball:GetAttribute("NoSplit") ~= true then
		local v = ball.AssemblyLinearVelocity
		local base = v.Magnitude > 5 and v.Unit or Vector3.new(0, 0, 1)
		local side = base:Cross(Vector3.new(0, 1, 0))
		if side.Magnitude < 0.01 then side = Vector3.new(1, 0, 0) end
		side = side.Unit
		spawnMiniBall(pos, (base + side * 0.95).Unit, t.id, t)
		spawnMiniBall(pos, (base - side * 0.95).Unit, t.id, t)
	end

	local coinGain = (ball:GetAttribute("Mini") == true) and 0 or (t.coin or 0)
	if attacker then
		if coinGain > 0 then
			local d = pd(attacker)
			d.coins += coinGain
			syncLeader(attacker)
			send(attacker, "coins", d.coins)
		end

		send(attacker, "ballhit", {
			kind = "destroy",
			pos = pos,
			color = t.color,
			coin = coinGain,
			name = t.name,
			skin = (KNIFE_BY_ID[pd(attacker).equipped] or KNIVES[1]).id,
		})
	end
	ball:Destroy()
end

spawnMiniBall = function(pos: Vector3, dir: Vector3, kindId: string, t)
	local mt = BALL_BY_ID[kindId] or t
	createBall(mt, pos, dir.Unit * 82, {mini = true, life = 6.5, track = false, hp = 1})
end

-- 給 knifeHit 用：扇形範圍內把球砍碎／反彈
swordSweepBalls = function(attacker: Player, look: Vector3): number
	local char = attacker.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return 0 end
	local origin = (hrp :: BasePart).Position
	local now = os.clock()
	local n = 0
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("BasePart") and obj:GetAttribute("BallKind") ~= nil then
			local ball = obj
			if (ballHitCd[ball] or 0) <= now then
				local t = BALL_BY_ID[ball:GetAttribute("BallKind") :: string]
				if t then
					local off = ball.Position - origin
					local dist = off.Magnitude
					local skin = (attacker and KNIFE_BY_ID[pd(attacker).equipped]) or KNIVES[1]
					local reach = (skin.reach or 22) + t.size * 0.8
					local maxDeflect = (skin.skill == "雙球並射" or (skin.tier or 1) >= 5) and 2 or 1
					if dist <= reach and dist > 0.01 and off.Unit:Dot(look) > -0.22 and n < maxDeflect then
						ballHitCd[ball] = now + 0.26
						n += 1
						local hp = ball:GetAttribute("BallHp")
						if typeof(hp) ~= "number" then hp = t.hp or 1 end
						if (hp :: number) > 0 then
							hp = (hp :: number) - 1
							if (hp :: number) <= 0 then
								breakBall(attacker, ball, t)
							else
								ball:SetAttribute("BallHp", hp)
								reflectBall(attacker, ball, look, t)
							end
						else
							reflectBall(attacker, ball, look, t)
						end
					end
				end
			end
		end
	end
	return n
end

spawnBall = function(kindId: string?)
	local progress = math.clamp((os.clock() - roundStartClock) / ROUND_TIME_MAX, 0, 1)
	local t = (kindId and BALL_BY_ID[kindId]) or pickBallKind(progress)

	local ang = math.rad(math.random(0, 359))
	local startR = ARENA_R + 8
	local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * startR, 3, math.sin(ang) * startR)

	-- 瞄準：依球種追蹤機率決定是否直接砸向某個存活玩家
	local aim: Vector3? = nil
	if math.random() < t.track then
		local cands = {}
		for plr, a in pairs(alive) do
			local c = plr.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if a and h then table.insert(cands, (h :: BasePart).Position) end
		end
		if #cands > 0 then aim = cands[math.random(1, #cands)] end
	end
	if not aim then
		local targAng = math.rad(math.random(0, 359))
		local targR = math.random(0, math.floor(ARENA_R * 0.5))
		aim = ARENA_CENTER + Vector3.new(math.cos(targAng) * targR, 2, math.sin(targAng) * targR)
	end
	local goal = Vector3.new((aim :: Vector3).X, 3, (aim :: Vector3).Z)
	local dir = (goal - pos).Unit
	local spd = math.random(t.spd[1], t.spd[2])

	createBall(t, pos, dir * spd, {
		track = math.random() < t.track,
		hp = t.hp,
		life = 9,
	})
end

-- ------------------------------------------------------------
-- 效果道具
-- ------------------------------------------------------------
local slowTraps: {[BasePart]: {owner: Player}} = {}

-- 減速／加速改成記時間戳，由統一的速度迴圈套用
-- （沙地慢 0.6 × 道具減速 0.45 × 疾風 1.65，全部用 SpeedMul 屬性交給動作腳本）
local function applySlow(plr: Player)
	slowUntil[plr] = os.clock() + 5
end

local function applySpeed(plr: Player)
	speedUntil[plr] = os.clock() + 6
	send(plr, "effect", {kind = "speed", t = 6})
end

local function applyFlash(plr: Player)
	send(plr, "effect", {kind = "blind", t = 4})
end

local function useItem(plr: Player, slot: number)
	local d = pd(plr)
	if not d.items[slot] then return end
	local itemId = d.items[slot]
	if not roundActive or not inRound[plr] or not alive[plr] then return end

	if itemId == "speed" then
		applySpeed(plr)
	elseif itemId == "flash" then
		local myChar = plr.Character
		local myPos = myChar and myChar:FindFirstChild("HumanoidRootPart") and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart).Position
		if myPos then
			for target in pairs(alive) do
				if target ~= plr and alive[target] then
					local tc = target.Character
					local tp = tc and tc:FindFirstChild("HumanoidRootPart")
					if tp and (tp.Position - myPos).Magnitude <= 30 then
						applyFlash(target)
					end
				end
			end
		end
		broadcast("killfeed", {killer = plr.DisplayName, victim = "使用了閃光彈！", by = "item"})
	elseif itemId == "slowtrap" then
		local myChar = plr.Character
		local myPos = myChar and myChar:FindFirstChild("HumanoidRootPart") and (myChar:FindFirstChild("HumanoidRootPart") :: BasePart).Position
		if myPos then
			local trap = Instance.new("Part")
			trap.Shape = Enum.PartType.Cylinder
			trap.Size = Vector3.new(0.4, 10, 10)
			trap.CFrame = CFrame.new(Vector3.new(myPos.X, ARENA_CENTER.Y + 0.4, myPos.Z)) * CFrame.Angles(0, 0, math.rad(90))
			trap.Color = Color3.fromRGB(150, 100, 255)
			trap.Material = Enum.Material.Neon
			trap.Anchored = true
			trap.CanCollide = false
			trap.Name = "SlowTrap"
			tagObject(trap)
			trap.Parent = workspace
			local touched = false
			trap.Touched:Connect(function(other)
				if touched then return end
				local hum = other.Parent and other.Parent:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local victim = Players:GetPlayerFromCharacter(other.Parent)
					if victim and victim ~= plr and inRound[victim] and alive[victim] then
						touched = true
						applySlow(victim)
						task.delay(0.3, function() touched = false end)
					end
				end
			end)
			task.delay(20, function()
				if trap.Parent then trap:Destroy() end
			end)
		end
	elseif itemId == "teleport" then
		local myChar = plr.Character
		local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local forward = hrp.CFrame.LookVector
			local newPos = hrp.Position + forward * 35
			local flat = Vector3.new(newPos.X - ARENA_CENTER.X, 0, newPos.Z - ARENA_CENTER.Z)
			if flat.Magnitude > ARENA_R - 6 then
				flat = flat.Unit * (ARENA_R - 8)
				newPos = ARENA_CENTER + flat + Vector3.new(0, hrp.Position.Y - ARENA_CENTER.Y, 0)
			end
			ballBurst(hrp.Position, Color3.fromRGB(100, 200, 255), 2.5)
			hrp.CFrame = CFrame.new(newPos, newPos + forward)
			ballBurst(newPos, Color3.fromRGB(100, 200, 255), 2.5)
			broadcast("killfeed", {killer = plr.DisplayName, victim = "施展了【次元瞬移】！", by = "item"})
		end
	elseif itemId == "swap" then
		local myChar = plr.Character
		local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if myHrp then
			local cands: {BasePart} = {}
			for target, a in pairs(alive) do
				if target ~= plr and a and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
					table.insert(cands, target.Character.HumanoidRootPart :: BasePart)
				end
			end
			for _, bot in ipairs(activeBots) do
				if bot and bot.PrimaryPart and bot:FindFirstChild("Humanoid") and (bot.Humanoid :: Humanoid).Health > 0 then
					table.insert(cands, bot.PrimaryPart)
				end
			end
			if #cands > 0 then
				local targetHrp = cands[math.random(1, #cands)]
				local myOldPos = myHrp.Position
				local targetOldPos = targetHrp.Position
				myHrp.CFrame = CFrame.new(targetOldPos) * myHrp.CFrame.Rotation
				targetHrp.CFrame = CFrame.new(myOldPos) * targetHrp.CFrame.Rotation
				ballBurst(myOldPos, Color3.fromRGB(255, 110, 220), 3.0)
				ballBurst(targetOldPos, Color3.fromRGB(255, 110, 220), 3.0)
				broadcast("killfeed", {killer = plr.DisplayName, victim = "發動了【乾坤大挪移】！", by = "item"})
			end
		end
	elseif itemId == "barrier" then
		local myChar = plr.Character
		local hrp = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local shield = Instance.new("Part")
			shield.Shape = Enum.PartType.Ball
			shield.Size = Vector3.new(8, 8, 8)
			shield.Color = Color3.fromRGB(255, 225, 80)
			shield.Material = Enum.Material.ForceField
			shield.CanCollide = false
			shield.Anchored = false
			shield.Massless = true
			shield.CFrame = hrp.CFrame
			shield.Parent = myChar
			local w = Instance.new("WeldConstraint")
			w.Part0 = hrp; w.Part1 = shield; w.Parent = shield
			hrp:SetAttribute("InvincibleUntil", os.clock() + 3.5)
			task.delay(3.5, function()
				if shield.Parent then shield:Destroy() end
			end)
			broadcast("killfeed", {killer = plr.DisplayName, victim = "開啟了【無敵金鐘罩】！", by = "item"})
		end
	end

	table.remove(d.items, slot)
	send(plr, "items", d.items)
end

-- ------------------------------------------------------------
-- 盒子（隨機出現，開出效果道具）
-- ------------------------------------------------------------
spawnBox = function()
	-- 避開紅色方塊：落地點壓在方塊上/裡面就換位置（最多試 12 次，不行就放場中央）
	local pos: Vector3? = nil
	for _ = 1, 12 do
		local ang = math.rad(math.random(0, 359))
		local rr = math.random(10, ARENA_R - 12)
		local cand = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, 0, math.sin(ang) * rr)
		local clear = true
		for _, b in ipairs(arenaBlocks) do
			local flat = Vector3.new(cand.X - b.c.X, 0, cand.Z - b.c.Z)
			if flat.Magnitude < b.half + 3.5 then
				clear = false
				break
			end
		end
		if clear then
			pos = cand
			break
		end
	end
	pos = pos or (ARENA_CENTER + Vector3.new(0, 0, 0))
	local spawnPos = pos + Vector3.new(0, 2, 0)

	local box = Instance.new("Part")
	box.Size = Vector3.new(3.4, 3.4, 3.4)
	box.Position = spawnPos
	box.Color = Color3.fromRGB(255, 215, 60)
	box.Material = Enum.Material.Neon
	box.Anchored = true
	box.CanCollide = true
	box.Name = "MysteryBox"
	tagObject(box)
	box.Parent = workspace

	local hl = Instance.new("Highlight")
	hl.Adornee = box
	hl.FillColor = Color3.fromRGB(255, 220, 80)
	hl.FillTransparency = 0.5
	hl.OutlineColor = Color3.fromRGB(255, 255, 220)
	hl.OutlineTransparency = 0
	hl.Parent = box

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 230, 100), Color3.fromRGB(255, 255, 220))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0)})
	pe.Lifetime = NumberRange.new(0.35, 0.75)
	pe.Rate = 22
	pe.Speed = NumberRange.new(2, 5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Parent = box

	-- 掉落與平滑旋轉浮動動畫
	box.CFrame = CFrame.new(spawnPos + Vector3.new(0, 14, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
	TweenService:Create(box, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {CFrame = CFrame.new(spawnPos) * box.CFrame.Rotation}):Play()

	task.spawn(function()
		local t0 = os.clock()
		while box.Parent do
			task.wait(0.04)
			local elapsed = os.clock() - t0
			box.CFrame = CFrame.new(spawnPos + Vector3.new(0, math.sin(elapsed * 2.5) * 0.45, 0)) * CFrame.Angles(0, elapsed * 1.6, 0)
		end
	end)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 225, 120); light.Range = 16; light.Brightness = 2.4
	light.Parent = box

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "開啟"; prompt.ObjectText = "神秘盒子"; prompt.HoldDuration = 0.3
	prompt.Parent = box

	local opened = false
	prompt.Triggered:Connect(function(plr)
		if opened then return end
		if not (roundActive and inRound[plr] and alive[plr]) then return end
		opened = true
		local d = pd(plr)
		if #d.items >= 2 then
			-- 欄位滿：直接換成金幣
			d.coins += 30
			syncLeader(plr)
			send(plr, "coins", d.coins)
			send(plr, "toast", "欄位已滿，盒子變成 ¥30！")
		else
			local it = ITEMS[math.random(1, #ITEMS)]
			table.insert(d.items, it.id)
			send(plr, "itemget", {id = it.id, name = it.name, desc = it.desc, color = it.color, items = d.items})
		end
		-- 開箱特效
		local e = Instance.new("Explosion")
		e.Position = box.Position; e.BlastRadius = 0; e.BlastPressure = 0
		e.Parent = workspace
		box:Destroy()
	end)

	task.delay(25, function()
		if box.Parent then box:Destroy() end
	end)
end

-- ------------------------------------------------------------
-- 掉出場外即死（掉出競技場／大廳，碰到最底下的海面或掉進虚空都算）
-- ------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.15)
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if h and hrp and h.Health > 0 then
				-- 場中玩家：低於競技場 30 格就死（海面在 -60）；大廳玩家：低於大廳 35 格就死
				local limit = (inRound[plr] and alive[plr]) and (ARENA_CENTER.Y - 30) or (LOBBY_CENTER.Y - 35)
				if hrp.Position.Y < limit then
					local wasInRound = inRound[plr] and alive[plr]
					h.Health = 0
					if wasInRound then
						alive[plr] = false
						lastAttacker[plr] = nil :: any
						broadcast("killfeed", {killer = "", victim = plr.DisplayName, by = "fall"})
					end
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- 統一速度控制：地板效果（沙地慢）× 道具減速 × 疾風藥水 → SpeedMul 屬性
-- ------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.15)
		local now = os.clock()
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then
				local mul = 1
				if roundActive and inRound[plr] and alive[plr] then
					local f = FLOORS[MAPS[currentMap].floor]
					if f.speedMul then mul = f.speedMul end
				end
				if (slowUntil[plr] or 0) > now then mul *= 0.45 end
				if (speedUntil[plr] or 0) > now then mul *= 1.65 end
				if h:GetAttribute("SpeedMul") ~= mul then
					h:SetAttribute("SpeedMul", mul)
				end
			end
		end
	end
end)

-- ------------------------------------------------------------
-- 回合流程
-- ------------------------------------------------------------
local function teleportToArena(plr: Player, i: number)
	local char = plr.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hrp and hum and hum.Health > 0 then
		local ang = math.rad(i * (360 / math.max(playerCount(), 1)))
		local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * 35, 4, math.sin(ang) * 35)
		char:PivotTo(CFrame.new(pos))
		hum.WalkSpeed = 16
	end
end

local function startRound()
	roundActive = true
	roundStartClock = os.clock()
	inRound = {}
	alive = {}
	lastAttacker = {}
	roundTag += 1
	clearRoundObjects()

	-- 統計大廳投票（限本輪 3 張候選）→ 得票最高的地圖（平手隨機）；沒人投就候選裡隨機一張
	local tally: {[number]: number} = {}
	local voterCount = 0
	for plr, idx in pairs(votes) do
		if plr.Parent and table.find(mapCandidates, idx) then
			tally[idx] = (tally[idx] or 0) + 1
			voterCount += 1
		end
	end
	if voterCount > 0 then
		local best: {number} = {}
		local bestN = 0
		for idx, n in pairs(tally) do
			if n > bestN then
				bestN = n
				best = {idx}
			elseif n == bestN then
				table.insert(best, idx)
			end
		end
		currentMap = best[math.random(1, #best)]
	else
		currentMap = mapCandidates[math.random(1, #mapCandidates)]
	end
	buildArena(currentMap)
	broadcast("mapinfo", MAPS[currentMap].name)
	table.clear(votes)
	pickCandidates()   -- 換下一組 3 張候選，讓下一輪大廳投票用

	local i = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if spectating[plr] then continue end   -- 按了「不參加」→ 留在大廳
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			hum.Health = hum.MaxHealth
		end
		i += 1
		inRound[plr] = true
		alive[plr] = true
	end
	if i == 0 then
		broadcast("winner", "大家都沒參加，這回合跳過 😴")
		roundActive = false
		return
	end
	task.wait(0.4)
	local pIdx = 0
	for plr in pairs(inRound) do
		pIdx += 1
		teleportToArena(plr, pIdx)
		giveKnife(plr)
	end

	setStatus("存活: " .. i .. " 人")

	-- 單人或人數不足 4 人時自動加入 AI 機器人陪玩
	clearBots()
	if i < 4 then
		local neededBots = math.clamp(4 - i, 1, 3)
		for bIdx = 1, neededBots do
			local ang = math.rad((i + bIdx) * (360 / (i + neededBots)))
			local bSpawn = ARENA_CENTER + Vector3.new(math.cos(ang) * (ARENA_R - 18), 3, math.sin(ang) * (ARENA_R - 18))
			spawnBot(bIdx, bSpawn)
		end
	end

	local startCount = i
	local elapsed = 0.0
	local nextBall = 2.0
	local nextBox = 6.0

	while roundActive do
		task.wait(0.25)
		elapsed += 0.25

		-- 出球（越到後面越密集，後期還會一次兩顆）
		nextBall -= 0.25
		if nextBall <= 0 then
			spawnBall()
			local progress = math.min(elapsed / ROUND_TIME_MAX, 1)
			local k = 1 - 0.65 * progress   -- 間隔從 3~5.5 秒 漸縮到約 1~1.9 秒
			if progress >= 0.35 and math.random() < 0.45 then
				spawnBall()                 -- 後期 45% 機率雙發
			end
			if progress >= 0.7 and math.random() < 0.3 then
				spawnBall()                 -- 尾聲偶爾三連發
			end
			nextBall = (BALL_EVERY[1] + math.random() * (BALL_EVERY[2] - BALL_EVERY[1])) * k
		end
		-- 出盒子
		nextBox -= 0.25
		if nextBox <= 0 then
			spawnBox()
			nextBox = BOX_EVERY[1] + math.random() * (BOX_EVERY[2] - BOX_EVERY[1])
		end

		-- 數存活（包含玩家與 AI 武者）
		local n = 0
		local lastPlr: Player? = nil
		for plr, a in pairs(alive) do
			if a and plr.Parent then
				n += 1
				lastPlr = plr
			end
		end
		local botCount = 0
		for _, b in ipairs(activeBots) do
			if b and b.Parent and b:FindFirstChild("Humanoid") and (b.Humanoid :: Humanoid).Health > 0 then
				botCount += 1
			end
		end
		local totalAlive = n + botCount
		local initialTotal = startCount + math.max(4 - startCount, 0)
		local timeUp = elapsed >= ROUND_TIME_MAX
		if (n == 0) or (totalAlive <= 1 and initialTotal > 1) or timeUp then
			-- 回合結束：判定唯一的最終大贏家！
			local winnerPlr: Player? = nil
			if n == 1 then
				for p, a in pairs(alive) do
					if a and p.Parent then
						winnerPlr = p
						break
					end
				end
			elseif n > 1 and timeUp then
				-- 超時則選取血量最多的存活玩家為唯一贏家
				local bestHp = -1
				for p, a in pairs(alive) do
					if a and p.Character and p.Character:FindFirstChild("Humanoid") then
						local hp = (p.Character.Humanoid :: Humanoid).Health
						if hp > bestHp then
							bestHp = hp
							winnerPlr = p
						end
					end
				end
			end

			if winnerPlr then
				local d = pd(winnerPlr)
				d.coins += COIN_WIN
				syncLeader(winnerPlr)
				send(winnerPlr, "coins", d.coins)
				broadcast("winner", "👑 " .. winnerPlr.DisplayName .. " 勇奪本局唯一總冠軍！ (+" .. COIN_WIN .. " 金幣)")
			elseif totalAlive == 1 and botCount == 1 then
				broadcast("winner", "⚔️ AI 頂級武者技高一籌，奪得本局冠軍！")
			else
				broadcast("winner", "無人存活…本回合平局")
			end
			roundActive = false
		else
			setStatus("存活: " .. totalAlive .. " 人")
		end
	end

	-- 贏家誕生後迅速 (1.4 秒) 直接將全體玩家傳送回典雅豪氣大廳，絕不在戰鬥地圖逗留！
	task.wait(1.4)
	for _, plr in ipairs(Players:GetPlayers()) do
		inRound[plr] = false
		alive[plr] = false
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and hum and hum.Health > 0 then
			char:PivotTo(CFrame.new(LOBBY_CENTER + Vector3.new(0, 4, 0)))
			hum.Health = hum.MaxHealth
		end
	end
	roundTag += 1
	clearRoundObjects()
end

task.spawn(function()
	while true do
		-- 等人
		while playerCount() < MIN_PLAYERS do
			setStatus("等待玩家 (" .. playerCount() .. "/" .. MIN_PLAYERS .. ")")
			task.wait(1)
		end
		for t = INTERMISSION, 1, -1 do
			setStatus("遊戲開始倒數: " .. t .. " 秒")
			task.wait(1)
		end
		startRound()
		task.wait(2)
	end
end)

-- ------------------------------------------------------------
-- 遠端事件處理
-- ------------------------------------------------------------
Net.OnServerEvent:Connect(function(plr: Player, msg: any)
	if type(msg) ~= "table" then return end
	local act = msg.act
	local d = pd(plr)

	if act == "spectate" then
		spectating[plr] = msg.on and true or nil
	elseif act == "buynife" then
		local id = tostring(msg.id)
		local skin = KNIFE_BY_ID[id]
		if skin and not d.owned[id] and d.coins >= skin.price then
			d.coins -= skin.price
			d.owned[id] = true
			d.equipped = id
			syncLeader(plr)
			send(plr, "shopdata", {coins = d.coins, owned = d.owned, equipped = d.equipped, knives = KNIVES})
		end
	elseif act == "equipnife" then
		local id = tostring(msg.id)
		if KNIFE_BY_ID[id] and d.owned[id] then
			d.equipped = id
			send(plr, "shopdata", {coins = d.coins, owned = d.owned, equipped = d.equipped, knives = KNIVES})
		end
	elseif act == "gacha" then
		if d.coins >= GACHA_COST then
			d.coins -= GACHA_COST
			-- 加權隨機
			local total = 0
			for _, g in ipairs(GACHA_POOL) do total += g.w end
			local roll = math.random() * total
			local picked = GACHA_POOL[1].id
			for _, g in ipairs(GACHA_POOL) do
				roll -= g.w
				if roll <= 0 then
					picked = g.id
					break
				end
			end
			local dup = d.owned[picked] == true
			if dup then
				d.coins += GACHA_DUP_REFUND
			else
				d.owned[picked] = true
			end
			syncLeader(plr)
			send(plr, "gacharesult", {knife = KNIFE_BY_ID[picked], dup = dup, coins = d.coins})
		else
			send(plr, "toast", "金幣不足！抽獎需要 ¥" .. GACHA_COST)
		end
	elseif act == "useitem" then
		useItem(plr, tonumber(msg.slot) or 1)
	elseif act == "openshop" then
		send(plr, "shopdata", {coins = d.coins, owned = d.owned, equipped = d.equipped, knives = KNIVES})
	elseif act == "ultimate" then
		if (ultimateCharge[plr] or 0) >= 100 then
			ultimateCharge[plr] = 0
			send(plr, "ultimate_charge", 0)

			local ch = plr.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hrp then
				-- 2.5 秒金色無敵
				hrp:SetAttribute("InvincibleUntil", os.clock() + 2.5)

				-- 全場廣播必殺大絕特效與震盪
				broadcast("ultimate_burst", {pos = hrp.Position, user = plr.DisplayName})

				-- 震飛引爆半徑 35 格內全部躲避球
				for _, b in ipairs(balls) do
					if b and b.Parent and (b.Position - hrp.Position).Magnitude <= 35 then
						local outDir = (b.Position - hrp.Position).Unit
						if outDir.Magnitude < 0.1 then outDir = hrp.CFrame.LookVector end
						b.AssemblyLinearVelocity = (outDir + Vector3.new(0, 0.15, 0)).Unit * 220
						ballBurst(b.Position, Color3.fromRGB(255, 200, 40), 3.2)
					end
				end

				-- 震飛波及周圍對手與機器人（35 傷害＋18格強擊退）
				for target in pairs(alive) do
					if target ~= plr and alive[target] then
						local tChar = target.Character
						local tHrp = tChar and tChar:FindFirstChild("HumanoidRootPart") :: BasePart?
						local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
						if tHrp and tHum and (tHrp.Position - hrp.Position).Magnitude <= 30 then
							local kDir = (tHrp.Position - hrp.Position).Unit
							tHrp.AssemblyLinearVelocity = kDir * 55 + Vector3.new(0, 22, 0)
							tHum:TakeDamage(35)
							send(target, "hurt", {dmg = 35, attacker = plr.DisplayName .. " [必殺]"})
						end
					end
				end
				for _, bot in ipairs(activeBots) do
					if bot and bot.PrimaryPart and (bot.PrimaryPart.Position - hrp.Position).Magnitude <= 30 then
						local bHum = bot:FindFirstChildOfClass("Humanoid")
						if bHum then
							local kDir = (bot.PrimaryPart.Position - hrp.Position).Unit
							bot.PrimaryPart.AssemblyLinearVelocity = kDir * 55 + Vector3.new(0, 22, 0)
							bHum:TakeDamage(35)
						end
					end
				end
			end
		end
	elseif act == "claimdaily" then
		local today = math.floor(os.time() / 86400)
		if today > (d.lastClaimDay or 0) then
			local REWARDS = {50, 100, 200, 350, 500, 750, 1500}
			local day = math.clamp(d.loginStreak or 1, 1, 7)
			local award = REWARDS[day] or 100
			d.coins += award
			d.lastClaimDay = today
			if day == 7 then
				d.owned["phoenix"] = true
				send(plr, "toast", "🔥 登頂大獎！獲得第7日專屬神話刀【鳳凰】＋1500金幣！")
			else
				send(plr, "toast", "🎉 簽到成功！領取第 " .. day .. " 天福利：+" .. award .. " 金幣！")
			end
			d.loginStreak = (d.loginStreak % 7) + 1
			save(plr)
			syncLeader(plr)
			send(plr, "coins", d.coins)
			send(plr, "daily_status", {
				streak = d.loginStreak,
				canClaim = false,
				day = math.clamp(d.loginStreak, 1, 7),
			})
		end
	end
end)

-- 大廳互動提示
lobbyRefs.shopPrompt.Triggered:Connect(function(plr)
	send(plr, "openshop", nil)
end)
lobbyRefs.gachaPrompt.Triggered:Connect(function(plr)
	send(plr, "opengacha", nil)
end)

-- ------------------------------------------------------------
-- 排行榜更新
-- ------------------------------------------------------------

print("[Dodgeball] 伺服器已啟動")

-- ------------------------------------------------------------
-- 角色動作系統（CharacterMovesClient）的 F 攻擊
-- → 走同一套刀判定：同一個冷卻、同樣 20 傷害、擊殺照樣算給攻擊者
-- ------------------------------------------------------------
task.spawn(function()
	local cm = ReplicatedStorage:WaitForChild("CharacterMoves", 30)
	if not cm then
		warn("[Dodgeball] 找不到 CharacterMoves 資料夾 → F 攻擊不會扣血（請確認 CharacterMovesServer 在 ServerScriptService）")
		return
	end
	local ev = cm:WaitForChild("KnifeHit", 30)
	if not ev then
		warn("[Dodgeball] 找不到 CharacterMoves.KnifeHit → F 攻擊不會扣血")
		return
	end
	;(ev :: BindableEvent).Event:Connect(function(who: any)
		local plr = who :: Player
		if typeof(plr) == "Instance" and plr:IsA("Player") then
			knifeHit(plr)
		end
	end)
	print("[Dodgeball] 已接上 CharacterMoves 的 F 攻擊 ✔")
end)

