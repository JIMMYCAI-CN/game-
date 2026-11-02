--[[
	=========================================================
	 AnimationForge  （在 Studio 的 Command Bar 執行，不是放到遊戲裡）
	---------------------------------------------------------
	 用法：
	  1. Studio 上方 View（檢視）→ Command Bar（命令列）
	  2. 把這整份貼進下面那條輸入框，按 Enter
	  3. 看 Output（輸出）視窗，會印出：
	        [AnimationForge] Combo_RightPunch -> rbxassetid://1234567890
	  4. 把那個 id 貼進 CharacterMovesClient 的 CONFIG.AnimationIds 就能用

	 這支做的事情：
	   - 用程式「擺姿勢」組出 KeyframeSequence（每個 Pose 就是一個關節的旋轉）
	   - 直接呼叫 KeyframeSequenceProvider:RegisterKeyframeSequence 上傳成動畫資產
	   - 若你的 Studio 版本不給上傳，會自動把 KeyframeSequence 丟進 ReplicatedStorage，
	     你再右鍵 → Save to File / 用 Animation Editor 開起來微調後 Publish

	 ⚠ 角度是我估的「起始值」，不是動畫師雕過的成品。
	   執行後先在 Animation Editor 預覽，正負號不對就把對應數字改號即可（註解有說明方向）。
	=========================================================
]]

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 角度 → CFrame（單位：度）
local function rot(x, y, z)
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

--[[
	姿勢表說明（R15 骨架，Pose 名稱 = 身體部位名稱）：
	  UpperTorso      腰部扭轉（Y 正 = 向左轉、Y 負 = 向右轉）
	  RightUpperArm   右大臂（X 負 = 往前抬、X 正 = 往後、Z 負 = 往外張）
	  RightLowerArm   右小臂／手肘（X 負 = 彎曲）
	  LeftUpperArm / LeftLowerArm  左邊同理（Z 正 = 往外張）
	  Head            頭（X 正 = 低頭、Y 正 = 轉向左）
	若預覽時方向相反，把該軸數字改正負號就好。
]]

local ANIMATIONS = {
	------------------------------------------------------------------
	-- 示範 1：右直拳（0.38 秒，可接在 F 攻擊上）
	------------------------------------------------------------------
	{
		Name = "Combo_RightPunch",
		Loop = false,
		Priority = Enum.AnimationPriority.Action,

		Keyframes = {
			-- 0.00 架式
			{
				Time = 0.00,
				Pose = {
					UpperTorso = rot(0, -25, 0),
					Head = rot(0, 15, 0),
					RightUpperArm = rot(-60, 0, -35),
					RightLowerArm = rot(-85, 0, 0),
					LeftUpperArm = rot(-70, 0, 30),
					LeftLowerArm = rot(-95, 0, 0),
				},
			},
			-- 0.09 收拳蓄力（身體往右轉、右拳拉到腰側）
			{
				Time = 0.09,
				Pose = {
					UpperTorso = rot(0, -40, 0),
					Head = rot(0, 25, 0),
					RightUpperArm = rot(-25, 0, -45),
					RightLowerArm = rot(-115, 0, 0),
					LeftUpperArm = rot(-60, 0, 35),
					LeftLowerArm = rot(-100, 0, 0),
				},
			},
			-- 0.20 出拳命中（身體回正、右手打直）
			{
				Time = 0.20,
				Pose = {
					UpperTorso = rot(0, 20, 0),
					Head = rot(0, -5, 0),
					RightUpperArm = rot(-95, 0, -5),
					RightLowerArm = rot(-5, 0, 0),
					LeftUpperArm = rot(-45, 0, 40),
					LeftLowerArm = rot(-120, 0, 0),
					RightUpperLeg = rot(-10, 0, 0),
					LeftUpperLeg = rot(10, 0, 0),
				},
				EasingStyle = Enum.PoseEasingStyle.Quad,
				EasingDirection = Enum.PoseEasingDirection.Out,
			},
			-- 0.38 收招回架式
			{
				Time = 0.38,
				Pose = {
					UpperTorso = rot(0, -25, 0),
					Head = rot(0, 15, 0),
					RightUpperArm = rot(-60, 0, -35),
					RightLowerArm = rot(-85, 0, 0),
					LeftUpperArm = rot(-70, 0, 30),
					LeftLowerArm = rot(-95, 0, 0),
				},
			},
		},
	},

	------------------------------------------------------------------
	-- 示範 2：受擊後仰（0.45 秒，被打到時播）
	------------------------------------------------------------------
	{
		Name = "Hit_React",
		Loop = false,
		Priority = Enum.AnimationPriority.Action,

		Keyframes = {
			{
				Time = 0.00,
				Pose = {
					UpperTorso = rot(0, 0, 0),
					Head = rot(0, 0, 0),
				},
			},
			{
				Time = 0.08,
				Pose = {
					UpperTorso = rot(-20, 0, 8),   -- 上身後仰
					Head = rot(-15, 0, 0),
					RightUpperArm = rot(-30, 0, -50),
					LeftUpperArm = rot(-30, 0, 50),
					RightUpperLeg = rot(8, 0, 0),
					LeftUpperLeg = rot(-8, 0, 0),
				},
				EasingStyle = Enum.PoseEasingStyle.Quad,
				EasingDirection = Enum.PoseEasingDirection.Out,
			},
			{
				Time = 0.45,
				Pose = {
					UpperTorso = rot(0, 0, 0),
					Head = rot(0, 0, 0),
					RightUpperArm = rot(0, 0, 0),
					LeftUpperArm = rot(0, 0, 0),
					RightUpperLeg = rot(0, 0, 0),
					LeftUpperLeg = rot(0, 0, 0),
				},
			},
		},
	},
}

--============================ 產生 KeyframeSequence ============================
local function buildKeyframeSequence(def)
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = def.Name
	sequence.Loop = def.Loop or false
	sequence.Priority = def.Priority or Enum.AnimationPriority.Action

	for _, keyframeDef in ipairs(def.Keyframes) do
		local keyframe = Instance.new("Keyframe")
		keyframe.Name = string.format("KF_%.2f", keyframeDef.Time)
		keyframe.Time = keyframeDef.Time

		local easingStyle = keyframeDef.EasingStyle or Enum.PoseEasingStyle.Cubic
		local easingDirection = keyframeDef.EasingDirection or Enum.PoseEasingDirection.InOut

		for partName, poseCFrame in pairs(keyframeDef.Pose) do
			local pose = Instance.new("Pose")
			pose.Name = partName
			pose.CFrame = poseCFrame
			pose.Weight = keyframeDef.Weight or 1
			pose.EasingStyle = easingStyle
			pose.EasingDirection = easingDirection
			pose.Parent = keyframe
		end

		keyframe.Parent = sequence
	end

	return sequence
end

--============================ 上傳 ============================
local uploaded = {}

for _, def in ipairs(ANIMATIONS) do
	local sequence = buildKeyframeSequence(def)

	local ok, result = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
	end)

	if ok and typeof(result) == "string" and result ~= "" then
		local id = "rbxassetid://" .. tostring(result):gsub("rbxassetid://", "")
		table.insert(uploaded, { name = def.Name, id = id })
		print(("[AnimationForge] 上傳成功：%s -> %s"):format(def.Name, id))
		sequence:Destroy()
	else
		sequence.Parent = ReplicatedStorage
		warn(("[AnimationForge] %s 無法自動上傳（%s）。已放進 ReplicatedStorage.%s，"
			.. "請選取它右鍵 Save to File，或用 Animation Editor 開起來微調後 Publish 取得 id。")
			:format(def.Name, tostring(result), def.Name))
	end
end

--============================ 結果摘要（可直接複製） ============================
print("------------------------------------------------------------")
if #uploaded == 0 then
	print("[AnimationForge] 沒有成功上傳任何動畫，請看上面的警告訊息。")
else
	print("[AnimationForge] 把下面這幾行貼進 CharacterMovesClient 的 CONFIG.AnimationIds：")
	for _, item in ipairs(uploaded) do
		print(string.format('\t%s = "%s",', item.name, item.id))
	end
end
print("------------------------------------------------------------")
