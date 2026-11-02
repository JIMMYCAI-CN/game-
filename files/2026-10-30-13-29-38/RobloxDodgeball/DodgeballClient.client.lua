--!strict
-- ============================================================
--  躲避球大亂鬥 · 客戶端主腳本
--  放置位置：StarterPlayer → StarterPlayerScripts（LocalScript）
--  UI：金幣／狀態／淘汰播報／軍械庫商店／抽獎機／道具欄／失明效果
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer
local Net = ReplicatedStorage:WaitForChild("DodgeNet") :: RemoteEvent

-- ------------------------------------------------------------
-- UI 基礎
-- ------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "DodgeUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = plr:WaitForChild("PlayerGui")

local function styleRound(f: Frame, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = f
end

-- 頂部狀態列
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 420, 0, 36)
statusLabel.Position = UDim2.new(0.5, -210, 0, 8)
statusLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
statusLabel.BackgroundTransparency = 0.35
statusLabel.TextColor3 = Color3.fromRGB(255, 230, 150)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.SourceSansBold
statusLabel.Text = "…"
styleRound(statusLabel :: any, 10)
statusLabel.Parent = gui

-- 金幣（左上）
local coinLabel = Instance.new("TextLabel")
coinLabel.Size = UDim2.new(0, 150, 0, 34)
coinLabel.Position = UDim2.new(0, 10, 0, 8)
coinLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
coinLabel.BackgroundTransparency = 0.35
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 90)
coinLabel.TextScaled = true
coinLabel.Font = Enum.Font.SourceSansBold
coinLabel.Text = "¥ …"
styleRound(coinLabel :: any, 10)
coinLabel.Parent = gui

-- 淘汰播報（右上，往上堆疊）
local feedFrame = Instance.new("Frame")
feedFrame.Size = UDim2.new(0, 320, 0, 220)
feedFrame.Position = UDim2.new(1, -330, 0, 50)
feedFrame.BackgroundTransparency = 1
feedFrame.Parent = gui
local feedLayout = Instance.new("UIListLayout")
feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
feedLayout.Parent = feedFrame

local function addFeed(txt: string, col: Color3)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0, 26)
	t.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	t.BackgroundTransparency = 0.4
	t.TextColor3 = col
	t.TextScaled = true
	t.Font = Enum.Font.SourceSansBold
	t.Text = txt
	styleRound(t :: any, 8)
	t.Parent = feedFrame
	task.delay(4, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.5), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
			task.wait(0.55)
			t:Destroy()
		end
	end)
end

-- 飄提示（底部中間）
local toast = Instance.new("TextLabel")
toast.Size = UDim2.new(0, 460, 0, 34)
toast.Position = UDim2.new(0.5, -230, 1, -140)
toast.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
toast.BackgroundTransparency = 0.35
toast.TextColor3 = Color3.new(1, 1, 1)
toast.TextScaled = true
toast.Font = Enum.Font.SourceSansBold
toast.Text = ""
toast.Visible = false
styleRound(toast :: any, 10)
toast.Parent = gui

local toastToken = 0
local function showToast(txt: string)
	toastToken += 1
	local my = toastToken
	toast.Text = txt
	toast.Visible = true
	task.delay(2.5, function()
		if toastToken == my then toast.Visible = false end
	end)
end

-- 失明效果（全黑覆蓋）
local blind = Instance.new("Frame")
blind.Size = UDim2.new(1, 0, 1, 0)
blind.BackgroundColor3 = Color3.new(0, 0, 0)
blind.BackgroundTransparency = 1
blind.Visible = false
blind.ZIndex = 50
blind.Parent = gui

-- 受傷紅閃
local hurtFlash = Instance.new("Frame")
hurtFlash.Size = UDim2.new(1, 0, 1, 0)
hurtFlash.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
hurtFlash.BackgroundTransparency = 1
hurtFlash.Visible = false
hurtFlash.ZIndex = 40
hurtFlash.Parent = gui

-- ------------------------------------------------------------
-- 打击感：屏幕震动 / 大字横幅 / 命中飘字 / 球种预警
-- ------------------------------------------------------------
local RunService = game:GetService("RunService")

local shakeAmt = 0
local function addShake(a: number)
	shakeAmt = math.min(shakeAmt + a, 1.4)
end
RunService:BindToRenderStep("DodgeShake", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	if shakeAmt > 0.004 then
		local cam = workspace.CurrentCamera
		if cam then
			local k = shakeAmt * 0.032
			cam.CFrame = cam.CFrame * CFrame.Angles(
				(math.random() - 0.5) * k,
				(math.random() - 0.5) * k,
				(math.random() - 0.5) * k * 0.7)
		end
		shakeAmt = shakeAmt * math.max(0, 1 - dt * 8)
	else
		shakeAmt = 0
	end
end)

-- 大字横幅
local bigLabel = Instance.new("TextLabel")
bigLabel.Size = UDim2.new(0, 680, 0, 96)
bigLabel.Position = UDim2.new(0.5, -340, 0.26, 0)
bigLabel.BackgroundTransparency = 1
bigLabel.TextColor3 = Color3.new(1, 1, 1)
bigLabel.TextScaled = true
bigLabel.Font = Enum.Font.FredokaOne
bigLabel.TextStrokeTransparency = 0.4
bigLabel.TextTransparency = 1
bigLabel.ZIndex = 45
bigLabel.Text = ""
bigLabel.Parent = gui

local bigToken = 0
local function bigBanner(txt: string, col: Color3, hold: number?)
	bigToken += 1
	local my = bigToken
	bigLabel.Text = txt
	bigLabel.TextColor3 = col
	bigLabel.TextTransparency = 1
	bigLabel.Position = UDim2.new(0.5, -340, 0.26, 20)
	TweenService:Create(bigLabel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Position = UDim2.new(0.5, -340, 0.26, 0),
	}):Play()
	task.delay(hold or 1.1, function()
		if bigToken ~= my then return end
		TweenService:Create(bigLabel, TweenInfo.new(0.35), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, -340, 0.26, -26),
		}):Play()
	end)
end

-- 命中飘字
local function floatText(txt: string, col: Color3)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(0, 260, 0, 40)
	t.Position = UDim2.new(0.5, -130 + math.random(-45, 45), 0.6, 0)
	t.BackgroundTransparency = 1
	t.Text = txt
	t.TextColor3 = col
	t.TextScaled = true
	t.Font = Enum.Font.SourceSansBold
	t.TextStrokeTransparency = 0.35
	t.ZIndex = 46
	t.Parent = gui
	local startX = t.Position.X.Scale
	local startOff = t.Position.X.Offset
	TweenService:Create(t, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(startX, startOff, 0.6, -72),
		TextTransparency = 1,
	}):Play()
	task.delay(0.8, function()
		if t and t.Parent then t:Destroy() end
	end)
end

-- 球种预警（状态条下方）
local warnLabel = Instance.new("TextLabel")
warnLabel.Size = UDim2.new(0, 380, 0, 30)
warnLabel.Position = UDim2.new(0.5, -190, 0, 48)
warnLabel.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
warnLabel.BackgroundTransparency = 1
warnLabel.TextColor3 = Color3.new(1, 1, 1)
warnLabel.TextScaled = true
warnLabel.Font = Enum.Font.SourceSansBold
warnLabel.TextTransparency = 1
warnLabel.Text = ""
warnLabel.ZIndex = 30
styleRound(warnLabel :: any, 8)
warnLabel.Parent = gui

local warnToken = 0
local function ballWarn(nm: string, col: Color3)
	warnToken += 1
	local my = warnToken
	warnLabel.Text = "⚠  " .. nm .. " 来袭"
	warnLabel.TextColor3 = col
	warnLabel.BackgroundTransparency = 0.3
	warnLabel.TextTransparency = 0
	task.delay(1.7, function()
		if warnToken ~= my then return end
		TweenService:Create(warnLabel, TweenInfo.new(0.5), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		}):Play()
	end)
end

-- 连杀计数
local streak = 0
local streakAt = 0
local STREAK_NAMES = { "DOUBLE KILL", "TRIPLE KILL", "RAMPAGE", "UNSTOPPABLE", "GODLIKE" }
local function bumpStreak()
	local now = os.clock()
	if now - streakAt > 4.5 then streak = 0 end
	streakAt = now
	streak += 1
	if streak >= 2 then
		local nm = STREAK_NAMES[math.min(streak - 1, #STREAK_NAMES)]
		bigBanner(nm, Color3.fromRGB(255, 214, 110))
		addShake(0.35)
	end
end

-- ------------------------------------------------------------
-- 道具欄（最多 2 格，像影片裡右上角的 1/2 格）
-- ------------------------------------------------------------
local slots: {Frame} = {}
for i = 1, 2 do
	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 72, 0, 72)
	f.Position = UDim2.new(0, 14, 1, -90 - (i - 1) * 84)
	f.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	f.BackgroundTransparency = 0.25
	styleRound(f :: any, 12)
	f.Parent = gui

	local num = Instance.new("TextLabel")
	num.Size = UDim2.new(0, 20, 0, 20)
	num.Position = UDim2.new(0, 4, 0, 4)
	num.BackgroundTransparency = 1
	num.TextColor3 = Color3.fromRGB(200, 200, 200)
	num.TextScaled = true
	num.Font = Enum.Font.SourceSansBold
	num.Text = tostring(i)
	num.Parent = f

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -8, 0, 26)
	name.Position = UDim2.new(0, 4, 0, 24)
	name.BackgroundTransparency = 1
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextScaled = true
	name.Font = Enum.Font.SourceSansBold
	name.Text = "空"
	name.Parent = f

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = f
	btn.Activated:Connect(function()
		Net:FireServer({act = "useitem", slot = i})
	end)

	slots[i] = f
end

local function setSlots(items: {string})
	for i = 1, 2 do
		local f = slots[i]
		local name = f:FindFirstChildOfClass("TextLabel")
		if name then
			local it = items[i]
			if it then
				local map = {slowtrap = "減速陷阱", flash = "閃光彈", speed = "疾風藥水"}
				name.Text = map[it] or it
				name.TextColor3 = Color3.fromRGB(255, 230, 120)
				f.BackgroundColor3 = Color3.fromRGB(60, 50, 25)
			else
				name.Text = "空"
				name.TextColor3 = Color3.fromRGB(120, 120, 120)
				f.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
			end
		end
	end
end

-- 鍵盤 1/2 也能用
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.One then
		Net:FireServer({act = "useitem", slot = 1})
	elseif input.KeyCode == Enum.KeyCode.Two then
		Net:FireServer({act = "useitem", slot = 2})
	end
end)

-- ------------------------------------------------------------
-- 軍械庫商店
-- ------------------------------------------------------------
local shopFrame = Instance.new("Frame")
shopFrame.Size = UDim2.new(0, 560, 0, 420)
shopFrame.Position = UDim2.new(0.5, -280, 0.5, -210)
shopFrame.BackgroundColor3 = Color3.fromRGB(30, 25, 22)
shopFrame.BackgroundTransparency = 0.06
shopFrame.Visible = false
shopFrame.ZIndex = 20
styleRound(shopFrame :: any, 14)
shopFrame.Parent = gui

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(1, 0, 0, 44)
shopTitle.BackgroundTransparency = 1
shopTitle.TextColor3 = Color3.fromRGB(255, 215, 90)
shopTitle.TextScaled = true
shopTitle.Font = Enum.Font.SourceSansBold
shopTitle.Text = "⚔ 軍械庫"
shopTitle.ZIndex = 21
shopTitle.Parent = shopFrame

local shopCoins = Instance.new("TextLabel")
shopCoins.Size = UDim2.new(0, 160, 0, 30)
shopCoins.Position = UDim2.new(1, -170, 0, 6)
shopCoins.BackgroundTransparency = 1
shopCoins.TextColor3 = Color3.fromRGB(255, 215, 90)
shopCoins.TextScaled = true
shopCoins.Font = Enum.Font.SourceSansBold
shopCoins.Text = "¥ 0"
shopCoins.ZIndex = 21
shopCoins.Parent = shopFrame

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 40, 0, 40)
shopClose.Position = UDim2.new(1, -50, 0, 46)
shopClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
shopClose.TextColor3 = Color3.new(1, 1, 1)
shopClose.TextScaled = true
shopClose.Font = Enum.Font.SourceSansBold
shopClose.Text = "X"
shopClose.ZIndex = 21
styleRound(shopClose :: any, 8)
shopClose.Parent = shopFrame
shopClose.Activated:Connect(function()
	shopFrame.Visible = false
end)

-- 格子容器
local shopGrid = Instance.new("Frame")
shopGrid.Size = UDim2.new(1, -24, 1, -120)
shopGrid.Position = UDim2.new(0, 12, 0, 54)
shopGrid.BackgroundTransparency = 1
shopGrid.ZIndex = 20
local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, 165, 0, 105)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = shopGrid
shopGrid.Parent = shopFrame

local shopCells: {[string]: TextButton} = {}
local knifeList: {{[string]: any}} = {}
local shopState = {coins = 0, owned = {}, equipped = "steel"}

local function refreshShop()
	shopCoins.Text = "¥ " .. shopState.coins
	for _, k in ipairs(knifeList) do
		local cell = shopCells[k.id]
		if cell then
			local nm = cell:FindFirstChild("KN") :: TextLabel?
			local pr = cell:FindFirstChild("PR") :: TextLabel?
			if nm and pr then
				if shopState.owned[k.id] then
					if shopState.equipped == k.id then
						pr.Text = "✓ 已裝備"
						pr.TextColor3 = Color3.fromRGB(120, 255, 140)
						cell.BackgroundColor3 = Color3.fromRGB(50, 90, 50)
					else
						pr.Text = "點擊裝備"
						pr.TextColor3 = Color3.fromRGB(230, 230, 230)
						cell.BackgroundColor3 = Color3.fromRGB(55, 55, 45)
					end
				else
					pr.Text = "¥ " .. k.price
					pr.TextColor3 = (shopState.coins >= k.price) and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(255, 110, 110)
					cell.BackgroundColor3 = Color3.fromRGB(60, 45, 35)
				end
			end
		end
	end
end

local function buildShopCells()
	for _, child in ipairs(shopGrid:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end
	shopCells = {}
	for idx, k in ipairs(knifeList) do
		local cell = Instance.new("TextButton")
		cell.Name = k.id
		cell.LayoutOrder = idx
		cell.Text = ""
		cell.ZIndex = 21
		styleRound(cell :: any, 10)
		cell.Parent = shopGrid

		local nm = Instance.new("TextLabel")
		nm.Name = "KN"
		nm.Size = UDim2.new(1, -8, 0, 34)
		nm.Position = UDim2.new(0, 4, 0, 8)
		nm.BackgroundTransparency = 1
		nm.TextColor3 = k.color
		nm.TextScaled = true
		nm.Font = Enum.Font.SourceSansBold
		nm.Text = "🗡 " .. k.name
		nm.ZIndex = 22
		nm.Parent = cell

		local dmg = Instance.new("TextLabel")
		dmg.Size = UDim2.new(1, -8, 0, 20)
		dmg.Position = UDim2.new(0, 4, 0, 42)
		dmg.BackgroundTransparency = 1
		dmg.TextColor3 = Color3.fromRGB(180, 180, 180)
		dmg.TextScaled = true
		dmg.Font = Enum.Font.SourceSans
		dmg.Text = "傷害 20（一樣）"
		dmg.ZIndex = 22
		dmg.Parent = cell

		local pr = Instance.new("TextLabel")
		pr.Name = "PR"
		pr.Size = UDim2.new(1, -8, 0, 26)
		pr.Position = UDim2.new(0, 4, 0, 68)
		pr.BackgroundTransparency = 1
		pr.TextScaled = true
		pr.Font = Enum.Font.SourceSansBold
		pr.Text = ""
		pr.ZIndex = 22
		pr.Parent = cell

		cell.Activated:Connect(function()
			if shopState.owned[k.id] then
				if shopState.equipped ~= k.id then
					Net:FireServer({act = "equipnife", id = k.id})
				end
			else
				Net:FireServer({act = "buynife", id = k.id})
			end
		end)

		shopCells[k.id] = cell
	end
	refreshShop()
end

-- ------------------------------------------------------------
-- 抽獎機
-- ------------------------------------------------------------
local gachaFrame = Instance.new("Frame")
gachaFrame.Size = UDim2.new(0, 420, 0, 330)
gachaFrame.Position = UDim2.new(0.5, -210, 0.5, -165)
gachaFrame.BackgroundColor3 = Color3.fromRGB(45, 25, 35)
gachaFrame.BackgroundTransparency = 0.05
gachaFrame.Visible = false
gachaFrame.ZIndex = 20
styleRound(gachaFrame :: any, 14)
gachaFrame.Parent = gui

local gTitle = Instance.new("TextLabel")
gTitle.Size = UDim2.new(1, 0, 0, 46)
gTitle.BackgroundTransparency = 1
gTitle.TextColor3 = Color3.fromRGB(255, 150, 190)
gTitle.TextScaled = true
gTitle.Font = Enum.Font.SourceSansBold
gTitle.Text = "🎁 幸運扭蛋"
gTitle.ZIndex = 21
gTitle.Parent = gachaFrame

local gResult = Instance.new("TextLabel")
gResult.Size = UDim2.new(1, -30, 0, 90)
gResult.Position = UDim2.new(0, 15, 0, 60)
gResult.BackgroundColor3 = Color3.fromRGB(20, 15, 20)
gResult.BackgroundTransparency = 0.3
gResult.TextColor3 = Color3.new(1, 1, 1)
gResult.TextScaled = true
gResult.Font = Enum.Font.SourceSansBold
gResult.Text = "按下抽獎試試手氣！\n（¥150 一次，重複補償 ¥100）"
gResult.ZIndex = 21
styleRound(gResult :: any, 10)
gResult.Parent = gachaFrame

local gBtn = Instance.new("TextButton")
gBtn.Size = UDim2.new(0, 200, 0, 60)
gBtn.Position = UDim2.new(0.5, -100, 0, 170)
gBtn.BackgroundColor3 = Color3.fromRGB(230, 80, 120)
gBtn.TextColor3 = Color3.new(1, 1, 1)
gBtn.TextScaled = true
gBtn.Font = Enum.Font.SourceSansBold
gBtn.Text = "抽 獎 ¥150"
gBtn.ZIndex = 21
styleRound(gBtn :: any, 12)
gBtn.Parent = gachaFrame

local gClose = Instance.new("TextButton")
gClose.Size = UDim2.new(0, 40, 0, 40)
gClose.Position = UDim2.new(1, -50, 0, 8)
gClose.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
gClose.TextColor3 = Color3.new(1, 1, 1)
gClose.TextScaled = true
gClose.Font = Enum.Font.SourceSansBold
gClose.Text = "X"
gClose.ZIndex = 21
styleRound(gClose :: any, 8)
gClose.Parent = gachaFrame

local gachaSpinning = false
gBtn.Activated:Connect(function()
	if gachaSpinning then return end
	Net:FireServer({act = "gacha"})
end)
gClose.Activated:Connect(function()
	gachaFrame.Visible = false
end)

local function spinGacha(finalName: string, finalColor: Color3, dup: boolean)
	gachaSpinning = true
	local names = {"鋼鐵", "黑曜石", "雷霆", "櫻花", "冰霜", "阿斯特拉", "九頭蛇", "藍焰", "鳳凰"}
	for i = 1, 14 do
		gResult.Text = "🎲 " .. names[(i % #names) + 1]
		gResult.TextColor3 = Color3.fromHSV(math.random(), 0.7, 1)
		task.wait(0.08 + i * 0.02)
	end
	gResult.Text = (dup and "重複了！補償 ¥100\n" or "NEW! ") .. "🎉 恭喜獲得【" .. finalName .. "】"
	gResult.TextColor3 = finalColor
	gachaSpinning = false
end

-- ------------------------------------------------------------
-- 伺服器事件
-- ------------------------------------------------------------
Net.OnClientEvent:Connect(function(msg: any)
	if type(msg) ~= "table" then return end
	local act = msg.act
	local data = msg.data

	if act == "init" or act == "coins" then
		coinLabel.Text = "¥ " .. tostring(data)
		shopState.coins = tonumber(data) or shopState.coins
		refreshShop()
	elseif act == "status" then
		statusLabel.Text = tostring(data)
	elseif act == "mapinfo" then
		addFeed("🗺 本回合地圖：" .. tostring(data), Color3.fromRGB(140, 220, 255))
	elseif act == "killfeed" then
		local d = data :: any
		if d.killer and d.killer == plr.DisplayName then bumpStreak() end
		if d.by == "reflect" then
			addFeed("🗡 " .. d.killer .. " 反彈擊殺 " .. d.victim, Color3.fromRGB(255, 226, 130))
			addShake(0.3)
		elseif d.by == "ball" then
			addFeed("⚽ " .. d.victim .. " 被球撞飛了！", Color3.fromRGB(255, 150, 80))
		elseif d.by == "fall" then
			addFeed("💨 " .. d.victim .. " 掉出場外了！", Color3.fromRGB(150, 200, 255))
		elseif d.by == "knife" then
			addFeed("🗡 " .. d.killer .. " 斬殺了 " .. d.victim, Color3.fromRGB(255, 100, 100))
		elseif d.by == "item" then
			addFeed("✨ " .. d.killer .. " " .. d.victim, Color3.fromRGB(180, 150, 255))
		else
			addFeed("💀 " .. d.victim .. " 被淘汰", Color3.fromRGB(200, 200, 200))
		end
	elseif act == "winner" then
		statusLabel.Text = "🏆 " .. tostring(data) .. " 獲勝！"
	elseif act == "openshop" then
		Net:FireServer({act = "openshop"})
		shopFrame.Visible = true
	elseif act == "shopdata" then
		local d = data :: any
		shopState.coins = d.coins
		shopState.owned = d.owned
		shopState.equipped = d.equipped
		if #knifeList == 0 then
			knifeList = d.knives
			buildShopCells()
		else
			refreshShop()
		end
		coinLabel.Text = "¥ " .. tostring(d.coins)
	elseif act == "opengacha" then
		gachaFrame.Visible = true
	elseif act == "gacharesult" then
		local d = data :: any
		coinLabel.Text = "¥ " .. tostring(d.coins)
		shopState.coins = d.coins
		spinGacha(d.knife.name, d.knife.color, d.dup)
		Net:FireServer({act = "openshop"}) -- 拿最新擁有清單
	elseif act == "itemget" then
		local d = data :: any
		setSlots(d.items)
		showToast("🎁 開出【" .. d.name .. "】： " .. d.desc)
	elseif act == "items" then
		setSlots(data :: any)
	elseif act == "toast" then
		showToast(tostring(data))
	elseif act == "effect" then
		local d = data :: any
		if d.kind == "blind" then
			blind.Visible = true
			blind.BackgroundTransparency = 1
			TweenService:Create(blind, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
			task.delay(d.t - 0.6, function()
				TweenService:Create(blind, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play()
				task.wait(0.65)
				blind.Visible = false
			end)
		elseif d.kind == "speed" then
			showToast("💨 疾風加速 6 秒！")
		end
	elseif act == "hurt" then
		addShake(0.5)
		hurtFlash.Visible = true
		hurtFlash.BackgroundTransparency = 0.55
		TweenService:Create(hurtFlash, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		task.delay(0.45, function() hurtFlash.Visible = false end)
	elseif act == "hitsuccess" then
		floatText("🗡 -20", Color3.fromRGB(255, 238, 160))
		addShake(0.2)
	elseif act == "deflect" then
		bigBanner("REFLECT!", Color3.fromRGB(140, 244, 255), 0.85)
		floatText("🛡 反彈 x" .. tostring(data), Color3.fromRGB(150, 245, 255))
		addShake(0.45)
	elseif act == "reflectkill" then
		local d = data :: any
		bigBanner("反殺 " .. tostring(d.name), Color3.fromRGB(255, 218, 120), 1.2)
		floatText("💰 +15", Color3.fromRGB(255, 214, 92))
		addShake(0.65)
	elseif act == "ballwarn" then
		local d = data :: any
		ballWarn(tostring(d.name), Color3.fromRGB(d.r, d.g, d.b))
	end
end)

showToast("歡迎來到躲避球大亂鬥！靠近櫃檯買刀＆抽獎")

