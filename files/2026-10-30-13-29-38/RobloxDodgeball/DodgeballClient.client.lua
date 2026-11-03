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

-- 不參加回合按鈕（左上、金幣下面）：開了之後回合開始不會被傳送進場
local spectateBtn = Instance.new("TextButton")
spectateBtn.Size = UDim2.new(0, 150, 0, 30)
spectateBtn.Position = UDim2.new(0, 10, 0, 46)
spectateBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
spectateBtn.BackgroundTransparency = 0.35
spectateBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
spectateBtn.TextScaled = true
spectateBtn.Font = Enum.Font.SourceSansBold
spectateBtn.Text = "😴 不參加：關"
styleRound(spectateBtn :: any, 10)
spectateBtn.Parent = gui
local spectating = false
spectateBtn.MouseButton1Click:Connect(function()
	spectating = not spectating
	if spectating then
		spectateBtn.Text = "😴 不參加：開"
		spectateBtn.TextColor3 = Color3.fromRGB(255, 170, 90)
		spectateBtn.BackgroundColor3 = Color3.fromRGB(70, 40, 20)
	else
		spectateBtn.Text = "😴 不參加：關"
		spectateBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
		spectateBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	end
	Net:FireServer({act = "spectate", on = spectating})
end)

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
-- 軍械庫商店（現代化雙欄 3D 實體模型預覽與真實戰鬥數值）
-- ------------------------------------------------------------
local shopFrame = Instance.new("Frame")
shopFrame.Size = UDim2.new(0, 760, 0, 480)
shopFrame.Position = UDim2.new(0.5, -380, 0.5, -240)
shopFrame.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
shopFrame.BackgroundTransparency = 0.05
shopFrame.Visible = false
shopFrame.ZIndex = 20
styleRound(shopFrame :: any, 14)
shopFrame.Parent = gui

local shopTitle = Instance.new("TextLabel")
shopTitle.Size = UDim2.new(0, 260, 0, 36)
shopTitle.Position = UDim2.new(0, 20, 0, 10)
shopTitle.BackgroundTransparency = 1
shopTitle.TextColor3 = Color3.fromRGB(255, 220, 110)
shopTitle.TextScaled = true
shopTitle.Font = Enum.Font.GothamBold
shopTitle.Text = "⚔️ 武器軍械庫"
shopTitle.ZIndex = 21
shopTitle.Parent = shopFrame

local shopSub = Instance.new("TextLabel")
shopSub.Size = UDim2.new(0, 300, 0, 20)
shopSub.Position = UDim2.new(0, 22, 0, 44)
shopSub.BackgroundTransparency = 1
shopSub.TextColor3 = Color3.fromRGB(160, 165, 178)
shopSub.TextSize = 13
shopSub.Font = Enum.Font.SourceSans
shopSub.Text = "裝備神兵利器 · 提升揮刀判定與對決傷害"
shopSub.ZIndex = 21
shopSub.Parent = shopFrame

local shopCoins = Instance.new("TextLabel")
shopCoins.Size = UDim2.new(0, 180, 0, 32)
shopCoins.Position = UDim2.new(1, -250, 0, 14)
shopCoins.BackgroundTransparency = 1
shopCoins.TextColor3 = Color3.fromRGB(255, 215, 90)
shopCoins.TextSize = 22
shopCoins.Font = Enum.Font.GothamBold
shopCoins.Text = "💰 ¥ 0"
shopCoins.ZIndex = 21
shopCoins.Parent = shopFrame

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(0, 36, 0, 36)
shopClose.Position = UDim2.new(1, -50, 0, 12)
shopClose.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
shopClose.TextColor3 = Color3.new(1, 1, 1)
shopClose.TextSize = 20
shopClose.Font = Enum.Font.GothamBold
shopClose.Text = "✕"
shopClose.ZIndex = 21
styleRound(shopClose :: any, 8)
shopClose.Parent = shopFrame
shopClose.Activated:Connect(function()
	shopFrame.Visible = false
end)

-- 左側武器卡片滾動列表
local listScroll = Instance.new("ScrollingFrame")
listScroll.Size = UDim2.new(0, 320, 1, -78)
listScroll.Position = UDim2.new(0, 16, 0, 68)
listScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
listScroll.BackgroundTransparency = 0.5
listScroll.BorderSizePixel = 0
listScroll.ScrollBarThickness = 6
listScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 85, 100)
listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
listScroll.ZIndex = 21
styleRound(listScroll :: any, 10)
listScroll.Parent = shopFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listScroll

-- 右側 3D 預覽與屬性詳情面板
local detailPanel = Instance.new("Frame")
detailPanel.Size = UDim2.new(1, -370, 1, -78)
detailPanel.Position = UDim2.new(0, 352, 0, 68)
detailPanel.BackgroundColor3 = Color3.fromRGB(18, 20, 25)
detailPanel.BackgroundTransparency = 0.5
detailPanel.ZIndex = 21
styleRound(detailPanel :: any, 10)
detailPanel.Parent = shopFrame

-- 3D 視窗
local vp = Instance.new("ViewportFrame")
vp.Size = UDim2.new(1, -20, 0, 175)
vp.Position = UDim2.new(0, 10, 0, 10)
vp.BackgroundColor3 = Color3.fromRGB(12, 13, 17)
vp.BackgroundTransparency = 0.3
vp.BorderSizePixel = 0
vp.ZIndex = 22
styleRound(vp :: any, 8)
vp.Parent = detailPanel

local vpCam = Instance.new("Camera")
vpCam.FieldOfView = 50
vp.CurrentCamera = vpCam
vpCam.Parent = vp

-- 詳情文字
local detName = Instance.new("TextLabel")
detName.Size = UDim2.new(1, -20, 0, 30)
detName.Position = UDim2.new(0, 10, 0, 192)
detName.BackgroundTransparency = 1
detName.TextColor3 = Color3.fromRGB(255, 230, 120)
detName.TextSize = 22
detName.Font = Enum.Font.GothamBold
detName.TextXAlignment = Enum.TextXAlignment.Left
detName.ZIndex = 22
detName.Parent = detailPanel

local detStats = Instance.new("TextLabel")
detStats.Size = UDim2.new(1, -20, 0, 68)
detStats.Position = UDim2.new(0, 10, 0, 224)
detStats.BackgroundTransparency = 1
detStats.TextColor3 = Color3.fromRGB(220, 225, 235)
detStats.TextSize = 14
detStats.Font = Enum.Font.SourceSans
detStats.TextXAlignment = Enum.TextXAlignment.Left
detStats.TextYAlignment = Enum.TextYAlignment.Top
detStats.TextWrapped = true
detStats.ZIndex = 22
detStats.Parent = detailPanel

local detDesc = Instance.new("TextLabel")
detDesc.Size = UDim2.new(1, -20, 0, 40)
detDesc.Position = UDim2.new(0, 10, 0, 294)
detDesc.BackgroundTransparency = 1
detDesc.TextColor3 = Color3.fromRGB(180, 205, 240)
detDesc.TextSize = 13
detDesc.Font = Enum.Font.SourceSansItalic
detDesc.TextXAlignment = Enum.TextXAlignment.Left
detDesc.TextYAlignment = Enum.TextYAlignment.Top
detDesc.TextWrapped = true
detDesc.ZIndex = 22
detDesc.Parent = detailPanel

-- 底部操作按鈕
local actionBtn = Instance.new("TextButton")
actionBtn.Size = UDim2.new(1, -20, 0, 44)
actionBtn.Position = UDim2.new(0, 10, 1, -54)
actionBtn.BackgroundColor3 = Color3.fromRGB(60, 160, 80)
actionBtn.TextColor3 = Color3.new(1, 1, 1)
actionBtn.TextSize = 18
actionBtn.Font = Enum.Font.GothamBold
actionBtn.ZIndex = 22
styleRound(actionBtn :: any, 8)
actionBtn.Parent = detailPanel

-- 內部狀態
local shopCells: {[string]: Frame} = {}
local knifeList: {{[string]: any}} = {}
local shopState = {coins = 0, owned = {}, equipped = "steel"}
local selectedKnifeId = "steel"
local previewModel: Model? = nil

local TIER_NAMES = {"[T1 基礎]", "[T2 堅毅]", "[T3 精銳]", "[T4 史詩]", "[T5 傳說]", "[T6 神話]"}
local TIER_COLORS = {
	Color3.fromRGB(180, 185, 195),
	Color3.fromRGB(100, 180, 255),
	Color3.fromRGB(160, 110, 255),
	Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(255, 180, 60),
	Color3.fromRGB(255, 60, 60),
}


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

-- 建立 3D 實體模型
local function make3DKnife(k: {[string]: any}): Model
	local m = Instance.new("Model")
	m.Name = "Preview_" .. tostring(k.id)
	buildKnifeParts(m, tostring(k.id), false)
	return m
end

local function selectKnife(id: string)
	selectedKnifeId = id
	local k: {[string]: any}?
	for _, item in ipairs(knifeList) do
		if item.id == id then k = item break end
	end
	if not k then return end

	-- 更新 3D 預覽模型
	if previewModel then previewModel:Destroy() end
	previewModel = make3DKnife(k)
	previewModel.Parent = vp

	-- 更新詳情文字
	local tier = math.clamp(k.tier or 1, 1, 6)
	detName.Text = (TIER_NAMES[tier] or "") .. " " .. tostring(k.name) .. "之刃"
	detName.TextColor3 = k.color or Color3.new(1, 1, 1)

	detStats.Text = string.format(
		"⚔️ 近戰傷害: %d 點 (聯機打人扣血)\n⚡ 反彈倍率: x%.2f 倍 (球速加成)\n🎯 判定範圍: %.1f 格 (更易擊中球)",
		k.dmg or 25,
		k.reflectMul or 1.25,
		k.reach or 22
	)

	detDesc.Text = "🌟 專屬神技【" .. tostring(k.skill or "無") .. "】: " .. tostring(k.desc or "標準刀刃")

	-- 更新操作按鈕
	local isOwned = shopState.owned[id]
	local isEquipped = (shopState.equipped == id)

	if isEquipped then
		actionBtn.Text = "✓ 當前已裝備"
		actionBtn.BackgroundColor3 = Color3.fromRGB(45, 75, 50)
		actionBtn.TextColor3 = Color3.fromRGB(160, 220, 170)
	elseif isOwned then
		actionBtn.Text = "裝備此神兵"
		actionBtn.BackgroundColor3 = Color3.fromRGB(45, 120, 200)
		actionBtn.TextColor3 = Color3.new(1, 1, 1)
	else
		local canBuy = shopState.coins >= (k.price or 0)
		actionBtn.Text = string.format("購買神兵 (¥ %d)", k.price or 0)
		actionBtn.BackgroundColor3 = canBuy and Color3.fromRGB(200, 140, 40) or Color3.fromRGB(110, 60, 50)
		actionBtn.TextColor3 = canBuy and Color3.fromRGB(255, 245, 220) or Color3.fromRGB(230, 170, 170)
	end

	-- 高亮左側選中卡片
	for cId, cell in pairs(shopCells) do
		if cId == id then
			cell.BackgroundColor3 = Color3.fromRGB(45, 52, 68)
		else
			cell.BackgroundColor3 = Color3.fromRGB(26, 29, 36)
		end
	end
end

actionBtn.Activated:Connect(function()
	if not selectedKnifeId then return end
	if shopState.owned[selectedKnifeId] then
		if shopState.equipped ~= selectedKnifeId then
			Net:FireServer({act = "equipnife", id = selectedKnifeId})
		end
	else
		Net:FireServer({act = "buynife", id = selectedKnifeId})
	end
end)

-- 3D 刀刃平滑旋轉
task.spawn(function()
	local t0 = os.clock()
	while true do
		task.wait(0.03)
		if shopFrame.Visible and previewModel and previewModel.PrimaryPart then
			local elapsed = os.clock() - t0
			previewModel:PivotTo(CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(18), elapsed * 1.4, math.rad(-14)))
			vpCam.CFrame = CFrame.lookAt(Vector3.new(0, 1.8, 4.3), Vector3.new(0, 1.8, 0))
		end
	end
end)

local function refreshShop()
	shopCoins.Text = "💰 ¥ " .. shopState.coins
	for _, k in ipairs(knifeList) do
		local cell = shopCells[k.id]
		if cell then
			local stLabel = cell:FindFirstChild("ST") :: TextLabel?
			if stLabel then
				if shopState.owned[k.id] then
					if shopState.equipped == k.id then
						stLabel.Text = "✓ 已裝備"
						stLabel.TextColor3 = Color3.fromRGB(110, 240, 130)
					else
						stLabel.Text = "已擁有"
						stLabel.TextColor3 = Color3.fromRGB(180, 210, 240)
					end
				else
					stLabel.Text = "¥ " .. k.price
					stLabel.TextColor3 = (shopState.coins >= k.price) and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(240, 110, 110)
				end
			end
		end
	end
	selectKnife(selectedKnifeId or (knifeList[1] and knifeList[1].id or "steel"))
end

local function buildShopCells()
	for _, child in ipairs(listScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	shopCells = {}

	local rowH = 68
	local totalH = #knifeList * (rowH + 8)
	listScroll.CanvasSize = UDim2.new(0, 0, 0, totalH)

	for idx, k in ipairs(knifeList) do
		local tier = math.clamp(k.tier or 1, 1, 6)
		local cell = Instance.new("Frame")
		cell.Name = k.id
		cell.LayoutOrder = idx
		cell.Size = UDim2.new(1, -12, 0, rowH)
		cell.BackgroundColor3 = Color3.fromRGB(26, 29, 36)
		cell.ZIndex = 22
		styleRound(cell :: any, 8)
		cell.Parent = listScroll

		-- 等級角標
		local tierBadge = Instance.new("TextLabel")
		tierBadge.Size = UDim2.new(0, 42, 0, 22)
		tierBadge.Position = UDim2.new(0, 8, 0, 10)
		tierBadge.BackgroundColor3 = TIER_COLORS[tier] or Color3.fromRGB(150, 150, 150)
		tierBadge.TextColor3 = Color3.fromRGB(20, 20, 25)
		tierBadge.TextSize = 12
		tierBadge.Font = Enum.Font.GothamBold
		tierBadge.Text = "T" .. tier
		tierBadge.ZIndex = 23
		styleRound(tierBadge :: any, 4)
		tierBadge.Parent = cell

		-- 武器名稱
		local nm = Instance.new("TextLabel")
		nm.Name = "KN"
		nm.Size = UDim2.new(0, 150, 0, 24)
		nm.Position = UDim2.new(0, 56, 0, 8)
		nm.BackgroundTransparency = 1
		nm.TextColor3 = k.color or Color3.new(1, 1, 1)
		nm.TextSize = 16
		nm.Font = Enum.Font.GothamBold
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.Text = tostring(k.name) .. "之刃"
		nm.ZIndex = 23
		nm.Parent = cell

		-- 屬性數值行（傷害 | 反彈 | 判定）
		local statsRow = Instance.new("TextLabel")
		statsRow.Size = UDim2.new(1, -64, 0, 20)
		statsRow.Position = UDim2.new(0, 10, 0, 38)
		statsRow.BackgroundTransparency = 1
		statsRow.TextColor3 = Color3.fromRGB(160, 170, 185)
		statsRow.TextSize = 12
		statsRow.Font = Enum.Font.SourceSans
		statsRow.TextXAlignment = Enum.TextXAlignment.Left
		statsRow.Text = string.format("傷 %d · 反彈 x%.1f · 判定 %d", k.dmg or 25, k.reflectMul or 1.25, k.reach or 22)
		statsRow.ZIndex = 23
		statsRow.Parent = cell

		-- 擁有/價格狀態
		local st = Instance.new("TextLabel")
		st.Name = "ST"
		st.Size = UDim2.new(0, 80, 0, 24)
		st.Position = UDim2.new(1, -88, 0, 8)
		st.BackgroundTransparency = 1
		st.TextSize = 14
		st.Font = Enum.Font.GothamBold
		st.TextXAlignment = Enum.TextXAlignment.Right
		st.Text = ""
		st.ZIndex = 23
		st.Parent = cell

		-- 點擊卡片選中預覽
		local clickBtn = Instance.new("TextButton")
		clickBtn.Size = UDim2.new(1, 0, 1, 0)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.ZIndex = 24
		clickBtn.Parent = cell
		clickBtn.Activated:Connect(function()
			selectKnife(k.id)
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
		if d.by == "ball" then
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
		hurtFlash.Visible = true
		hurtFlash.BackgroundTransparency = 0.55
		TweenService:Create(hurtFlash, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		task.delay(0.45, function() hurtFlash.Visible = false end)
	elseif act == "hitsuccess" then
		showToast("🗡 命中！")
	end
end)

showToast("歡迎來到躲避球大亂鬥！靠近櫃檯買刀＆抽獎")

