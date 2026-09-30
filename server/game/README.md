# Arcane Academy 独立岛屿服务端

这是寒冰岛游戏服务端。Godot 4.5.1 Standard 负责世界/战斗；同一游戏容器内另由固定版本自带 Python 在 127.0.0.1 提供唯一经济账本。它不包含、替换或启动云登录/存档服务，也不携带玩家数据库。无窗口，不加载地图模型、卡面、HUD或音频。

## Linux 启动

发布工具先上传经过 SHA256 锁定的 `game-runtime-<精确版本>.tar.gz`，再提交 `island-server.zip`。启动脚本校验并解压不可变 runtime，然后监督 loopback 账本和 Godot；不依赖容器 PATH 中已有 Python。

```sh
cd /app
GODOT_BIN=/opt/godot/Godot_v4.5.1-stable_linux.x86_64 sh start.sh
```

默认明确监听 IPv4 `0.0.0.0:29710/UDP`。服务器和路由器/云防火墙需允许该 UDP 端口。自定义端口：

```sh
PORT=29711 GODOT_BIN=/opt/godot/Godot_v4.5.1-stable_linux.x86_64 sh start.sh
```

构建包包含 Godot 脚本类型缓存。只有账本目录/SQLite事务、旧云身份服务能力、bridge恢复和Godot网络都就绪后才输出 `ISLAND_SERVER_READY`；监督器随后输出 `GAME_SERVER_STACK_READY`。任一必需组件失败会停止另一组件并失败退出。

## 客户端

正式客户端登录后自动连接预设云岛服，不显示 IP、创建房间或加入房间入口；掉线会显示常驻状态并受控重连。只有经旧云账号真实认证的 admin 可用 F10 进入 LAN 调试。客户端、Godot 岛服、账本协议和目录必须来自同一冻结版本。

任意玩家距游荡怪物水平距离不超过 2 米，且高度差小于 4 米，服务端启动战斗。战斗区域按该营地现有 `radius` 和中心收集玩家，高度差小于 8 米，一起载入并归位。范围外玩家可看见演出，不自动参战。每名真人继续控制当前正式岛屿模式的一名角色；保留现有 AI 助战。已满 4 个角色（含 AI）不再新增站位。

空余站位支持中途加入：当前 planning 可以集结；演出阶段靠近时先入阵，下一次 planning 正式加入。所有战斗状态由服务器结算，客户端只提交操作，不能提交伤害或资源结果。战斗消息 v3 将整轮动作合包，复用相邻演出快照；客户端按内部序号播放，整轮结束后确认。重复/旧确认不推进。90 秒未完成载入或演出的连接不会无限卡住房间。掉线角色保留重连窗口，期间未选行动按跳过处理。

战斗握手额外要求 `battle_wire_version=3`（经济协议仍为 2）。客户端与服务端须成套更新，旧客户端会收到升级提示。消息按接收者投影：血量、魔豆和已生效状态公开；本人手牌定向发送；队友仅能看到已选法术摘要；对手及旁观者不能查看私有牌库。本人牌库查看保留组成，隐藏洗牌顺序及库存凭证。规则及验证记录见 `docs/combat_v3.md`。

## 维护入口

主项目 `scripts/server/island_server.gd` 管理房间、触发、集结、指令与演出确认；`encounter_geometry.gd` 定义 2 米触发与范围判定；`terrain_heights.gd` 使用原高度数据，不加载地表图形。费用和效果仍使用 `BattleEngineV2` 与 `fusion_engine.gd`。

每次修改账本或服务端后，先运行 `python tools/server_update/build_game_runtime.py`，再运行 `python server/game/build.py`。相邻 `server/account_server.py` 是原有云账号服务，本次禁止发布、迁移、改库或重启。

可在部署目录直接检查关键脚本；不需要先启动编辑器：

```sh
godot --headless --path . --script res://scripts/fusion_3d/world_one_ai.gd --check-only
godot --headless --path . --script res://scripts/fusion_3d/fusion_engine.gd --check-only
```

服务端运行时，可在另一终端测试本机 ENet 握手：

```sh
godot --headless --path . --script res://tests/server/connection_probe.gd -- --address=127.0.0.1 --port=29710 --timeout=5
```

出现 `PROBE_CONNECTED` 说明 Godot 和 Docker 监听正常；公网客户端仍超时则检查云安全组与系统防火墙是否放行入站 UDP 29710。

## 验证与边界

在 Windows Godot 4.5.1 headless 完成真实 UDP 多进程验证：4 客户端，非主机触发、远处观战、2→3→4 人跨回合入场、逐包状态摘要一致、断线清理。服务器无 3D 场景。当前机器未配置可用 Linux 运行环境，因此没有宣称已做 Linux 实机测试；部署脚本及资源路径为跨平台形式。

正式公网路径已接旧云 v1 Bearer 与角色归属校验，再由游戏服账本处理 bootstrap、装备和经济事务；原云账号/存档服务保持不变。服务端继续校验操作归属、回合、卡牌合法性和移动速率；完整服务端移动碰撞与多世界分片仍不在本次范围。
