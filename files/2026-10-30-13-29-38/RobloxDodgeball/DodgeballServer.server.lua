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
local KNIVES = {
	{id = "steel",   name = "鋼鐵",   price = 0,    color = Color3.fromRGB(190, 195, 205)},
	{id = "obsidian",name = "黑曜石", price = 250,  color = Color3.fromRGB(35, 30, 45)},
	{id = "thunder", name = "雷霆",   price = 400,  color = Color3.fromRGB(90, 150, 255)},
	{id = "sakura",  name = "櫻花",   price = 600,  color = Color3.fromRGB(255, 170, 200)},
	{id = "frost",   name = "冰霜",   price = 800,  color = Color3.fromRGB(160, 230, 255)},
	{id = "astra",   name = "阿斯特拉", price = 1200, color = Color3.fromRGB(120, 255, 180)},
	{id = "hydra",   name = "九頭蛇", price = 1600, color = Color3.fromRGB(110, 220, 90)},
	{id = "blueflame",name = "藍焰",  price = 2000, color = Color3.fromRGB(60, 160, 255)},
	{id = "phoenix", name = "鳳凰",   price = 3000, color = Color3.fromRGB(255, 120, 40)},
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

-- ============================================================
--  光影與氛圍：黃昏金光 + 大氣霧 + 泛光 + 色彩分級
--  所有效果都用 pcall 保護，避免舊版 Studio 不支援時整個腳本掛掉
-- ============================================================
local Lighting = game:GetService("Lighting")

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
-- 大廳（圓形浮空島：草皮＋岩層＋石板路＋櫻花樹＋燈籠＋鳥居＋軍械庫＋抽獎機）
-- ------------------------------------------------------------
local LOBBY_CENTER = Vector3.new(0, 50, 0)

-- 清掉範本預設的 Baseplate / 舊出生點，避免玩家出生在下面的平台
for _, nm in ipairs({"Baseplate", "SpawnLocation"}) do
	local obj = workspace:FindFirstChild(nm)
	if obj then obj:Destroy() end
end

-- 小工具：圓盤（軸向朝上）
local function disc(pos: Vector3, diameter: number, thick: number, props: {[string]: any}, parent: Instance)
	local t = {}
	for k, v in pairs(props) do t[k] = v end
	t.Shape = Enum.PartType.Cylinder
	t.Size = Vector3.new(thick, diameter, diameter)
	t.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	return part(t, parent)
end

-- 小工具：燈籠柱
local function lanternPost(pos: Vector3, parent: Instance, col: Color3)
	part({Size = Vector3.new(1.2, 11, 1.2), Position = pos + Vector3.new(0, 5.5, 0),
		Color = Color3.fromRGB(78, 52, 38), Material = Enum.Material.Wood}, parent)
	part({Size = Vector3.new(4.6, 0.5, 0.5), Position = pos + Vector3.new(0, 10.6, 0),
		Color = Color3.fromRGB(78, 52, 38), Material = Enum.Material.Wood}, parent)
	local lamp = part({Size = Vector3.new(2.1, 2.6, 2.1), Position = pos + Vector3.new(0, 9.1, 0),
		Color = col, Material = Enum.Material.Neon, Transparency = 0.12}, parent)
	local cap = part({Size = Vector3.new(2.6, 0.4, 2.6), Position = pos + Vector3.new(0, 10.4, 0),
		Color = Color3.fromRGB(40, 32, 28), Material = Enum.Material.Metal}, parent)
	part({Size = Vector3.new(3, 0.4, 3), Position = pos + Vector3.new(0, 7.7, 0),
		Color = Color3.fromRGB(40, 32, 28), Material = Enum.Material.Metal}, parent)
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 22
	light.Brightness = 1.6
	light.Shadows = true
	light.Parent = lamp
	return lamp
end

-- 小工具：櫻花樹
local function sakuraTree(pos: Vector3, scale: number, parent: Instance)
	local trunkH = 13 * scale
	part({Size = Vector3.new(2.4, trunkH, 2.4) * Vector3.new(1, 1, 1),
		Position = pos + Vector3.new(0, trunkH / 2, 0),
		Color = Color3.fromRGB(96, 66, 58), Material = Enum.Material.Wood}, parent)
	-- 三根分枝
	for i = 1, 3 do
		local ang = math.rad(i * 120 + 25)
		local arm = part({Size = Vector3.new(1.1, 6.5, 1.1),
			Position = pos + Vector3.new(math.cos(ang) * 2.6 * scale, trunkH * 0.78, math.sin(ang) * 2.6 * scale),
			Color = Color3.fromRGB(96, 66, 58), Material = Enum.Material.Wood}, parent)
		arm.CFrame = CFrame.new(arm.Position) * CFrame.Angles(math.rad(28), ang, 0)
	end
	-- 花冠：多顆粉球堆疊
	local crownY = pos.Y + trunkH + 2
	for i = 1, 9 do
		local ang = math.rad(i * 40)
		local rr = (i == 1) and 0 or (2.6 + (i % 3) * 1.6) * scale
		local hh = (i == 1) and 2.4 or ((i % 2 == 0) and 1.0 or 3.2) * scale
		local s = (i == 1) and 7.5 or (4.2 + (i % 3) * 0.9)
		local blob = part({Shape = Enum.PartType.Ball, Size = Vector3.new(s, s * 0.86, s) * scale,
			Position = Vector3.new(pos.X + math.cos(ang) * rr, crownY + hh, pos.Z + math.sin(ang) * rr),
			Color = Color3.fromRGB(255, 182, 205),
			Material = Enum.Material.SmoothPlastic, CanCollide = false}, parent)
		blob.Reflectance = 0.03
	end
end

local function buildLobby()
	local island = Instance.new("Model")
	island.Name = "Lobby"

	-- 島體：分層圓盤（上窄下更窄，像浮空岩塊）
	disc(LOBBY_CENTER + Vector3.new(0, -0.6, 0), 106, 4,
		{Name = "Grass", Color = Color3.fromRGB(104, 156, 78), Material = Enum.Material.Grass}, island)
	disc(LOBBY_CENTER + Vector3.new(0, -5.5, 0), 100, 7,
		{Name = "Soil", Color = Color3.fromRGB(96, 72, 54), Material = Enum.Material.Ground}, island)
	disc(LOBBY_CENTER + Vector3.new(0, -11.5, 0), 84, 6,
		{Name = "Rock1", Color = Color3.fromRGB(74, 66, 72), Material = Enum.Material.Rock}, island)
	disc(LOBBY_CENTER + Vector3.new(0, -17, 0), 62, 6,
		{Name = "Rock2", Color = Color3.fromRGB(58, 52, 60), Material = Enum.Material.Rock}, island)
	disc(LOBBY_CENTER + Vector3.new(0, -22.5, 0), 36, 6,
		{Name = "Rock3", Color = Color3.fromRGB(44, 40, 48), Material = Enum.Material.Basalt}, island)

	-- 中央石板廣場 + 通往地圖板的步道
	disc(LOBBY_CENTER + Vector3.new(0, 1.6, 2), 40, 0.5,
		{Color = Color3.fromRGB(150, 146, 140), Material = Enum.Material.Cobblestone}, island)
	for i = 0, 7 do
		part({Size = Vector3.new(9, 0.5, 4.2),
			Position = LOBBY_CENTER + Vector3.new(0, 1.65, 8 + i * 4.4),
			Color = (i % 2 == 0) and Color3.fromRGB(158, 152, 144) or Color3.fromRGB(138, 133, 126),
			Material = Enum.Material.Cobblestone}, island)
	end

	-- 木頭甲板（抽獎機前）
	part({Name = "Deck", Size = Vector3.new(34, 0.5, 20), Position = LOBBY_CENTER + Vector3.new(0, 1.7, 24),
		Color = Color3.fromRGB(164, 124, 82), Material = Enum.Material.WoodPlanks}, island)

	-- 鳥居（紅色大門）
	local gate = Instance.new("Model"); gate.Name = "Torii"; gate.Parent = island
	local gC = LOBBY_CENTER + Vector3.new(0, 0, -34)
	part({Size = Vector3.new(2.2, 24, 2.2), Position = gC + Vector3.new(-11, 12, 0), Color = Color3.fromRGB(196, 46, 44), Material = Enum.Material.Wood}, gate)
	part({Size = Vector3.new(2.2, 24, 2.2), Position = gC + Vector3.new(11, 12, 0), Color = Color3.fromRGB(196, 46, 44), Material = Enum.Material.Wood}, gate)
	part({Size = Vector3.new(32, 2.6, 3.2), Position = gC + Vector3.new(0, 24, 0), Color = Color3.fromRGB(196, 46, 44), Material = Enum.Material.Wood}, gate)
	part({Size = Vector3.new(36, 1.8, 2.6), Position = gC + Vector3.new(0, 26.8, 0), Color = Color3.fromRGB(38, 34, 34), Material = Enum.Material.Slate}, gate)
	part({Size = Vector3.new(26, 1.4, 2), Position = gC + Vector3.new(0, 21.2, 0), Color = Color3.fromRGB(196, 46, 44), Material = Enum.Material.Wood}, gate)
	-- 鳥居匾額
	local plaque = part({Size = Vector3.new(7, 3, 0.6), Position = gC + Vector3.new(0, 22.6, 1.2),
		Color = Color3.fromRGB(28, 24, 26), Material = Enum.Material.Wood}, gate)
	local pg = Instance.new("SurfaceGui"); pg.Face = Enum.NormalId.Front; pg.CanvasSize = Vector2.new(280, 120); pg.Parent = plaque
	local pt = Instance.new("TextLabel"); pt.Size = UDim2.new(1, 0, 1, 0); pt.BackgroundTransparency = 1
	pt.Text = "躲避球刺客"; pt.TextColor3 = Color3.fromRGB(255, 214, 120); pt.TextScaled = true
	pt.Font = Enum.Font.SourceSansBold; pt.Parent = pg

	-- 軍械庫小屋
	local shopC = LOBBY_CENTER + Vector3.new(-26, 0, 16)
	local shop = Instance.new("Model"); shop.Name = "KnifeShop"; shop.Parent = island
	part({Size = Vector3.new(18, 0.6, 12), Position = shopC + Vector3.new(0, 1.9, 0), Color = Color3.fromRGB(120, 92, 66), Material = Enum.Material.WoodPlanks}, shop)
	part({Size = Vector3.new(18, 8, 1), Position = shopC + Vector3.new(0, 6, -5.6), Color = Color3.fromRGB(104, 76, 52), Material = Enum.Material.WoodPlanks}, shop)
	part({Size = Vector3.new(1, 8, 12), Position = shopC + Vector3.new(-8.6, 6, 0), Color = Color3.fromRGB(96, 70, 48), Material = Enum.Material.WoodPlanks}, shop)
	part({Size = Vector3.new(1, 8, 12), Position = shopC + Vector3.new(8.6, 6, 0), Color = Color3.fromRGB(96, 70, 48), Material = Enum.Material.WoodPlanks}, shop)
	-- 斜屋頂（兩片）
	for s, dir in ipairs({-1, 1}) do
		local roof = part({Size = Vector3.new(20, 0.6, 8), Position = shopC + Vector3.new(0, 11.4, dir * 3.4),
			Color = Color3.fromRGB(64, 72, 84), Material = Enum.Material.Slate}, shop)
		roof.CFrame = CFrame.new(roof.Position) * CFrame.Angles(math.rad(dir * -22), 0, 0)
	end
	-- 櫃台
	part({Size = Vector3.new(12, 1, 5), Position = shopC + Vector3.new(0, 3.2, 0), Color = Color3.fromRGB(146, 106, 68), Material = Enum.Material.Wood}, shop)
	part({Size = Vector3.new(12.6, 0.35, 5.6), Position = shopC + Vector3.new(0, 3.85, 0),
		Color = Color3.fromRGB(255, 196, 96), Material = Enum.Material.Neon, Transparency = 0.15}, shop)
	local shopSign = part({Size = Vector3.new(10, 2.8, 0.4), Position = shopC + Vector3.new(0, 9.2, -5.4),
		Color = Color3.fromRGB(42, 32, 26), Material = Enum.Material.Wood}, shop)
	local sg = Instance.new("SurfaceGui"); sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(400, 120); sg.Parent = shopSign
	local st = Instance.new("TextLabel"); st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
	st.Text = "⚔ 軍械庫"; st.TextScaled = true; st.TextColor3 = Color3.fromRGB(255, 215, 90); st.Font = Enum.Font.SourceSansBold; st.Parent = sg
	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.ActionText = "買刀"; shopPrompt.ObjectText = "軍械庫"; shopPrompt.HoldDuration = 0
	shopPrompt.MaxActivationDistance = 14
	shopPrompt.Parent = shopSign
	local shopLight = Instance.new("PointLight")
	shopLight.Color = Color3.fromRGB(255, 200, 120); shopLight.Range = 26; shopLight.Brightness = 1.3
	shopLight.Parent = shopSign

	-- 抽獎機（扭蛋機）
	local gachaC = LOBBY_CENTER + Vector3.new(0, 0, 24)
	local gacha = Instance.new("Model"); gacha.Name = "Gacha"; gacha.Parent = island
	disc(gachaC + Vector3.new(0, 2.3, 0), 12, 3,
		{Color = Color3.fromRGB(74, 46, 62), Material = Enum.Material.Metal}, gacha)
	local body = part({Size = Vector3.new(6, 6, 5), Position = gachaC + Vector3.new(0, 6.4, 0),
		Color = Color3.fromRGB(226, 74, 118), Material = Enum.Material.SmoothPlastic}, gacha)
	local dome = part({Shape = Enum.PartType.Ball, Size = Vector3.new(7.4, 7.4, 7.4),
		Position = gachaC + Vector3.new(0, 10.4, 0),
		Color = Color3.fromRGB(220, 240, 255), Material = Enum.Material.Glass,
		Transparency = 0.45, CanCollide = false}, gacha)
	dome.Reflectance = 0.12
	-- 裡面的彩球
	for i = 1, 9 do
		part({Shape = Enum.PartType.Ball, Size = Vector3.new(1.15, 1.15, 1.15),
			Position = gachaC + Vector3.new(-1.6 + (i % 3) * 1.6, 9.4 + (math.floor((i - 1) / 3)) * 1.15, 0.4),
			Color = Color3.fromHSV((i * 0.13) % 1, 0.75, 1), Material = Enum.Material.Neon, CanCollide = false}, gacha)
	end
	part({Size = Vector3.new(7.6, 0.5, 7.6), Position = gachaC + Vector3.new(0, 13.9, 0),
		Color = Color3.fromRGB(255, 214, 110), Material = Enum.Material.Neon, CanCollide = false}, gacha)
	local gachaPrompt = Instance.new("ProximityPrompt")
	gachaPrompt.ActionText = "抽獎 (¥" .. GACHA_COST .. ")"; gachaPrompt.ObjectText = "幸運扭蛋"; gachaPrompt.HoldDuration = 0
	gachaPrompt.MaxActivationDistance = 14
	gachaPrompt.Parent = body
	local gl = Instance.new("PointLight")
	gl.Color = Color3.fromRGB(255, 150, 200); gl.Range = 22; gl.Brightness = 1.5
	gl.Parent = body

	-- 排行板
	local lbC = LOBBY_CENTER + Vector3.new(26, 0, 16)
	part({Size = Vector3.new(13, 9, 1.2), Position = lbC + Vector3.new(0, 6.5, 0),
		Color = Color3.fromRGB(72, 56, 42), Material = Enum.Material.Wood}, island)
	local boardFace = part({Size = Vector3.new(12, 8, 0.2), Position = lbC + Vector3.new(0, 6.5, 0.7),
		Color = Color3.fromRGB(26, 30, 44), Material = Enum.Material.SmoothPlastic}, island)
	local bg = Instance.new("SurfaceGui"); bg.Name = "BoardGui"; bg.Face = Enum.NormalId.Front; bg.CanvasSize = Vector2.new(480, 320); bg.Parent = boardFace
	local title = Instance.new("TextLabel"); title.Size = UDim2.new(1, 0, 0.18, 0); title.BackgroundTransparency = 1
	title.Text = "🏆 金幣排行"; title.TextScaled = true; title.TextColor3 = Color3.fromRGB(255, 215, 90); title.Font = Enum.Font.SourceSansBold; title.Parent = bg
	local list = Instance.new("TextLabel"); list.Name = "List"; list.Size = UDim2.new(1, -16, 0.82, -8); list.Position = UDim2.new(0, 8, 0.18, 4)
	list.BackgroundTransparency = 1; list.Text = "暫無資料"; list.TextScaled = true; list.TextColor3 = Color3.new(1, 1, 1); list.Font = Enum.Font.SourceSans; list.Parent = bg

	-- 出生點
	local sp = Instance.new("SpawnLocation")
	sp.Size = Vector3.new(8, 0.8, 8); sp.Position = LOBBY_CENTER + Vector3.new(0, 2.2, 4)
	sp.Anchored = true; sp.Neutral = true
	sp.Color = Color3.fromRGB(36, 40, 54); sp.Material = Enum.Material.Metal
	sp.Reflectance = 0.18; sp.Transparency = 0
	sp.Parent = island
	-- 出生台發光圓盤（蓋住預設的藍色貼圖感）
	disc(LOBBY_CENTER + Vector3.new(0, 2.65, 4), 9.6, 0.18,
		{Color = Color3.fromRGB(255, 206, 120), Material = Enum.Material.Neon,
		Transparency = 0.35, CanCollide = false}, island)

	-- 圍欄（半透明木欄，防止掉下去）
	local edge = 50
	for i, off in ipairs({Vector3.new(0, 0, -edge), Vector3.new(0, 0, edge), Vector3.new(-edge, 0, 0), Vector3.new(edge, 0, 0)}) do
		local horizontal = (i <= 2)
		part({Size = Vector3.new(horizontal and 100 or 1.6, 5, horizontal and 1.6 or 100),
			Position = LOBBY_CENTER + off + Vector3.new(0, 4, 0),
			Color = Color3.fromRGB(124, 92, 62), Material = Enum.Material.Wood, Transparency = 0.35, CanCollide = true}, island)
	end

	-- 裝飾：燈籠柱（四角）、櫻花樹（四棵）
	for _, p in ipairs({
		LOBBY_CENTER + Vector3.new(-16, 1.6, -14),
		LOBBY_CENTER + Vector3.new(16, 1.6, -14),
		LOBBY_CENTER + Vector3.new(-20, 1.6, 30),
		LOBBY_CENTER + Vector3.new(20, 1.6, 30),
	}) do
		lanternPost(p, island, Color3.fromRGB(255, 168, 120))
	end
	for _, p in ipairs({
		LOBBY_CENTER + Vector3.new(-38, 1.2, -6),
		LOBBY_CENTER + Vector3.new(38, 1.2, -6),
		LOBBY_CENTER + Vector3.new(-34, 1.2, 36),
		LOBBY_CENTER + Vector3.new(34, 1.2, 36),
	}) do
		sakuraTree(p, 1, island)
	end

	island.Parent = workspace
	return {shopPrompt = shopPrompt, gachaPrompt = gachaPrompt, lbList = list}
end

local lobbyRefs = buildLobby()

-- ------------------------------------------------------------
-- 地圖選擇板（大廳：15 塊板子，站上去 = 投那一張地圖）
-- ------------------------------------------------------------
local mapPads: {{pad: Part, label: TextLabel, idx: number}} = {}

local function buildMapBoard()
	local boardC = LOBBY_CENTER + Vector3.new(0, 0, -16)
	-- 木框平台（像影片裡的選圖台）
	part({Size = Vector3.new(60, 0.4, 34), Position = boardC + Vector3.new(0, 1.2, 0),
		Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.WoodPlanks})
	part({Size = Vector3.new(62, 1.2, 36), Position = boardC + Vector3.new(0, 0.4, 0),
		Color = Color3.fromRGB(70, 50, 35), Material = Enum.Material.Wood})

	-- 標題
	local sign = part({Size = Vector3.new(20, 3, 0.6), Position = boardC + Vector3.new(0, 4.6, -16.4),
		Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Wood})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back; sg.CanvasSize = Vector2.new(600, 90); sg.Parent = sign
	local st = Instance.new("TextLabel")
	st.Size = UDim2.new(1, 0, 1, 0); st.BackgroundTransparency = 1
	st.Text = "🗺 選擇地圖：站上去投票（5 形狀 × 3 地板 = 15 張）"
	st.TextColor3 = Color3.fromRGB(255, 215, 90); st.TextScaled = true
	st.Font = Enum.Font.SourceSansBold; st.Parent = sg

	-- 15 塊地圖板（5 形狀直排 × 3 地板橫排）
	local padY = LOBBY_CENTER.Y + 1.55
	for idx, map in ipairs(MAPS) do
		local col = ((idx - 1) % 5)          -- 0~4 → 形狀
		local row = math.floor((idx - 1) / 5) -- 0~2 → 地板
		local pos = boardC + Vector3.new(-21 + col * 10.5, 0, -9 + row * 9)
		local pad = part({Size = Vector3.new(8.5, 0.3, 7.5), Position = Vector3.new(pos.X, padY, pos.Z),
			Color = Color3.fromRGB(54, 58, 72), Material = Enum.Material.Metal, Reflectance = 0.18})
		part({Size = Vector3.new(9.2, 0.14, 8.2), Position = Vector3.new(pos.X, padY - 0.14, pos.Z),
			Color = Color3.fromRGB(255, 172, 96), Material = Enum.Material.Neon,
			Transparency = 0.78, CanCollide = false})
		local pg = Instance.new("SurfaceGui")
		pg.Face = Enum.NormalId.Top; pg.CanvasSize = Vector2.new(340, 160); pg.Parent = pad
		local lb = Instance.new("TextLabel")
		lb.Size = UDim2.new(1, -6, 1, -6); lb.Position = UDim2.new(0, 3, 0, 3)
		lb.BackgroundColor3 = Color3.fromRGB(20, 20, 30); lb.BackgroundTransparency = 0.25
		lb.TextColor3 = Color3.new(1, 1, 1); lb.TextScaled = true
		lb.Font = Enum.Font.SourceSansBold
		lb.Text = map.name .. "\n👤 0"
		lb.Parent = pg
		table.insert(mapPads, {pad = pad, label = lb, idx = idx})
	end
end

buildMapBoard()

-- 站上哪塊板就投哪張（每 0.3 秒偵測一次）
task.spawn(function()
	while true do
		task.wait(0.3)
		for _, plr in ipairs(Players:GetPlayers()) do
			local c = plr.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if hrp and hrp.Position.Y < LOBBY_CENTER.Y + 12 and math.abs(hrp.Position.Z - (LOBBY_CENTER.Z - 16)) < 20 then
				for _, mp in ipairs(mapPads) do
					local p = mp.pad.Position
					if math.abs(hrp.Position.X - p.X) <= 4.5 and math.abs(hrp.Position.Z - p.Z) <= 4
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
end)

-- 板子票數顯示（每秒更新，最多票的金色）
task.spawn(function()
	while true do
		task.wait(1)
		local tally: {[number]: number} = {}
		local bestN = 0
		for plr, idx in pairs(votes) do
			if plr.Parent and MAPS[idx] then
				tally[idx] = (tally[idx] or 0) + 1
				if tally[idx] > bestN then bestN = tally[idx] end
			end
		end
		for _, mp in ipairs(mapPads) do
			local n = tally[mp.idx] or 0
			mp.label.Text = MAPS[mp.idx].name .. "\n👤 " .. n
			if bestN > 0 and n == bestN then
				mp.label.TextColor3 = Color3.fromRGB(255, 215, 90)
				mp.label.BackgroundColor3 = Color3.fromRGB(70, 55, 15)
			elseif n > 0 then
				mp.label.TextColor3 = Color3.fromRGB(160, 255, 170)
				mp.label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
			else
				mp.label.TextColor3 = Color3.new(1, 1, 1)
				mp.label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
			end
		end
	end
end)

-- ------------------------------------------------------------
-- 競技場（圓形浮空躲避球場）
-- ------------------------------------------------------------
local ARENA_CENTER = Vector3.new(0, 0, -600)
local ARENA_R = 62
local arenaInnerR = ARENA_R   -- buildArena 會依形狀更新

local function buildArena(mapIdx: number)
	local map = MAPS[mapIdx]
	local shape: number = map.shape
	local floorDef: any = FLOORS[map.floor]

	if workspace:FindFirstChild("Arena") then
		workspace.Arena:Destroy()
	end

	local arena = Instance.new("Model")
	arena.Name = "Arena"

	-- 各地板的光澤與發光色（材質感的重點）
	local trimColor = (map.floor == 1 and Color3.fromRGB(255, 128, 52))
		or (map.floor == 2 and Color3.fromRGB(120, 220, 255))
		or (map.floor == 3 and Color3.fromRGB(150, 245, 255))
	local floorReflect = (map.floor == 3) and 0.18 or (map.floor == 1 and 0.02 or 0.05)

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
	disc(ARENA_CENTER + Vector3.new(0, floorY, 0), aIn * 2, 2,
		{Color = floorDef.color, Material = floorDef.material, CustomPhysicalProperties = floorProps, Reflectance = floorReflect}, arena)

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

	for _, e in ipairs(edgeDefs) do
		local midAng, edgeLen, innerR = e[1], e[2], e[3]
		local bandLen = ARENA_R - innerR + 3
		local dir = Vector3.new(math.cos(midAng), 0, math.sin(midAng))
		local pos = ARENA_CENTER + dir * (innerR + bandLen / 2 - 1.5) + Vector3.new(0, floorY, 0)
		part({Size = Vector3.new(edgeLen, 2, bandLen),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Color = floorDef.color, Material = floorDef.material,
			CustomPhysicalProperties = floorProps, Reflectance = floorReflect}, arena)
		-- 外緣金屬包邊
		local capPos = ARENA_CENTER + dir * (ARENA_R + 0.6) + Vector3.new(0, -0.3, 0)
		part({Size = Vector3.new(edgeLen + 1.6, 1.4, 2.4),
			CFrame = CFrame.lookAt(capPos, capPos + dir),
			Color = Color3.fromRGB(58, 60, 72), Material = Enum.Material.Metal,
			Reflectance = 0.22, CanCollide = false}, arena)
		-- 霓虹邊條（浮在包邊上）
		local npos = ARENA_CENTER + dir * (ARENA_R + 1.6) + Vector3.new(0, 0.35, 0)
		part({Size = Vector3.new(edgeLen, 0.3, 0.9),
			CFrame = CFrame.lookAt(npos, npos + dir),
			Color = trimColor, Material = Enum.Material.Neon, CanCollide = false}, arena)
	end

	-- 圓形：外圈金屬 + 霓虹
	if shape == 1 then
		disc(ARENA_CENTER + Vector3.new(0, -0.35, 0), ARENA_R * 2 + 3.4, 1.4,
			{Color = Color3.fromRGB(58, 60, 72), Material = Enum.Material.Metal, Reflectance = 0.22, CanCollide = false}, arena)
		disc(ARENA_CENTER + Vector3.new(0, 0.35, 0), ARENA_R * 2 + 1.2, 0.3,
			{Color = trimColor, Material = Enum.Material.Neon, CanCollide = false}, arena)
	end

	-- 地板紋路：三圈同心圓
	for _, rr in ipairs({0.32, 0.58, 0.86}) do
		disc(ARENA_CENTER + Vector3.new(0, 0.03, 0), aIn * 2 * rr, 0.16,
			{Color = trimColor, Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false}, arena)
	end
	-- 放射線
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p = ARENA_CENTER + dir * (aIn * 0.44) + Vector3.new(0, 0.03, 0)
		part({Size = Vector3.new(0.5, 0.16, aIn * 0.86),
			CFrame = CFrame.lookAt(p, p + dir),
			Color = trimColor, Material = Enum.Material.Neon, Transparency = 0.62, CanCollide = false}, arena)
	end

	-- 中央徽記（八角星 + 內圈）
	disc(ARENA_CENTER + Vector3.new(0, 0.05, 0), 22, 0.18,
		{Color = Color3.fromRGB(255, 226, 150), Material = Enum.Material.Neon, Transparency = 0.4, CanCollide = false}, arena)
	disc(ARENA_CENTER + Vector3.new(0, 0.07, 0), 10, 0.2,
		{Color = trimColor, Material = Enum.Material.Neon, CanCollide = false}, arena)
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p = ARENA_CENTER + dir * 8 + Vector3.new(0, 0.08, 0)
		part({Size = Vector3.new(1.1, 0.22, 5.6),
			CFrame = CFrame.lookAt(p, p + dir),
			Color = Color3.fromRGB(255, 238, 180), Material = Enum.Material.Neon,
			Transparency = 0.2, CanCollide = false}, arena)
	end

	-- 底座岩
	local rockR = math.max(aIn * 0.9, ARENA_R * 0.5)
	disc(ARENA_CENTER + Vector3.new(0, -8, 0), rockR * 2, 13,
		{Color = Color3.fromRGB(62, 48, 58), Material = Enum.Material.Rock}, arena)
	disc(ARENA_CENTER + Vector3.new(0, -16, 0), rockR * 1.5, 9,
		{Color = Color3.fromRGB(46, 38, 48), Material = Enum.Material.Basalt}, arena)

	-- 障礙方塊（金屬深紅 + 頂部發光邊，跳得上去佔高點）
	local blockR = aIn * 0.85
	for i = 1, 12 do
		local ang = math.rad(i * 30 + math.random(-10, 10))
		local rr = blockR * (0.25 + math.random() * 0.75)
		local w = 6 + math.random() * 3              -- 6 ~ 9 寬
		local h = 2.5 + math.random() * 4            -- 2.5 ~ 6.5 高
		local cx = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, h / 2, math.sin(ang) * rr)
		part({Size = Vector3.new(w, h, w), Position = cx,
			Color = Color3.fromRGB(150, 44, 56), Material = Enum.Material.Metal,
			Reflectance = 0.12}, arena)
		-- 頂面發光細框
		part({Size = Vector3.new(w * 0.92, 0.18, w * 0.92), Position = cx + Vector3.new(0, h / 2 + 0.1, 0),
			Color = Color3.fromRGB(255, 132, 96), Material = Enum.Material.Neon,
			Transparency = 0.35, CanCollide = false}, arena)
	end

	-- 外圍燈柱（照出明暗層次，不擋路 → 放在場外）
	local lampCount = 8
	for i = 0, lampCount - 1 do
		local ang = math.rad(i * (360 / lampCount))
		local base = ARENA_CENTER + Vector3.new(math.cos(ang) * (ARENA_R + 7), 0, math.sin(ang) * (ARENA_R + 7))
		part({Size = Vector3.new(1.8, 26, 1.8), Position = base + Vector3.new(0, 13, 0),
			Color = Color3.fromRGB(42, 44, 56), Material = Enum.Material.Metal,
			Reflectance = 0.2, CanCollide = false}, arena)
		local head = part({Size = Vector3.new(3.4, 3.4, 3.4), Position = base + Vector3.new(0, 27, 0),
			Color = trimColor, Material = Enum.Material.Neon, CanCollide = false}, arena)
		local pl = Instance.new("PointLight")
		pl.Color = trimColor
		pl.Range = 62
		pl.Brightness = 1.5
		pl.Shadows = true
		pl.Parent = head
	end

	-- 觀眾席：外圈三層階梯 + 座位
	for layer = 1, 3 do
		local ringR = ARENA_R + 12 + layer * 7
		if shape == 1 then
			disc(ARENA_CENTER + Vector3.new(0, 2.5 + layer * 2.2, 0), ringR * 2, 4,
				{Color = Color3.fromRGB(56, 52, 66), Material = Enum.Material.Concrete, CanCollide = false}, arena)
		end
		local seats = 12
		for i = 0, seats - 1 do
			local ang = math.rad(i * (360 / seats) + layer * 11)
			local p = ARENA_CENTER + Vector3.new(math.cos(ang) * ringR, 5 + layer * 2.2, math.sin(ang) * ringR)
			part({Size = Vector3.new(3.6, 2.6, 3.2), Position = p,
				CFrame = CFrame.new(p) * CFrame.Angles(0, -ang + math.rad(90), 0),
				Color = Color3.fromRGB(74 + layer * 8, 62, 88), Material = Enum.Material.Fabric,
				CanCollide = false}, arena)
		end
	end

	-- 四周浮空岩（裝飾）
	for i = 1, 14 do
		local ang = math.rad(i * 25.7)
		local rr = ARENA_R + math.random(28, 80)
		part({Shape = Enum.PartType.Ball, Size = Vector3.new(math.random(6, 14), math.random(6, 14), math.random(6, 14)),
			Position = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, math.random(-30, 5), math.sin(ang) * rr),
			Color = Color3.fromRGB(68, 58, 76), Material = Enum.Material.Rock, CanCollide = false}, arena)
	end

	-- 懸浮水晶（緩慢上下浮動 + 呼吸光）
	for i = 0, 5 do
		local ang = math.rad(i * 60 + 20)
		local rr = ARENA_R * 0.72
		local p0 = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, 20 + (i % 3) * 4, math.sin(ang) * rr)
		local cry = part({Size = Vector3.new(2.2, 5.4, 2.2), Position = p0,
			CFrame = CFrame.new(p0) * CFrame.Angles(0, ang, math.rad(12)),
			Color = Color3.fromRGB(150, 220, 255), Material = Enum.Material.Glass,
			Transparency = 0.25, Reflectance = 0.25, CanCollide = false}, arena)
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(140, 210, 255)
		glow.Range = 26
		glow.Brightness = 1.2
		glow.Parent = cry
		TweenService:Create(cry, TweenInfo.new(2.6 + i * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Position = p0 + Vector3.new(0, 3.4, 0)}):Play()
		TweenService:Create(glow, TweenInfo.new(1.8 + i * 0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{Brightness = 2.4}):Play()
	end

	arena.Parent = workspace
	arenaInnerR = aIn
	return arena
end

-- 海面（很下面，全地圖共用，只建一次）
part({Name = "Ocean", Size = Vector3.new(4000, 4, 4000), Position = ARENA_CENTER + Vector3.new(0, -62, 0),
	Color = Color3.fromRGB(26, 64, 112), Material = Enum.Material.Water,
	Reflectance = 0.12, CanCollide = false})

-- ------------------------------------------------------------
-- 回合狀態
-- ------------------------------------------------------------
local roundActive = false
local inRound: {[Player]: boolean} = {}
local alive: {[Player]: boolean} = {}
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
	local tool = Instance.new("Tool")
	tool.Name = skin.name .. "之刀"
	tool.ToolTip = "砍 5 下擊倒敵人"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 3.4, 0.4)
	handle.Color = skin.color
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	-- 握把（黑）
	local grip = Instance.new("Part")
	grip.Name = "GripDeco"; grip.Size = Vector3.new(0.5, 1.2, 0.5); grip.Color = Color3.fromRGB(40, 40, 40)
	grip.Material = Enum.Material.Rubber; grip.CanCollide = false
	grip.CFrame = handle.CFrame * CFrame.new(0, -1.6, 0)
	local weld = Instance.new("WeldConstraint"); weld.Part0 = handle; weld.Part1 = grip; weld.Parent = handle
	grip.Parent = tool
	handle.Parent = tool
	tool.Grip = CFrame.new(0, -0.6, 0)
	return tool
end

local deflectBalls: any = nil   -- 球系统段落里赋值

local swingCd: {[Player]: number} = {}

local function knifeHit(attacker: Player)
	if not roundActive or not inRound[attacker] or not alive[attacker] then return end
	local now = os.clock()
	if (swingCd[attacker] or 0) > now then return end
	swingCd[attacker] = now + 0.45
	-- 挥刀顺手把正前方的球打回去
	if deflectBalls then
		local n = deflectBalls(attacker)
		if n > 0 then send(attacker, "deflect", n) end
	end

	local char = attacker.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end
	local look = hrp.CFrame.LookVector

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
						if thum.Health <= 0 then
							-- 擊殺獎勵在 Died 事件統一處理
						end
					end
				end
			end
		end
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
-- 球（撞到即死）· 七种球型 ＋ 刀反弹
-- ------------------------------------------------------------
local BALL_KINDS = {
	{ id = "ember", name = "烈焰球", weight = 26, color = Color3.fromRGB(255, 108, 42),
	  glow = Color3.fromRGB(255, 196, 120), size = 6, speed = {64, 90}, chase = 0 },
	{ id = "hunter", name = "追猎球", weight = 18, color = Color3.fromRGB(186, 92, 255),
	  glow = Color3.fromRGB(232, 172, 255), size = 6.4, speed = {60, 80}, chase = 0.08 },
	{ id = "heavy", name = "重击球", weight = 12, color = Color3.fromRGB(196, 42, 46),
	  glow = Color3.fromRGB(255, 120, 110), size = 11, speed = {38, 52}, chase = 0.03, shock = true },
	{ id = "bouncer", name = "弹跳球", weight = 14, color = Color3.fromRGB(58, 236, 216),
	  glow = Color3.fromRGB(190, 255, 248), size = 5.4, speed = {72, 98}, chase = 0, bounce = true },
	{ id = "splitter", name = "分裂球", weight = 12, color = Color3.fromRGB(255, 216, 62),
	  glow = Color3.fromRGB(255, 244, 160), size = 7.6, speed = {48, 64}, chase = 0.04, split = true },
	{ id = "zigzag", name = "蛇行球", weight = 11, color = Color3.fromRGB(104, 250, 118),
	  glow = Color3.fromRGB(200, 255, 198), size = 5.8, speed = {68, 86}, chase = 0.02, zigzag = 3.2 },
	{ id = "ghost", name = "幽灵球", weight = 7, color = Color3.fromRGB(236, 242, 255),
	  glow = Color3.fromRGB(196, 220, 255), size = 6.6, speed = {46, 58}, chase = 0.05, ghost = true },
}
local BALL_W = 0
for _, k in ipairs(BALL_KINDS) do BALL_W += k.weight end

-- 分裂球炸出来的小碎片（与主球同色系，速度快、体积小）
local SMALL_KIND = { id = "shard", name = "碎片", color = Color3.fromRGB(255, 226, 120),
	glow = Color3.fromRGB(255, 246, 190), size = 7.6, speed = {48, 64}, chase = 0 }

local activeBalls: {[BasePart]: boolean} = {}
local ballOwnerOf: {[BasePart]: Player} = {}   -- 被玩家刀反弹的球，击杀算给该玩家

local function pickBallKind()
	local r = math.random() * BALL_W
	for _, k in ipairs(BALL_KINDS) do
		r -= k.weight
		if r <= 0 then return k end
	end
	return BALL_KINDS[1]
end

local function makeTrail(ball: BasePart, a: Color3, b: Color3)
	local t0 = Instance.new("Attachment"); t0.Position = Vector3.new(0, 1.05, 0); t0.Parent = ball
	local t1 = Instance.new("Attachment"); t1.Position = Vector3.new(0, -1.05, 0); t1.Parent = ball
	local tr = Instance.new("Trail")
	tr.Attachment0 = t0
	tr.Attachment1 = t1
	tr.Lifetime = 0.5
	tr.MinLength = 0.04
	tr.FaceCamera = true
	tr.LightEmission = 0.9
	tr.LightInfluence = 0
	tr.Color = ColorSequence.new(a, b)
	tr.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	tr.WidthScale = NumberSequence.new(1, 0)
	tr.Parent = ball
end

-- 爆开：霓虹碎块飞散（比 Explosion 更好看，也不伤人）
local function killBurst(pos: Vector3, col: Color3, big: boolean)
	local n = big and 16 or 9
	for _ = 1, n do
		local p = Instance.new("Part")
		local s = math.random(4, 11) / 10
		p.Size = Vector3.new(s, s, s)
		p.Shape = Enum.PartType.Ball
		p.Color = col
		p.Material = Enum.Material.Neon
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Anchored = true
		p.CFrame = CFrame.new(pos)
		p.Parent = workspace
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9, math.random() - 0.5).Unit
		local dist = math.random(6, big and 20 or 13)
		local info = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(p, info, { CFrame = CFrame.new(pos + dir * dist) }):Play()
		TweenService:Create(p, TweenInfo.new(0.55), { Transparency = 1 }):Play()
		task.delay(0.6, function()
			if p and p.Parent then p:Destroy() end
		end)
	end
end

local function launchBall(kind: any, pos: Vector3, vel: Vector3, sizeMul: number, owner: Player?, silent: boolean?): BasePart
	local ball = Instance.new("Part")
	ball.Name = "DodgeBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(kind.size, kind.size, kind.size) * (sizeMul or 1)
	ball.Position = pos
	ball.Color = kind.color
	ball.Material = Enum.Material.Neon
	ball.Transparency = kind.ghost and 0.45 or 0
	ball.CanCollide = false
	ball.Anchored = false
	ball.CFrame = CFrame.new(pos, pos + (vel.Magnitude > 1 and vel.Unit or Vector3.new(0, 0, 1)))
	tagObject(ball)
	ball:SetAttribute("BallKind", kind.id)
	ball.Parent = workspace
	activeBalls[ball] = true
	if owner then ballOwnerOf[ball] = owner end

	-- 反重力：让球笔直穿过场地，不会掉出世界
	local antiG = Instance.new("BodyForce")
	antiG.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity, 0)
	antiG.Parent = ball

	local spin = Instance.new("BodyAngularVelocity")
	spin.AngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
	spin.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
	spin.Parent = ball

	makeTrail(ball, kind.color, kind.glow)
	local light = Instance.new("PointLight")
	light.Color = kind.glow
	light.Brightness = kind.ghost and 1.1 or 2.4
	light.Range = kind.size * 2.2 + 6
	light.Shadows = false
	light.Parent = ball

	ball.AssemblyLinearVelocity = vel

	-- 出球预告（只有特殊球才播，免得一直刷屏）
	if not silent and kind.id ~= "ember" and owner == nil then
		broadcast("ballwarn", { name = kind.name, id = kind.id,
			r = kind.color.R, g = kind.color.G, b = kind.color.B })
	end

	local hit = false
	local born = os.clock()

	-- 击杀判定
	ball.Touched:Connect(function(other)
		if hit then return end
		if not ball.Parent then return end
		local par = other.Parent
		if not par then return end
		local hum = par:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local plr = Players:GetPlayerFromCharacter(par)
		if not plr then return end
		if not (roundActive and inRound[plr] and alive[plr]) then return end
		local owner2 = ballOwnerOf[ball]
		if owner2 == plr then return end          -- 反弹球不会砸到自己
		hit = true
		alive[plr] = false
		lastAttacker[plr] = nil :: any
		if owner2 then
			local d = pd(owner2)
			d.coins += COIN_KILL + 5
			d.kills += 1
			syncLeader(owner2)
			send(owner2, "coins", d.coins)
			send(owner2, "reflectkill", { name = plr.DisplayName })
			broadcast("killfeed", { killer = owner2.DisplayName, victim = plr.DisplayName, by = "reflect" })
		else
			broadcast("killfeed", { killer = "", victim = plr.DisplayName, by = "ball" })
		end
		hum.Health = 0
		killBurst(ball.Position, kind.glow, kind.shock == true)
		if ball.Parent then ball:Destroy() end
	end)

	-- 飞行行为（追踪 / 蛇行 / 弹墙 / 幽灵加速 / 分裂）
	local needsBrain = (kind.chase or 0) > 0 or kind.zigzag or kind.bounce or kind.ghost or kind.split
	if needsBrain then
		task.spawn(function()
			local phase = math.random() * 6.28
			local splitLeft = kind.split and 0.75 or -1
			while ball.Parent and not hit and os.clock() - born < 9 do
				local dt = task.wait(0.05) or 0.05
				if not ball.Parent or hit then break end
				phase += dt
				if splitLeft > 0 then splitLeft -= dt end

				if ballOwnerOf[ball] == nil then
					local v = ball.AssemblyLinearVelocity
					local spd = math.max(v.Magnitude, 42)
					local base = (v.Magnitude > 1 and v.Unit) or Vector3.new(0, 0, 1)
					local nearDist = math.huge
					local best, bestD = nil, math.huge
					for plr, a in pairs(alive) do
						local c = plr.Character
						local hrp = c and (c:FindFirstChild("HumanoidRootPart") :: BasePart?)
						if a and hrp then
							local dd = (hrp.Position - ball.Position).Magnitude
							if dd < nearDist then nearDist = dd end
							if dd < bestD then
								bestD = dd
								best = hrp.Position + Vector3.new(0, 1.2, 0)
							end
						end
					end

					if (kind.chase or 0) > 0 and best then
						base = base:Lerp((best - ball.Position).Unit, kind.chase)
					end

					if kind.ghost then
						if nearDist < 22 then spd *= 1.8 end
						ball.Transparency = math.clamp(0.45 - (22 - nearDist) / 60, 0.1, 0.45)
					end

					if kind.zigzag then
						local yaw = math.sin(phase * kind.zigzag) * 0.62
						base = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw) * base
					end

					if kind.bounce then
						local flat = Vector3.new(ball.Position.X - ARENA_CENTER.X, 0, ball.Position.Z - ARENA_CENTER.Z)
						if flat.Magnitude > ARENA_R - 4 then
							local nrm = flat.Unit
							local d = base:Dot(nrm)
							if d > 0 then base = (base - 2 * d * nrm).Unit end
						end
					end

					if base.Magnitude > 0.05 then
						ball.AssemblyLinearVelocity = base.Unit * spd
					end
				end

				-- 分裂：到点炸成三颗碎片
				if kind.split and splitLeft <= 0 then
					local v = ball.AssemblyLinearVelocity
					local sp = math.max(v.Magnitude, 52)
					local fwd = (v.Magnitude > 1 and v.Unit) or Vector3.new(0, 0, 1)
					for f = -1, 1 do
						local rot = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), f * 0.45)
						launchBall(SMALL_KIND, ball.Position, (rot * fwd).Unit * sp * 1.05, 0.52, ballOwnerOf[ball], true)
					end
					killBurst(ball.Position, kind.glow, false)
					hit = true
					if ball.Parent then ball:Destroy() end
					break
				end
			end
		end)
	end

	ball.Destroying:Connect(function()
		activeBalls[ball] = nil
		ballOwnerOf[ball] = nil
	end)

	task.delay(9, function()
		if ball.Parent then ball:Destroy() end
	end)
	return ball
end

-- 刀反弹：挥刀时把正前方的球打回去（一次最多两颗）
deflectBalls = function(attacker: Player): number
	local char = attacker.Character
	if not char then return 0 end
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return 0 end
	local look = hrp.CFrame.LookVector
	local n = 0
	for ball in pairs(activeBalls) do
		if n >= 2 then break end
		if ball.Parent and ballOwnerOf[ball] == nil then
			local off = ball.Position - hrp.Position
			if off.Magnitude <= 15 and off.Magnitude > 1 and look:Dot(off.Unit) > 0.1 then
				n += 1
				ballOwnerOf[ball] = attacker
				local dir = (look + Vector3.new(0, 0.14, 0)).Unit
				ball.AssemblyLinearVelocity = dir * 120
				ball.Color = Color3.fromRGB(255, 236, 150)
				ball:SetAttribute("Reflected", true)
				local l = ball:FindFirstChildOfClass("PointLight")
				if l then
					l.Color = Color3.fromRGB(255, 240, 170)
					l.Brightness = 4
				end
				local hl = Instance.new("Highlight")
				hl.FillColor = Color3.fromRGB(255, 235, 160)
				hl.FillTransparency = 0.55
				hl.OutlineColor = Color3.fromRGB(255, 255, 210)
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = ball
				task.delay(1.2, function()
					if hl and hl.Parent then hl:Destroy() end
				end)
				killBurst(ball.Position, Color3.fromRGB(255, 240, 170), false)
			end
		end
	end
	return n
end

local function spawnBall(forcedKind: any?)
	local kind = forcedKind or pickBallKind()
	local ang = math.rad(math.random(0, 359))
	local startR = ARENA_R + 8
	local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * startR, 3, math.sin(ang) * startR)
	-- 目标：六成机率瞄准某个存活玩家（更有威胁），否则打向场内随机点
	local target
	if math.random() < 0.6 then
		local cands = {}
		for plr, a in pairs(alive) do
			local c = plr.Character
			local h = c and c:FindFirstChild("HumanoidRootPart")
			if a and h then table.insert(cands, h.Position) end
		end
		if #cands > 0 then target = cands[math.random(1, #cands)] end
	end
	if not target then
		local targAng = math.rad(math.random(0, 359))
		local targR = math.random(0, math.floor(ARENA_R * 0.5))
		target = ARENA_CENTER + Vector3.new(math.cos(targAng) * targR, 2, math.sin(targAng) * targR)
	end
	target = Vector3.new(target.X, 3, target.Z)
	local vel = (target - pos).Unit * math.random(kind.speed[1], kind.speed[2])
	launchBall(kind, pos, vel, 1, nil, false)
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
	local ang = math.rad(math.random(0, 359))
	local rr = math.random(10, ARENA_R - 12)
	local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * rr, 2, math.sin(ang) * rr)

	local box = Instance.new("Part")
	box.Size = Vector3.new(3, 3, 3)
	box.Position = pos
	box.Color = Color3.fromRGB(255, 200, 60)
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = true
	box.Name = "MysteryBox"
	tagObject(box)
	box.Parent = workspace

	-- 掉落動畫
	box.CFrame = CFrame.new(pos + Vector3.new(0, 14, 0)) * CFrame.Angles(0, math.random() * 6.28, 0)
	TweenService:Create(box, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {CFrame = CFrame.new(pos) * box.CFrame.Rotation}):Play()

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
		-- 多邊形與星星要留在內切圓裡，否則會直接掉出場外
		local spawnR = math.min(ARENA_R - 12, arenaInnerR * 0.78)
		local pos = ARENA_CENTER + Vector3.new(math.cos(ang) * spawnR, 5, math.sin(ang) * spawnR)
		char:PivotTo(CFrame.new(pos))
		hum.WalkSpeed = 16
	end
end

local function startRound()
	roundActive = true
	inRound = {}
	alive = {}
	lastAttacker = {}
	roundTag += 1
	clearRoundObjects()

	-- 統計大廳投票 → 得票最高的地圖（平手隨機）；沒人投就隨機一張
	local tally: {[number]: number} = {}
	local voterCount = 0
	for plr, idx in pairs(votes) do
		if plr.Parent and MAPS[idx] then
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
		currentMap = math.random(1, #MAPS)
	end
	buildArena(currentMap)
	broadcast("mapinfo", MAPS[currentMap].name)

	local i = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		i += 1
		inRound[plr] = true
		alive[plr] = true
		plr:LoadCharacter()
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

	if act == "buynife" then
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
task.spawn(function()
	while true do
		task.wait(5)
		local entries = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			table.insert(entries, {name = plr.DisplayName, coins = pd(plr).coins})
		end
		table.sort(entries, function(a, b) return a.coins > b.coins end)
		local lines = {}
		for i = 1, math.min(6, #entries) do
			table.insert(lines, i .. ". " .. entries[i].name .. "  ¥" .. entries[i].coins)
		end
		lobbyRefs.lbList.Text = #lines > 0 and table.concat(lines, "\n") or "暫無資料"
	end
end)

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

