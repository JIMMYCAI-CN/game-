# Roblox 角色動作系統（走路 / 跑步 / 滑剷 / 攻擊 / 二段跳 / 快閃 / 左右閃身）

八組動作 ID 已全部接上：跑步和滑剷有「加速 + 畫面 FOV 拉寬」的衝刺感，攻擊會真的扣血，二段跳會向上再彈一次，快閃往前位移，Q / R 左右閃身。

| 動作 | 動畫 ID | 觸發方式 | 效果 |
|---|---|---|---|
| 走路 | 119174241724731 | 平常移動（自動） | 取代原本的走路動畫 |
| 跑步 | 128677818236008 | 按住 **Shift** + 移動 | 速度 16 → 34，FOV 70 → 88（畫面拉長） |
| 滑剷 | 113527499571998 | 按 **C**（需在地面且正在移動） | 沿當前方向真的往前滑出去，速度 60，FOV 瞬間拉到 104 |
| 攻擊 | 113532863616074 | 按 **F** | 播放攻擊動作 → 伺服器判定 → 面前 5.5×5×5.5 範圍內敵人扣 20 血 |
| 二段跳 | 78281951371423 | 空中再按一次 **空白鍵** | 播放二段跳動作 + 向上速度 62（約再跳 10 格），落地才重置 |
| 快閃 | 138926327377619 | 按 **E** | 播放快閃動作 + 0.18 秒內向前位移 20 格，FOV 拉到 100，1.5 秒冷卻 |
| 左閃身 | 127771728638518 | 按 **R** | 朝角色左方橫移 8 格（0.16 秒），冷卻 0.9 秒 |
| 右閃身 | 109449343171378 | 按 **Q** | 朝角色右方橫移 8 格（0.16 秒），冷卻 0.9 秒 |

---

## ⚠ 先看這段：怎麼確認腳本有沒有在跑

按 **Play** 之後打開 **View → Output**，正常應該依序看到：

```
[CharacterMoves] 伺服器腳本已啟動 ✔ (RemoteEvent: CharacterMoves.AttackRequest)
[CharacterMoves] 客戶端腳本已啟動 ✔
[CharacterMoves] 攻擊用 RemoteEvent 已就緒
[CharacterMoves] 角色就緒：你的名字｜骨架 R15｜載入 11/11 個動畫
```

之後每個動作都會印一行：`滑剷 開始`／`快閃 開始（距離 xx 格）`／`左閃身 開始（距離 xx 格）`／`二段跳 觸發`／`攻擊 播放`。

**完全沒有第一行 = 腳本根本沒執行**，99% 是下面三件事之一：
1. **型別錯了**：客戶端那支必須是 **LocalScript**（貼到 Script 裡會直接報 `assert` 錯誤，Output 紅字）。
2. **位置錯了**：必須在 `StarterPlayer > StarterPlayerScripts`，不是 Workspace、不是 StarterCharacterScripts。
3. **沒有按 Play**：`StarterPlayerScripts` 的內容只在按下 Play 時才複製到玩家身上，在編輯模式看不到效果。

**有看到「載入 0/9 個動畫」**：腳本在跑，但動畫 ID 載不進來（資產權限問題）→ 位移、加速、FOV 都正常，只是沒動作。

---

## 安裝步驟（3 分鐘）

1. **伺服器腳本**
   `ServerScriptService` → 新增 **Script**，命名 `CharacterMovesServer`
   把 `CharacterMovesServer.server.lua` 的內容整段貼進去。

2. **客戶端腳本**
   `StarterPlayer` → `StarterPlayerScripts` → 新增 **LocalScript**，命名 `CharacterMovesClient`
   把 `CharacterMovesClient.client.lua` 的內容整段貼進去。

3. **角色設定（很重要）**
   `StarterPlayer` → 屬性：
   - `Avatar Type` = **R15**（滑剷動畫是 R15 骨架，用 R6 會播不出來或變形）
   - `Character Walk Speed` 保持 16 即可，腳本會自己接管

4. 按 **Play** 測試：
   - 走動 → 走路動畫
   - 按住 Shift 跑 → 加速 + 畫面變寬
   - 跑動中按 C → 往前滑出去（不是原地）
   - 走到 Dummy 前面按 F → Dummy 掉血
   - 跳起來後在空中再按一次空白鍵 → 二段跳（向上再彈一次）
   - 按 E → 向前快閃一段距離
   - 按 R / Q → 向左 / 向右閃身一小段

---

## 想調整的地方

### 速度 / 衝刺感（客戶端腳本最上方 `CONFIG`）
```lua
WalkSpeed  = 16,    -- 走路速度
RunSpeed   = 34,    -- 跑步速度，想更猛可改 40
SlideSpeed = 60,    -- 滑剷初速

BaseFov  = 70,      -- 平常視角
RunFov   = 88,      -- 跑步視角（越大衝刺感越強）
SlideFov = 104,     -- 滑剷視角（瞬間拉最寬）
FovSmooth = 8,      -- 鏡頭切換快慢，越小越柔
```
覺得「還不夠快」的標準調法：`RunSpeed` +6、`RunFov` +6、`FovSmooth` +2。

### 滑剷手感
```lua
SlideDuration = 0.62,        -- 滑多久
SlideCooldown = 1.2,         -- 冷卻
SlideEndSpeedFactor = 0.55,  -- 後段剩幾成速度（1 = 全程不減速）
```
想要「衝刺型滑剷」就把 `SlideEndSpeedFactor` 調到 0.85，`SlideDuration` 調到 0.8。

### 二段跳手感
```lua
DoubleJumpVelocity = 62,  -- 第二次跳的向上速度（50 ≈ 6.4 格、62 ≈ 10 格、75 ≈ 14 格）
DoubleJumpMaxCount = 1,   -- 額外可跳幾次：1 = 二段跳、2 = 三段跳
```
改成 2 就變三段跳（第三次在最高點再按，會再往上彈）。

### 快閃手感（E）
```lua
DashDistance = 20,    -- 往前幾格
DashDuration = 0.18,  -- 花多久（0.05 ≈ 瞬移、0.3 ≈ 貼地衝刺）
DashCooldown = 1.5,
DashFov = 100,        -- 快閃時的視角
DashStopBuffer = 1.5, -- 前方有牆時停在牆前幾格
```
快閃會先往前打射線，前面有牆就自動縮短距離（不會穿牆、不會卡進牆裡）。

### 左右閃身（Q / R）
```lua
DodgeDistance = 8,     -- 橫移幾格（想更遠改 12~15）
DodgeDuration = 0.16,  -- 花多久（0.05 ≈ 瞬間側閃）
DodgeCooldown = 0.9,
```
閃身方向是「角色自身的左右」（`RightVector`），所以面向哪就閃哪邊的左右。
如果覺得方向反了，把按鍵互換即可：
```lua
LeftDodgeKey = Enum.KeyCode.R,    -- 向左閃身
RightDodgeKey = Enum.KeyCode.Q,   -- 向右閃身
```
把 `startDodge(-1)` 和 `startDodge(1)` 對調也會有一樣效果。

### 想「一移動就自動跑」（不用按 Shift）
客戶端 `CONFIG` 裡把 `AutoSprint = false` 改成 `true`，走路動畫就只會在慢速時出現、移動即跑步＋衝刺感。

### 傷害
伺服器腳本 `CONFIG`：
```lua
Damage = 20,
Cooldown = 0.5,
HitboxSize = Vector3.new(5.5, 5, 5.5),
HitboxForward = 3.2,
```
想做大劍範圍技就把 `HitboxSize` 加大、`MaxTargets` 提高。

### 換按鍵
客戶端 `CONFIG` 最下方：
```lua
SprintKey = Enum.KeyCode.LeftShift,
SlideKey  = Enum.KeyCode.C,
AttackKey = Enum.KeyCode.F,
JumpKey   = Enum.KeyCode.Space,
DashKey   = Enum.KeyCode.E,
LeftDodgeKey  = Enum.KeyCode.R,
RightDodgeKey = Enum.KeyCode.Q,
```
（滑剷想改成 Ctrl 就寫 `Enum.KeyCode.LeftControl`）

---

## 運作原理（怕你之後要改）

- 客戶端腳本會**關掉角色內建的 Animate 腳本**（`Animate.Disabled = true`），移動動畫完全自己控。
- 但關掉前先讀走原本 Animate 裡的 **待機 / 跳躍 / 落下** 動畫 ID，所以站立、跳躍還是原本的樣子，R6、R15 都通用。
- 滑剷不是「站在原地做動作」：腳本在滑行期間把 `WalkSpeed` 設 0、鎖住自動轉向，然後每一幀直接把 `HumanoidRootPart.AssemblyLinearVelocity` 朝前方灌速度（保留 Y 軸重力，所以不會浮空），時間到自動結束。
- 二段跳靠 `Humanoid.StateChanged` 記次數：起跳時 `jumpsUsed = 1`，空中再按空白鍵就把 Y 速度直接設成 `DoubleJumpVelocity`（同時 `humanoid.Jump = false` 清掉預設跳躍請求，避免落地瞬間又自動跳一次），落地（Landed / Running）才歸零並收掉二段跳動作。
- 快閃同樣是速度注入，但會先往前打一條射線，撞到牆就把距離縮短到牆前 `DashStopBuffer` 格，所以不會穿牆。
- 攻擊一定走伺服器：客戶端只負責播動畫 + 發 `RemoteEvent`，傷害、判定框、冷卻都在伺服器算，避免外掛直接刷傷害。滑剷／快閃期間按 F 會被忽略。

---

## 常見問題

**動畫播不出來 / 角色擺 T-pose？**
Roblox 的動畫資產有權限限制：動畫必須是**你自己或你的群組**上傳的，或該資產已設為公開。若是在別人的遊戲/工具箱拿到的 ID，可能載入失敗（Output 會印 `[CharacterMoves] 動畫載入失敗`）。解法：用 Animation Editor 重新上傳一份自己的。

**角色是 R6 的話？**
這幾組 ID 看起來是 R15 骨架的動作，R6 角色套上去會播不動（但加速、FOV、位移、扣血都還是有效）。要完整效果請把 `StarterPlayer > Avatar Type` 設成 **R15**，或用 `Avatar > Rig Builder` 換成 R15 角色。

**滑剷沒有往前衝？**
1. 確認 `humanoid.FloorMaterial` 不是 Air（空中不能滑）。
2. 確認你是「有移動輸入」的狀態下按 C。
3. 如果你有其他角色控制腳本也在每幀設 `WalkSpeed`，會互相打架，把那邊的覆寫關掉。

**按 F 沒扣血？**
1. 確認 `CharacterMovesServer` 放在 `ServerScriptService`（不是 StarterPlayer）。
2. 確認打得夠近（預設前方 3.2 + 判定框深度，約 6 格內）。
3. 打 Dummy 測試時，Dummy 的 Humanoid 要存在（`Dummy` 預設有）。

**二段跳沒反應？**
1. 一定要「先跳一次」再按第二次空白鍵（走路掉落懸崖不算，`jumpsUsed` 還是 0）。
2. 如果你有改 `Humanoid.JumpHeight`/`JumpPower`，二段跳高度由 `DoubleJumpVelocity` 獨立控制，可自行對齊。
3. 角色如果貼在天花板下，向上速度會被擋住，看起來就像沒跳。

**按 E 沒位移？**
1. 冷卻中（預設 1.5 秒），或正前方 0.5 格內就是牆。
2. 如果 `DashDuration` 設得跟幀率一樣短（例如 0.02），可能只移動 1～2 幀，建議 0.1 以上比較穩。
3. 滑剷中不能快閃（兩個都用速度注入，會打架）。

**手機 / 手把要玩？**
目前只綁鍵盤。要支援的話，把 `InputBegan` 那段換成 `ContextActionService:BindAction`，或在手機上加 UI 按鈕呼叫同一組 `startSlide()` / `startDash()` / `tryDoubleJump()` / `doAttack()` 即可。
