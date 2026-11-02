# 躲避球刺客 · Dodgeball Assassin（Roblox）

> 圆环浮空竞技场 · 7 种躲避球 · 刀能反弹球 · 军械库 / 抽奖机 / 随机道具盒

## 文件放置

| 文件 | 放到 Studio 的哪里 | 类型 |
| --- | --- | --- |
| `DodgeballServer.server.lua` | `ServerScriptService` | Script |
| `DodgeballClient.client.lua` | `StarterPlayer/StarterPlayerScripts` | LocalScript |
| `CharacterMovesServer.server.lua` | `ServerScriptService` | Script |
| `CharacterMovesClient.client.lua` | `StarterPlayer/StarterPlayerScripts` | LocalScript |

`Lighting.Technology` 需手动设为 **Future**（脚本无权限写），其余光影、大气、Bloom、云层等由服务端运行时自动配置。

## 玩法

- **外场（大厅）**：军械库柜台买刀皮（伤害统一），抽奖机抽稀有刀；圆形浮空岛 + 樱花 + 灯笼 + 鸟居。
- **内场（竞技场）**：`MIN_PLAYERS = 1` 可单人开局（调试用），球从场外飞入，撞到即死；也能被近战砍死（5 刀）。
- **盒子道具**：场内随机刷新，开出减速陷阱、闪盲、疾风加速等非致命效果。
- **两种死法**：被球撞飞 / 被刀砍死（掉出场地也算）。

## 七种球

| 球 | 特性 |
| --- | --- |
| 烈焰球 | 基础高速直线球 |
| 追猎球 | 缓慢转向追踪最近玩家 |
| 重击球 | 体积大三倍、慢速、撞击爆散 |
| 弹跳球 | 撞到场地边界反弹，不追人 |
| 分裂球 | 飞行 0.75 秒后炸成 3 颗高速碎片 |
| 蛇行球 | 正弦摆动，难以预判 |
| 幽灵球 | 半透明，靠近 22 米内加速 1.8 倍 |

每颗球带霓虹拖尾 + 点光源；特殊球出场时顶部会显示「⚠ XX 来袭」。

## 刀反弹（核心操作）

挥刀 / 按 F 攻击时，若正前方 15 米内有球，最多同时把 **2 颗**打回去：

- 反弹球变成金黄色、速度 120、直线飞行、带高亮描边
- 反弹球**不会伤害反弹者本人**
- 反弹命中其他玩家算作反弹者的击杀：`+15 金币`、连杀计数、全服播报「反弹击杀」

## 打击反馈

屏幕震动（相机偏移）、命中飘字 `🗡 -20`、连杀大字（DOUBLE / TRIPLE / RAMPAGE / UNSTOPPABLE / GODLIKE）、受伤红闪。
