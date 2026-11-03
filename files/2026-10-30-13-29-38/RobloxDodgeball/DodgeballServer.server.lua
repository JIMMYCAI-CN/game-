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
	{id = "steel",     name = "鋼鐵",     price = 0,    tier = 1, color = Color3.fromRGB(190, 195, 205)},
	{id = "obsidian",  name = "黑曜石",   price = 250,  tier = 2, color = Color3.fromRGB(35, 30, 45)},
	{id = "thunder",   name = "雷霆",     price = 400,  tier = 3, color = Color3.fromRGB(90, 150, 255)},
	{id = "sakura",    name = "櫻花",     price = 600,  tier = 4, color = Color3.fromRGB(255, 170, 200)},
	{id = "frost",     name = "冰霜",     price = 800,  tier = 4, color = Color3.fromRGB(160, 230, 255)},
	{id = "astra",     name = "阿斯特拉", price = 1200, tier = 5, color = Color3.fromRGB(120, 255, 180)},
	{id = "hydra",     name = "九頭蛇",   price = 1600, tier = 5, color = Color3.fromRGB(110, 220, 90)},
	{id = "blueflame", name = "藍焰",     price = 2000, tier = 6, color = Color3.fromRGB(60, 160, 255)},
	{id = "phoenix",   name = "鳳凰",     price = 3000, tier = 6, color = Color3.fromRGB(255, 120, 40)},
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
	{id = "flash",    name = "閃光彈",   desc = "讓附近的敵人失明 4 秒",         color = Color3.fromRGB(255, 240, 150)},
	{id = "speed",    name = "疾風藥水", desc = "自己加速 6 秒",                 color = Color3.fromRGB(120, 255, 160)},
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

-- ------------------------------------------------------------
-- RemoteEvent（單一通道，act 欄位區分動作）
-- ------------------------------------------------------------
local Net = Instance.new("RemoteEvent")
Net.Name = "DodgeNet"
Net.Parent = ReplicatedStorage

local function send(plr: Player, act: string, data: any?)
	Net:FireClient(plr, {act = act, data = data})
end
local function broadcast(act: string, data: any?)
	Net:FireAllClients({act = act, data = data})
end

-- ------------------------------------------------------------
-- 玩家資料（含簡單雲存檔）
-- ------------------------------------------------------------
type PD = {coins: number, kills: number, owned: {[string]: boolean}, equipped: string, items: {string}}
local pData: {[Player]: PD} = {}

local function defaultData(): PD
	return {coins = 250, kills = 0, owned = {steel = true}, equipped = "steel", items = {}}
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
	end
	pData[plr] = d
end

local function save(plr: Player)
	local d = pData[plr]
	if not d or not STORE then return end
	pcall(function()
		STORE:SetAsync("u_" .. plr.UserId, {coins = d.coins, kills = d.kills, owned = d.owned, equipped = d.equipped})
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
	local island = Instance.new("Model")
	island.Name = "Lobby"

	-- 島體（下面泥土層）
	part({Name = "Grass", Size = Vector3.new(96, 2, 96), Position = LOBBY_CENTER, Color = Color3.fromRGB(106, 168, 79), Material = Enum.Material.Grass}, island)
	part({Name = "Dirt", Size = Vector3.new(88, 10, 88), Position = LOBBY_CENTER - Vector3.new(0, 5.5, 0), Color = Color3.fromRGB(120, 85, 60), Material = Enum.Material.Slate}, island)
	-- 木頭甲板
	part({Name = "Deck", Size = Vector3.new(60, 0.4, 34), Position = LOBBY_CENTER + Vector3.new(0, 1, 14), Color = Color3.fromRGB(160, 120, 80), Material = Enum.Material.WoodPlanks}, island)

	-- 鳥居（紅色大門，裝飾）
	local gate = Instance.new("Model"); gate.Name = "Torii"; gate.Parent = island
	local gC = LOBBY_CENTER + Vector3.new(0, 0, -40)
	part({Size = Vector3.new(2, 22, 2), Position = gC + Vector3.new(-10, 11, 0), Color = Color3.fromRGB(200, 40, 40), Material = Enum.Material.SmoothPlastic}, gate)
	part({Size = Vector3.new(2, 22, 2), Position = gC + Vector3.new(10, 11, 0), Color = Color3.fromRGB(200, 40, 40), Material = Enum.Material.SmoothPlastic}, gate)
	part({Size = Vector3.new(30, 2.4, 3), Position = gC + Vector3.new(0, 22, 0), Color = Color3.fromRGB(200, 40, 40), Material = Enum.Material.SmoothPlastic}, gate)
	part({Size = Vector3.new(34, 1.6, 2.4), Position = gC + Vector3.new(0, 24.6, 0), Color = Color3.fromRGB(30, 30, 30), Material = Enum.Material.SmoothPlastic}, gate)

	-- 軍械庫（有匯入的「武器庫」模型就用模型，否則積木版櫃檯）
	local shopC = LOBBY_CENTER + Vector3.new(-22, 0, 20)
	local shop = Instance.new("Model"); shop.Name = "KnifeShop"; shop.Parent = island
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.ActionText = "買刀"; shopPrompt.ObjectText = "軍械庫"; shopPrompt.HoldDuration = 0
	local armoryTpl = findModelTemplate({"武器庫", "armory", "arsenal"})
	if armoryTpl then
		local m = placeModel(armoryTpl, shopC, 13, math.rad(200))
		if m then m.Name = "ArmoryModel"; m.Parent = shop end
		-- 隱形互動區（掛提示用）
		local hitbox = part({Size = Vector3.new(11, 9, 9), Position = shopC + Vector3.new(0, 4.5, 3), Transparency = 1, CanCollide = false}, shop)
		shopPrompt.Parent = hitbox
		-- 招牌照舊掛高一點
		local shopSign = part({Size = Vector3.new(8, 2.4, 0.4), Position = shopC + Vector3.new(0, 15, 0), Color = Color3.fromRGB(60, 40, 30)}, shop)
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(400, 120); sg.Parent = shopSign
		local st = Instance.new("TextLabel"); st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
		st.Text = "⚔ 軍械庫"; st.TextScaled = true; st.TextColor3 = Color3.fromRGB(255, 215, 90); st.Font = Enum.Font.SourceSansBold; st.Parent = sg
	else
		-- 積木版軍械庫：攤位造型（屋頂＋支柱＋後牆武器架＋展示刀＋櫃檯）
		-- 後牆＋武器架
		part({Size = Vector3.new(12, 6.5, 0.8), Position = shopC + Vector3.new(0, 3.25, -3), Color = Color3.fromRGB(105, 75, 45), Material = Enum.Material.WoodPlanks}, shop)
		for i = 0, 2 do
			local kx = -3.4 + i * 3.4
			part({Size = Vector3.new(0.22, 2.8, 0.7), Position = shopC + Vector3.new(kx, 4.7, -2.45), Color = Color3.fromRGB(205, 210, 220), Material = Enum.Material.Metal, CanCollide = false}, shop)
			part({Size = Vector3.new(0.34, 1, 0.45), Position = shopC + Vector3.new(kx, 2.9, -2.45), Color = Color3.fromRGB(90, 55, 30), CanCollide = false}, shop)
			part({Size = Vector3.new(0.7, 0.18, 0.9), Position = shopC + Vector3.new(kx, 3.45, -2.45), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Metal, CanCollide = false}, shop)
		end
		-- 櫃檯＋桌腳
		part({Size = Vector3.new(12, 1, 6), Position = shopC + Vector3.new(0, 3, 0), Color = Color3.fromRGB(140, 100, 60), Material = Enum.Material.Wood}, shop)
		part({Size = Vector3.new(1.2, 3, 1.2), Position = shopC + Vector3.new(-5.4, 1.5, -2.5), Color = Color3.fromRGB(90, 65, 40)}, shop)
		part({Size = Vector3.new(1.2, 3, 1.2), Position = shopC + Vector3.new(5.4, 1.5, -2.5), Color = Color3.fromRGB(90, 65, 40)}, shop)
		part({Size = Vector3.new(1.2, 3, 1.2), Position = shopC + Vector3.new(-5.4, 1.5, 2.5), Color = Color3.fromRGB(90, 65, 40)}, shop)
		part({Size = Vector3.new(1.2, 3, 1.2), Position = shopC + Vector3.new(5.4, 1.5, 2.5), Color = Color3.fromRGB(90, 65, 40)}, shop)
		-- 屋頂（兩片斜板）
		part({Size = Vector3.new(13, 0.6, 7.5), CFrame = CFrame.new(shopC + Vector3.new(0, 8.2, -1.2)) * CFrame.Angles(math.rad(-14), 0, 0), Color = Color3.fromRGB(150, 60, 50), Material = Enum.Material.WoodPlanks}, shop)
		-- 櫃檯上的小刀（展示）
		part({Size = Vector3.new(0.2, 0.3, 2.2), CFrame = CFrame.new(shopC + Vector3.new(-2.5, 3.75, 0.5)) * CFrame.Angles(0, math.rad(20), 0), Color = Color3.fromRGB(205, 210, 220), Material = Enum.Material.Metal, CanCollide = false}, shop)
		part({Size = Vector3.new(0.2, 0.3, 2.2), CFrame = CFrame.new(shopC + Vector3.new(2.2, 3.75, -0.3)) * CFrame.Angles(0, math.rad(-35), 0), Color = Color3.fromRGB(205, 210, 220), Material = Enum.Material.Metal, CanCollide = false}, shop)
		-- 招牌
		local shopSign = part({Size = Vector3.new(8, 2.4, 0.4), Position = shopC + Vector3.new(0, 11.2, 0), Color = Color3.fromRGB(60, 40, 30)}, shop)
		local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Front; sg.CanvasSize = Vector2.new(400, 120); sg.Parent = shopSign
		local st = Instance.new("TextLabel"); st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
		st.Text = "⚔ 軍械庫"; st.TextScaled = true; st.TextColor3 = Color3.fromRGB(255, 215, 90); st.Font = Enum.Font.SourceSansBold; st.Parent = sg
		shopPrompt.Parent = shopSign
	end

	-- 抽獎機（扭蛋機；有匯入的「搖蛋機」模型就用模型）
	local gachaC = LOBBY_CENTER + Vector3.new(0, 0, 26)
	local gacha = Instance.new("Model"); gacha.Name = "Gacha"; gacha.Parent = island
	local gachaPrompt = Instance.new("ProximityPrompt")
	gachaPrompt.ActionText = "抽獎 (¥" .. GACHA_COST .. ")"; gachaPrompt.ObjectText = "幸運扭蛋"; gachaPrompt.HoldDuration = 0
	local gachaTpl = findModelTemplate({"搖蛋機", "扭蛋機", "gachapon", "gachamachine"})
	if gachaTpl then
		local m = placeModel(gachaTpl, gachaC, 11, math.rad(180))
		if m then m.Name = "GachaModel"; m.Parent = gacha end
		local hitbox = part({Size = Vector3.new(8, 10, 7), Position = gachaC + Vector3.new(0, 5, 2.5), Transparency = 1, CanCollide = false}, gacha)
		gachaPrompt.Parent = hitbox
	else
		local body = part({Size = Vector3.new(6, 8, 5), Position = gachaC + Vector3.new(0, 4, 0), Color = Color3.fromRGB(230, 80, 120), Material = Enum.Material.SmoothPlastic}, gacha)
		part({Size = Vector3.new(5, 3, 1), Position = gachaC + Vector3.new(0, 5.5, 2.7), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Glass, Transparency = 0.4}, gacha)
		-- 裡面的彩球
		math.randomseed(os.clock())
		for i = 1, 6 do
			part({Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2),
				Position = gachaC + Vector3.new(-1.6 + (i % 3) * 1.6, 5 + (math.floor((i - 1) / 3)) * 1.3, 2.9),
				Color = Color3.fromHSV(math.random(), 0.8, 1), Material = Enum.Material.Neon, CanCollide = false}, gacha)
		end
		gachaPrompt.Parent = body
	end

	-- 金幣裝飾（散在甲板和草地上）
	for i = 1, 16 do
		local ang = math.rad(i * 137.5)
		local rr = 7 + (i * 7.3) % 30
		local cx, cz = math.cos(ang) * rr, math.sin(ang) * rr
		local onDeck = (math.abs(cx) < 29 and cz > -2 and cz < 30)
		local cy = onDeck and 1.48 or 1.08
		part({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 1.7, 1.7),
			CFrame = CFrame.new(LOBBY_CENTER + Vector3.new(cx, cy, cz)) * CFrame.Angles(math.rad(90), math.rad(i * 53), 0),
			Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.SmoothPlastic, CanCollide = false}, island)
	end

	-- 樹（裝飾，避開地圖選擇板區域）
	for i = 1, 7 do
		local ang = math.rad(i * 51 + 12)
		local rr = 34 + (i * 5.7) % 8
		local tx, tz = math.cos(ang) * rr, math.sin(ang) * rr
		if not (tz < 6 and math.abs(tx) < 34) then
			part({Size = Vector3.new(2.4, 9, 2.4), Position = LOBBY_CENTER + Vector3.new(tx, 5.5, tz),
				Color = Color3.fromRGB(110, 70, 40), Material = Enum.Material.Wood}, island)
			part({Shape = Enum.PartType.Ball, Size = Vector3.new(9.5, 9.5, 9.5), Position = LOBBY_CENTER + Vector3.new(tx, 11.5, tz),
				Color = Color3.fromRGB(70, 160, 70), Material = Enum.Material.Grass}, island)
			part({Shape = Enum.PartType.Ball, Size = Vector3.new(6.5, 6.5, 6.5), Position = LOBBY_CENTER + Vector3.new(tx + 2.8, 9.2, tz - 2.2),
				Color = Color3.fromRGB(84, 178, 84), Material = Enum.Material.Grass}, island)
			part({Shape = Enum.PartType.Ball, Size = Vector3.new(5.5, 5.5, 5.5), Position = LOBBY_CENTER + Vector3.new(tx - 2.6, 9.8, tz + 2.4),
				Color = Color3.fromRGB(60, 145, 60), Material = Enum.Material.Grass}, island)
		end
	end

	-- 使用者擺的裝飾模型：排行榜台、桌子、憤怒鳥家族 → 擺進大廳
	local deco = game:GetService("ServerStorage"):FindFirstChild("LobbyDeco")
	if deco then
		local function put(nm: string, pos: Vector3, h: number?, yaw: number?)
			local tpl = deco:FindFirstChild(nm)
			if tpl then
				local m = placeModel(tpl :: Model, pos, h or 0, yaw or 0)
				if m then m.Name = nm; m.Parent = island end
			end
		end
		put("排行台", LOBBY_CENTER + Vector3.new(25, 1.4, 31), 0, math.rad(-56))
		put("桌子", LOBBY_CENTER + Vector3.new(12, 1.4, 12), 0, math.rad(15))
		-- 沙發（甲板兩側，面向地圖投票板）＋可以坐的座位
		local sofaLong = nil
		local sofaLove = nil
		do
			local tplL = deco and deco:FindFirstChild("沙發長")
			if tplL then
				sofaLong = placeModel(tplL :: Model, LOBBY_CENTER + Vector3.new(-14, 1.4, 5), 0, math.rad(0))
				if sofaLong then sofaLong.Name = "沙發長"; sofaLong.Parent = island end
			end
			local tplV = deco and deco:FindFirstChild("沙發雙人")
			if tplV then
				sofaLove = placeModel(tplV :: Model, LOBBY_CENTER + Vector3.new(14, 1.4, 5), 0, math.rad(0))
				if sofaLove then sofaLove.Name = "沙發雙人"; sofaLove.Parent = island end
			end
		end
		local function addSeats(m: Model?, n: number)
			if not m then return end
			local cf, sz = m:GetBoundingBox()
			for i = 1, n do
				local s = Instance.new("Seat")
				s.Size = Vector3.new(2.4, 0.4, 2.2)
				s.Anchored = true
				s.CanCollide = false
				s.Transparency = 1
				local offX = (i - (n + 1) / 2) * 2.7
				s.CFrame = cf * CFrame.new(offX, sz.Y / 2 - 1.6, -0.2)
				s.Parent = m
			end
		end
		addSeats(sofaLong, 3)
		addSeats(sofaLove, 2)
		-- 固定鳥／豬：拉開彼此距離，並記錄位置供隨機鳥避讓
		local placedPts: {Vector3} = {}
		local function putSpread(nm: string, off: Vector3, yaw: number, h: number?)
			put(nm, LOBBY_CENTER + off, h or 0, yaw)
			table.insert(placedPts, Vector3.new(off.X, 0, off.Z))
		end
		putSpread("裝飾鳥Red", Vector3.new(-28, 1.4, 12), math.rad(160))
		putSpread("裝飾鳥Chuck", Vector3.new(-21, 1.4, 17), math.rad(140))
		putSpread("裝飾鳥Blues", Vector3.new(-33, 1.4, 3), math.rad(180))
		putSpread("裝飾豬", Vector3.new(16, 1, 38), math.rad(210))
		putSpread("裝飾豬小", Vector3.new(11, 1, 39), math.rad(230))
		-- 再隨機多放一批鳥鴨豬：彼此最小間距 8 防穿模，並補足大門側（z 負區）
		local birdNames = {"裝飾鳥Red", "裝飾鳥Chuck", "裝飾鳥Blues", "裝飾豬", "裝飾豬小"}
		local avoid = {
			{c = Vector3.new(0, 0, 8), r = 8},     -- 出生點
			{c = Vector3.new(0, 0, 26), r = 7},    -- 扭蛋機
			{c = Vector3.new(-22, 0, 20), r = 9},  -- 軍械庫
			{c = Vector3.new(25, 0, 31), r = 13},  -- 排行台
			{c = Vector3.new(12, 0, 12), r = 7},   -- 桌子
			{c = Vector3.new(-14, 0, 5), r = 8},   -- 沙發長
			{c = Vector3.new(14, 0, 5), r = 8},    -- 沙發雙人
			{c = Vector3.new(0, 0, -40), r = 10},  -- 大門本體
		}
		math.randomseed(os.clock())
		local placedBirds = 0
		local guard = 0
		while placedBirds < 14 and guard < 240 do
			guard += 1
			local bx: number, bz: number
			if math.random() < 0.45 then
				-- 大門側：地圖板平台（z -35~+2, |x|<33）以外或大門前草地
				bx = (math.random() * 2 - 1) * 38
				bz = -6 - math.random() * 34
			else
				local ang = math.rad(math.random() * 360)
				local rr = 14 + math.random() * 26
				bx, bz = math.cos(ang) * rr, math.sin(ang) * rr
			end
			if math.abs(bx) < 42 and math.abs(bz) < 42
				and not (bz > -35 and bz < 4 and math.abs(bx) < 33) then   -- 避開地圖板平台
				local ok = true
				for _, a2 in ipairs(avoid) do
					if (Vector3.new(bx, 0, bz) - a2.c).Magnitude < a2.r then ok = false break end
				end
				if ok then
					for _, p2 in ipairs(placedPts) do
						if (Vector3.new(bx, 0, bz) - p2).Magnitude < 8 then ok = false break end
					end
				end
				if ok then
					local nm = birdNames[math.random(1, #birdNames)]
					local tpl = deco:FindFirstChild(nm)
					if tpl then
						local onDeck = (math.abs(bx) < 29 and bz > -2 and bz < 30)
						local m = placeModel(tpl :: Model, LOBBY_CENTER + Vector3.new(bx, onDeck and 1.4 or 1, bz), 0, math.rad(math.random() * 360))
						if m then m.Name = "隨機裝飾" .. placedBirds; m.Parent = island; placedBirds += 1; table.insert(placedPts, Vector3.new(bx, 0, bz)) end
					end
				end
			end
		end
	end

	-- 出生點
	local sp = Instance.new("SpawnLocation")
	sp.Size = Vector3.new(12, 1, 12); sp.Position = LOBBY_CENTER + Vector3.new(0, 0.9, 8)
	sp.Anchored = true; sp.Neutral = true; sp.Color = Color3.fromRGB(255, 210, 80); sp.Material = Enum.Material.Neon
	sp.Parent = island

	-- 島邊圍欄（防止掉下去）
	local edge = 46
	for i, off in ipairs({Vector3.new(0, 0, -edge), Vector3.new(0, 0, edge), Vector3.new(-edge, 0, 0), Vector3.new(edge, 0, 0)}) do
		local horizontal = (i <= 2)
		part({Size = Vector3.new(horizontal and 94 or 2, 6, horizontal and 2 or 94),
			Position = LOBBY_CENTER + off + Vector3.new(0, 4.5, 0),
			Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.Wood, Transparency = 0.5, CanCollide = true}, island)
	end

	-- 三位製作人的真人 NPC（抓 Roblox 頭像外觀），站出生點後方一排，放大 1.4 倍
	task.spawn(function()
		local npcC = LOBBY_CENTER
		local face = npcC + Vector3.new(0, 2, 8)   -- 面向出生點
		local defs = {
			{name = "jimmycai27", label = "製作人 jimmy", off = Vector3.new(-7, 1.4, 12)},
			{name = "leo5546668ddddd", label = "製作人 leo", off = Vector3.new(0, 1.4, 15)},
			{name = "noobKeb", label = "製作人 noob", off = Vector3.new(7, 1.4, 12)},
		}
		for _, def in ipairs(defs) do
			local okNpc, errNpc = pcall(function()
				local uid = Players:GetUserIdFromNameAsync(def.name)
				local desc = Players:GetHumanoidDescriptionFromUserId(uid)
				-- 注意：ApplyDescription 在某些頭像設定下會靜默失敗（只留 R15 貼圖不留零件），
				-- 一定要用 CreateHumanoidModelFromDescription 直接建整隻模型
				local m = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
				m.Name = "NPC_" .. def.name
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
					-- 原生頭頂名字（Roblox 官方顯示機制，雙保險）
					hum.DisplayName = def.label
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
					hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
				end
				m:PivotTo(CFrame.lookAt(npcC + def.off + Vector3.new(0, 4.3, 0), face))
				m.Parent = workspace
				-- 名牌
				local head = m:FindFirstChild("Head")
				if head then
					local bb = Instance.new("BillboardGui")
					bb.Name = "NameTag"
					bb.Size = UDim2.new(0, 280, 0, 64)
					bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
					bb.AlwaysOnTop = true
					bb.MaxDistance = 500
					bb.LightInfluence = 0
					bb.Parent = head
					local tl = Instance.new("TextLabel")
					tl.Size = UDim2.new(1, 0, 1, 0)
					tl.BackgroundTransparency = 1
					tl.Text = def.label
					tl.TextColor3 = Color3.fromRGB(255, 230, 120)
					tl.TextStrokeTransparency = 0.3
					tl.TextScaled = true
					tl.Font = Enum.Font.SourceSansBold
					tl.Parent = bb
				end
			end)
			if not okNpc then
				warn("[Dodgeball] NPC " .. def.name .. " 生成失敗: " .. tostring(errNpc))
			end
		end
	end)

	island.Parent = workspace
	return {shopPrompt = shopPrompt, gachaPrompt = gachaPrompt}
end

-- ------------------------------------------------------------
-- 使用者在 Studio 裡擺放的模型 → 開服時收進 ServerStorage 當模板，再由 buildLobby 擺進大廳
-- ------------------------------------------------------------
local function adoptUserModels()
	local SS = game:GetService("ServerStorage")
	local deco = SS:FindFirstChild("LobbyDeco") :: Folder
	if not deco then
		deco = Instance.new("Folder")
		deco.Name = "LobbyDeco"
		deco.Parent = SS
	end
	local function adopt(model: Instance?, newName: string)
		if model and model.Parent then
			model.Name = newName
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true end
			end
			model.Parent = deco
		end
	end
	-- 扭蛋機：使用者擺的未命名模型，特徵是裡面有大量 DecorBall
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("Model") and d.Name == "Model" then
			local balls = 0
			for _, p in ipairs(d:GetDescendants()) do
				if p.Name == "DecorBall" then balls += 1 end
			end
			if balls >= 20 then
				adopt(d, "搖蛋機")
				break
			end
		end
	end
	-- 其餘照名字認養
	-- 其餘照名字認養（桌上的茶杯順便改成「杯子」，當散落裝飾的模板）
	local tbl = workspace:FindFirstChild("Table")
	if tbl then
		local tea = tbl:FindFirstChild("Tea")
		if tea then tea.Name = "杯子" end
	end
	adopt(workspace:FindFirstChild("RankBoardModel"), "排行台")
	adopt(tbl, "桌子")
	-- 沙發兩張（長沙髮是未命名 Model 內含 Sofa；雙人沙發叫 Loveseat_Dark stone grey）
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("Model") and d.Name == "Model" and d:FindFirstChild("Sofa") then
			adopt(d, "沙發長")
			break
		end
	end
	adopt(workspace:FindFirstChild("Loveseat_Dark stone grey"), "沙發雙人")
	adopt(workspace:FindFirstChild("Red"), "裝飾鳥Red")
	adopt(workspace:FindFirstChild("Chuck the Angry Bird"), "裝飾鳥Chuck")
	adopt(workspace:FindFirstChild("The Blues"), "裝飾鳥Blues")
	adopt(workspace:FindFirstChild("Minion Pig"), "裝飾豬")
	adopt(workspace:FindFirstChild("pig bored"), "裝飾豬小")
end
adoptUserModels()

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
			Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon})
	end
	-- 圓形的霓虹外圈
	if shape == 1 then
		pp({Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, ARENA_R * 2 * s + 0.5, ARENA_R * 2 * s + 0.5),
			CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(255, 140, 40), Material = Enum.Material.Neon})
	end
	-- 幾顆紅色方塊示意高點
	for i = 1, 4 do
		local ang = math.rad(i * 90 + math.random(-20, 20))
		local rr = aIn * 0.8 * s * (0.2 + math.random() * 0.8)
		pp({Size = Vector3.new(0.7, 0.5 + math.random() * 0.6, 0.7),
			Position = center + Vector3.new(math.cos(ang) * rr, 0.5, math.sin(ang) * rr),
			Color = Color3.fromRGB(190, 40, 50), Material = Enum.Material.SmoothPlastic})
	end
	m.Parent = workspace
	return m
end

local boardC = LOBBY_CENTER + Vector3.new(0, 0, -16)
local padY = LOBBY_CENTER.Y + 1.55
local PAD_HALF_X, PAD_HALF_Z = 6, 5

local function buildMapBoard()
	-- 木框平台
	part({Size = Vector3.new(60, 0.4, 34), Position = boardC + Vector3.new(0, 1.2, 0),
		Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.WoodPlanks})
	part({Size = Vector3.new(62, 1.2, 36), Position = boardC + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood})

	-- 標題（面向玩家走過來的方向：+Z，用 Back 面）
	local sign = part({Size = Vector3.new(24, 3.4, 0.6), Position = boardC + Vector3.new(0, 5.2, -16.2),
		Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Wood})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(700, 100); sg.Parent = sign
	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
	st.Text = "🗺 地圖三選一：從 15 張隨機抽 3 張，站上去投票"
	st.TextColor3 = Color3.fromRGB(255, 215, 90); st.TextScaled = true
	st.Font = Enum.Font.SourceSansBold; st.Parent = sg

	-- 3 塊投票板（站上去投票）＋ 後方立式告示牌（名字＋票數）
	for k = 1, 3 do
		local px = -14 + (k - 1) * 14
		local pad = part({Size = Vector3.new(12, 0.35, 10),
			Position = Vector3.new(boardC.X + px, padY, boardC.Z + 3),
			Color = Color3.fromRGB(90, 90, 100), Material = Enum.Material.SmoothPlastic})
		-- 霓虹描邊
		part({Size = Vector3.new(12.6, 0.2, 10.6),
			Position = Vector3.new(boardC.X + px, padY - 0.2, boardC.Z + 3),
			Color = Color3.fromRGB(255, 160, 50), Material = Enum.Material.Neon, CanCollide = false})
		-- 立式告示牌（Front = -Z，玩家從 +Z 過來 → 用 Back 面才正著看）
		local sp = part({Size = Vector3.new(12, 3.2, 0.5),
			Position = Vector3.new(boardC.X + px, padY + 2.1, boardC.Z + 3 - 6.2),
			Color = Color3.fromRGB(35, 35, 45), Material = Enum.Material.SmoothPlastic})
		local pg = Instance.new("SurfaceGui")
		pg.Face = Enum.NormalId.Back; pg.CanvasSize = Vector2.new(480, 130); pg.Parent = sp
		local lb = Instance.new("TextLabel")
		lb.Size = UDim2.new(1, -8, 1, -8); lb.Position = UDim2.new(0, 4, 0, 4)
		lb.BackgroundColor3 = Color3.fromRGB(20, 20, 30); lb.BackgroundTransparency = 0.15
		lb.TextColor3 = Color3.new(1, 1, 1); lb.TextScaled = true
		lb.Font = Enum.Font.SourceSansBold
		lb.Text = ""
		lb.Parent = pg
		table.insert(mapPads, {pad = pad, sign = lb, idx = -1, preview = nil :: any})
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
		mp.sign.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
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

-- 站上哪塊板就投那張地圖（每 0.3 秒偵測一次）
task.spawn(function()
	while true do
		task.wait(0.3)
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < LOBBY_CENTER.Y + 12 and math.abs(hrp.Position.Z - (LOBBY_CENTER.Z - 16)) < 20 then
				for _, mp in ipairs(mapPads) do
					if mp.idx >= 1 then
						local p = mp.pad.Position
						if math.abs(hrp.Position.X - p.X) <= PAD_HALF_X and math.abs(hrp.Position.Z - p.Z) <= PAD_HALF_Z
							and hrp.Position.Y > p.Y - 1 and hrp.Position.Y < p.Y + 8 then
							if votes[plr] ~= mp.idx then
								votes[plr] = mp.idx
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

	-- 紅色方塊（18 塊、散更開、階梯式高度：矮→高互相接得上，可一路跳上最高點）
	local blockR = aIn * 0.9
	local minGap = math.max(7.5, math.sqrt(blockR * blockR * math.pi / 18) * 0.92)
	arenaBlocks = {}
	local placed: {Vector3} = {}
	local attempts = 0
	while #placed < 18 and attempts < 600 do
		attempts += 1
		local ang = math.rad(math.random() * 360)
		local rr = blockR * (0.15 + math.random() * 0.85)
		if rr < 9 then rr = 9 + math.random() * 4 end   -- 別壓在出生區
		local pos = Vector3.new(math.cos(ang) * rr, 0, math.sin(ang) * rr)
		local ok = true
		for _, q in ipairs(placed) do
			if (q - pos).Magnitude < minGap then ok = false break end
		end
		if ok then
			table.insert(placed, pos)
			local tier = (#placed - 1) % 4                     -- 0~3：四段階梯高度
			local h = 2.5 + tier * 1.7 + math.random() * 1.2   -- 約 2.5 ~ 8.4
			local w = 6 + math.random() * 3
			part({Size = Vector3.new(w, h, w),
				Position = ARENA_CENTER + pos + Vector3.new(0, h / 2, 0),
				Color = Color3.fromRGB(190, 40, 50), Material = Enum.Material.SmoothPlastic}, arena)
			table.insert(arenaBlocks, {c = ARENA_CENTER + pos, half = w / 2, top = h})
		end
	end

	-- 邊緣柱子（圓形 8 支、多邊形照頂點數、星星 5 支）
	local pillarCount = (shape == 1 and 8) or (shape == 2 and 4) or (shape == 3 and 3) or 5
	for i = 0, pillarCount - 1 do
		local ang = math.rad(i * (360 / pillarCount))
		part({Size = Vector3.new(4, 16, 4),
			Position = ARENA_CENTER + Vector3.new(math.cos(ang) * (ARENA_R - 4), 8, math.sin(ang) * (ARENA_R - 4)),
			Color = Color3.fromRGB(45, 35, 50), Material = Enum.Material.Slate}, arena)
	end

	-- 四周浮空石（裝飾）
	for i = 1, 14 do
		local ang = math.rad(i * 25.7)
		local rr = ARENA_R + math.random(20, 70)
		part({Shape = Enum.PartType.Ball, Size = Vector3.new(math.random(6, 14), math.random(6, 14), math.random(6, 14)),
			Position = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, math.random(-30, 5), math.sin(ang) * rr),
			Color = Color3.fromRGB(70, 60, 80), Material = Enum.Material.Slate}, arena)
	end

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
local spectating: {[Player]: boolean} = {}   -- 玩家按「不參加」→ 本回合不傳送進場
local lastAttacker: {[Player]: Player} = {}
local roundTag = 0

-- 清掉上一回合留下的球／盒子／陷阱（全部直接掛在 Workspace 上，用屬性標記）
local function clearRoundObjects()
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
local function makeKnifeTool(skinId: string): Tool
	local skin = KNIFE_BY_ID[skinId] or KNIVES[1]
	local tier = skin.tier or 1
	local tool = Instance.new("Tool")
	tool.Name = skin.name .. "之刀"
	tool.ToolTip = "左鍵／F 揮刀：砍人 5 下倒，也能把球砍碎或反彈"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- 把皮膚資訊帶給客戶端（揮刀特效用）
	tool:SetAttribute("Skin", skin.id)
	tool:SetAttribute("Tier", tier)
	tool:SetAttribute("BladeColor", skin.color)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.34, 2.2, 0.34)
	handle.Color = Color3.fromRGB(62, 62, 68)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false

	local function weldBits(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = a
	end

	-- 握把（黑）
	local grip = Instance.new("Part")
	grip.Name = "GripDeco"
	grip.Size = Vector3.new(0.42, 1.1, 0.42)
	grip.Color = Color3.fromRGB(30, 30, 32)
	grip.Material = Enum.Material.Rubber
	grip.CanCollide = false
	grip.CFrame = handle.CFrame * CFrame.new(0, -0.75, 0)
	weldBits(handle, grip)
	grip.Parent = tool

	-- 刀身：越貴越長越亮
	local bladeLen = 2.3 + tier * 0.22
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.12, bladeLen, 0.6 + tier * 0.05)
	blade.Color = skin.color
	blade.Material = (tier >= 4) and Enum.Material.Neon or Enum.Material.Metal
	blade.CanCollide = false
	blade.CFrame = handle.CFrame * CFrame.new(0, 1.0 + bladeLen / 2, 0)
	weldBits(handle, blade)
	blade.Parent = tool

	-- 刃口白光（tier 3 起）
	if tier >= 3 then
		local edge = Instance.new("Part")
		edge.Name = "Edge"
		edge.Size = Vector3.new(0.17, bladeLen * 0.94, 0.09)
		edge.Color = Color3.new(1, 1, 1):Lerp(skin.color, 0.35)
		edge.Material = Enum.Material.Neon
		edge.CanCollide = false
		edge.CFrame = blade.CFrame * CFrame.new(0, 0, -(blade.Size.Z / 2))
		weldBits(blade, edge)
		edge.Parent = tool
	end

	-- 護手（tier 2 起）
	if tier >= 2 then
		local guard = Instance.new("Part")
		guard.Name = "Guard"
		guard.Size = Vector3.new(0.86 + tier * 0.03, 0.15, 0.34)
		guard.Color = skin.color
		guard.Material = Enum.Material.Metal
		guard.CanCollide = false
		guard.CFrame = handle.CFrame * CFrame.new(0, 1.0, 0)
		weldBits(handle, guard)
		guard.Parent = tool
	end

	-- 高階刀自體發光
	if tier >= 6 then
		local light = Instance.new("PointLight")
		light.Color = skin.color
		light.Brightness = 1.5
		light.Range = 9
		light.Parent = blade
	end

	handle.Parent = tool
	tool.Grip = CFrame.new(0, 0.78, 0) * CFrame.Angles(math.rad(-8), 0, math.rad(-10))
	return tool
end

local swingCd: {[Player]: number} = {}

-- 球的判定寫在下方「球」段落，這裡先宣告再由那裡指派
local swordSweepBalls: ((Player, Vector3) -> number)?

local function knifeHit(attacker: Player)
	if not roundActive or not inRound[attacker] or not alive[attacker] then return end
	local now = os.clock()
	if (swingCd[attacker] or 0) > now then return end
	swingCd[attacker] = now + 0.42

	local char = attacker.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local look = hrp.CFrame.LookVector

	-- 通知客戶端播揮刀特效（滑鼠左鍵與 F 鍵都走這裡，F 鍵也能有滿特效）
	local equipId = pd(attacker).equipped
	local equipSkin = KNIFE_BY_ID[equipId] or KNIVES[1]
	send(attacker, "swing", {skin = equipSkin.id, tier = equipSkin.tier or 1})

	-- 讓其他玩家也看得到刀光
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= attacker then
			send(other, "swingfx", {userId = attacker.UserId, skin = equipSkin.id, tier = equipSkin.tier or 1})
		end
	end

	-- 砍人
	for target in pairs(alive) do
		if target ~= attacker and alive[target] then
			local tchar = target.Character
			local thrp = tchar and (tchar:FindFirstChild("HumanoidRootPart") :: BasePart?)
			local thum = tchar and (tchar:FindFirstChild("Humanoid") :: Humanoid?)
			if thrp and thum and thum.Health > 0 then
				local off = thrp.Position - hrp.Position
				if off.Magnitude <= 7 then
					local dir = off.Unit
					if look:Dot(dir) > 0.35 then
						lastAttacker[target] = attacker
						thum:TakeDamage(KNIFE_DMG)
						send(attacker, "hitsuccess", nil)
						send(target, "hurt", nil)
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
local function giveKnife(plr: Player)
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
		size = 5.4, spd = {86, 112}, track = 0.80, homing = 0.13, hp = 1, coin = 5,
		weight = 9, from = 0.28, glow = 1.0, material = Enum.Material.Neon, trail = true, spark = true,
	},
	{
		id = "gold", name = "黃金球", color = Color3.fromRGB(255, 200, 60), edge = Color3.fromRGB(255, 250, 200),
		size = 5.0, spd = {42, 58}, track = 0.45, homing = 0.06, hp = 2, coin = 40,
		weight = 4, from = 0.32, glow = 1.2, material = Enum.Material.Neon, trail = true, spark = true,
	},
}

local BALL_BY_ID = {}
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
local function ballBurst(pos: Vector3, color: Color3, scale: number)
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
local function makeBallLook(ball: BasePart, t)
	if t.glow and t.glow > 0 then
		local light = Instance.new("PointLight")
		light.Color = t.color
		light.Brightness = t.glow * 2.2
		light.Range = t.size * 2.6
		light.Parent = ball
	end
	if t.trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, t.size * 0.42, 0)
		a0.Parent = ball
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -t.size * 0.42, 0)
		a1.Parent = ball
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Color = ColorSequence.new(t.color, t.edge)
		tr.Lifetime = 0.32
		tr.Texture = ""
		tr.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		tr.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.12),
		})
		tr.Parent = ball
	end
	if t.spark then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(t.edge, t.color)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, t.size * 0.22),
			NumberSequenceKeypoint.new(1, 0),
		})
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Lifetime = NumberRange.new(0.25, 0.55)
		pe.Rate = 45
		pe.Speed = NumberRange.new(1, 4)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, -12, 0)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Parent = ball
	end
end

-- 建立一顆球（真正的物理與判定）
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
local function reflectBall(attacker: Player, ball: BasePart, look: Vector3, t)
	local speed = math.max(ball.AssemblyLinearVelocity.Magnitude, 55) * (t.reflectMul or 1.3)
	local dir = (look + Vector3.new(0, 0.05, 0)).Unit
	ball.AssemblyLinearVelocity = dir * math.min(speed, 195)
	ball:SetAttribute("NoTrack", os.clock() + 1.6)
	ball:SetAttribute("Reflected", true)
	reflectImmune[ball] = {plr = attacker, exp = os.clock() + 0.55}

	local skin = KNIFE_BY_ID[pd(attacker).equipped] or KNIVES[1]
	ball.Color = skin.color
	for _, c in ipairs(ball:GetChildren()) do
		if c:IsA("PointLight") then
			c.Color = skin.color
		elseif c:IsA("Trail") then
			c.Color = ColorSequence.new(skin.color, Color3.fromRGB(255, 255, 255))
		end
	end

	ballBurst(ball.Position, skin.color, 2.6)

	local d = pd(attacker)
	d.coins += 1
	send(attacker, "coins", d.coins)
	send(attacker, "ballhit", {
		kind = "reflect",
		pos = ball.Position,
		color = skin.color,
		coin = 1,
		name = t.name,
		skin = skin.id,
	})
end

local spawnMiniBall: (Vector3, Vector3, string, any) -> ()

local function breakBall(attacker: Player, ball: BasePart, t)
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
					local reach = 9.0 + t.size * 0.45
					if dist <= reach and dist > 0.01 and off.Unit:Dot(look) > 0.12 then
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

local function spawnBall(kindId: string?)
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
	end

	table.remove(d.items, slot)
	send(plr, "items", d.items)
end

-- ------------------------------------------------------------
-- 盒子（隨機出現，開出效果道具）
-- ------------------------------------------------------------
local function spawnBox()
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
	box.Size = Vector3.new(3, 3, 3)
	box.Position = spawnPos
	box.Color = Color3.fromRGB(255, 200, 60)
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = true
	box.Name = "MysteryBox"
	tagObject(box)
	box.Parent = workspace

	-- 掉落動畫
	box.CFrame = CFrame.new(spawnPos + Vector3.new(0, 14, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
	TweenService:Create(box, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {CFrame = CFrame.new(spawnPos) * box.CFrame.Rotation}):Play()

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 100); light.Range = 14; light.Brightness = 2
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
		local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * (ARENA_R - 12), 5, math.sin(ang) * (ARENA_R - 12))
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
		i += 1
		inRound[plr] = true
		alive[plr] = true
		plr:LoadCharacter()
	end
	if i == 0 then
		broadcast("winner", "大家都沒參加，這回合跳過 😴")
		roundActive = false
		return
	end
	task.wait(1)
	i = 0
	for plr in pairs(inRound) do
		i += 1
		teleportToArena(plr, i)
		giveKnife(plr)
	end

	setStatus("存活: " .. i .. " 人")

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

		-- 數存活
		local n = 0
		local lastPlr: Player? = nil
		for plr, a in pairs(alive) do
			if a and plr.Parent then
				n += 1
				lastPlr = plr
			end
		end
		local timeUp = elapsed >= ROUND_TIME_MAX
		if (n == 0) or (n <= 1 and startCount > 1) or timeUp then
			-- 回合結束
			if n >= 1 then
				-- 有存活者：時間到（含單人測試撐完）→ 全部存活者拿獎勵
				for winner in pairs(alive) do
					if alive[winner] and winner.Parent then
						local d = pd(winner)
						d.coins += COIN_WIN
						syncLeader(winner)
						send(winner, "coins", d.coins)
						broadcast("winner", winner.DisplayName .. " 獲勝！ +" .. COIN_WIN)
					end
				end
				if not timeUp and n == 1 then
					-- 正常決出最後一人（已在上面發過獎勵）
				end
			else
				broadcast("winner", "無人存活…")
			end
			roundActive = false
		else
			setStatus("存活: " .. n .. " 人")
		end
	end

	task.wait(4)
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

