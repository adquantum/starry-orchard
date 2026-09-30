# 星界果园：统一服务端

统一入口为 server/start_all.py。它管理原有账号/云存档 Python 服务和 Godot 战斗服务：一起启动、停止，任一子服务退出时停止另一个，由 systemd 统一重启。数据库和原有 API 格式不变。

Linux（Python 3.11+、Godot 4.5.1）：
```
python3 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
.venv/bin/python server/start_all.py --production --godot /opt/godot/godot --data /原来的账号数据目录
```

现有账号服务仍在运行时：
```
python server/start_all.py --reuse-accounts --godot /path/to/godot
```
该模式只接管战斗子进程，不结束原有账号进程。账号监听默认 TCP 8787、游戏 UDP 29710；客户端账号服务器地址和联机服务器地址分别填写同一主机对应的服务。公网账号服务继续使用原有 HTTPS 代理配置。提供 star-orchard.service，按实际安装路径修改后安装。不要同时启用旧战斗 service 占用同一端口。

部署包不含账号数据库。迁移时先用原 account_server.py --data 原目录 --backup 备份路径进行 SQLite 在线备份，再在新服务器指定该数据目录；不要覆盖正在运行的数据库。此次整合未迁移正在运行的用户数据库、未修改远程服务器。

岛屿卡组本来就使用 Accounts.path_for 的角色缓存路径。保存卡组现在立即请求云存档同步，同时向战斗会话发送配置；离线失败保留本地，已有 30 秒自动同步继续重试。服务端保留原有身份、角色所有权、版本冲突和历史存档验证。

边界：统一部署和进程管理已接入；战斗连接仍沿用现有 ENet 协议，尚未把账号令牌鉴权绑定到战斗连接，不应当视为完成 MMO 防作弊或经济系统。
