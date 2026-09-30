# 学院账号与云存档服务

这是已接入 Godot 的账号后端，不运行图形界面或战斗模拟。一个 Python 进程、SQLite 数据库，固定最多 4 个本地请求工作线程，无 Redis、MySQL、容器或后台轮询依赖。

## 现在使用

1. Windows：双击 `start-server.bat` 即可启动，保持窗口打开；按 Ctrl+C 停止。重复启动会提示服务已经运行。也可运行 `powershell -ExecutionPolicy Bypass -File .\start-local.ps1`，支持 `-Python 路径 -Port 8787 -DataDirectory 路径`。
2. Linux/macOS：Python 3.11+，运行 `python3 account_server.py --host 127.0.0.1 --port 8787`。
3. 启动游戏，服务器地址使用 `http://127.0.0.1:8787`，点击“创建新账号”。账号名为 3–24 位字母、数字或下划线，密码 8–128 位。
4. 注册后创建角色。可选七学院、男女及八款发型；死亡学院默认保留 Death Wizard 原作整套模型。勾选“导入这台电脑的旧进度”可复制现有队伍、章节、衣橱和卡组，原文件不变。
5. 游戏内“保存进度”立即同步；每 30 秒检查并保存，只有内容变化才上传。退出游戏或返回角色管理也会保存。服务器断开时可继续当前游戏，本地待同步进度保留，恢复连接后重试。

每账号最多 12 个角色；可改名、删除（输入完整角色名确认）、修改密码、退出账号。每次启动需要登录，不在客户端保存密码或登录令牌。未实现邮件找回密码和邮箱验证。

## 数据与备份

- 服务端：默认 `server/data/accounts.sqlite3`，运行时可能有 `-wal` 和 `-shm` 文件。保存账号、加盐密码摘要、有效期 7 天的会话、角色、当前存档及最近 3 个历史版本。数据库不包含模型、音乐或贴图。
- 游戏端：Godot 用户目录 `account_cache/<服务器摘要>/<账号ID>/<角色ID>/`，四种独立存档文件、同步版本和备份。账号/角色 ID 来自服务器，不能用路径访问其他角色。
- 旧版 `user://fusion_3d_story.json`、`academy_chapter_one.json`、`academy_wardrobe.json`、`academy_custom_decks.json` 保留，可导入多个新角色。
- 创建在线一致备份：`python account_server.py --data ./data --backup ./backup.sqlite3`。服务运行期间不要只复制正在写入的 `.sqlite3` 主文件。
- 还原：停止服务后，用备份数据库替换新的空数据目录中的 `accounts.sqlite3`，再启动。旧数据目录完整留作回退。部署迁移要保留账号和角色 ID。
- 删除角色仅标记删除，数据库中仍保留记录，可由维护人员恢复；没有面向玩家的永久清除入口。

## 后续架设

本地运行器只用于本机或可信网络测试。公网部署使用 Waitress + HTTPS 反向代理，客户端改为你的 HTTPS 地址即可，业务 API 不变。

```sh
python3 -m venv /opt/academy/.venv
/opt/academy/.venv/bin/pip install -r /opt/academy/server/requirements.txt
/opt/academy/.venv/bin/python /opt/academy/server/account_server.py --production --host 127.0.0.1 --port 8787 --data /var/lib/academy
```

提供 `academy-accounts.service` 和 `Caddyfile.example` 模板。先创建 `academy` 系统用户、安装服务代码和虚拟环境，再安装 systemd 单元并配置域名。让反向代理监听公网 443，API 继续绑定回环地址；不要将本地 HTTP 端口直接暴露公网。模板内的 192 MB 是资源上限，不是实测容量或人数承诺。HTTP 限流按直连 IP 和账号，若部署反向代理，多用户共用代理源地址的登录限额要结合受信代理配置调整，不能直接信任客户端伪造的 X-Forwarded-For。

密码使用随机 16 字节盐与 PBKDF2-HMAC-SHA256（600,000 次），数据库只保存会话令牌的摘要。登录/注册限流、4 线程上限、512 KiB 请求上限和每账号角色上限控制开销。哈希计算只发生在登录、注册与修改密码时。生产 HTTP 由 [Waitress](https://docs.pylonsproject.org/projects/waitress/en/stable/) 处理；密码派生与 SQLite 分别使用 [Python hashlib](https://docs.python.org/3/library/hashlib.html#key-derivation) 和 [sqlite3](https://docs.python.org/3/library/sqlite3.html)。

当前服务保存客户端提交的进度；服务器验证身份、所有权、请求范围和版本，不验证战斗过程、防作弊、道具交易或付费经济。它与现有局域网城镇联机是两个独立服务。后续若有排行榜、交易或充值，需再增加对应的服务端规则校验。

## 存档冲突与断线

上传使用版本比较；两个设备基于同一版本写入时仅一个成功，另一端返回冲突。角色管理提供“使用云端存档”和“保留本地进度并上传”，选择前会备份两份内容。自动同步不覆盖较新的云端进度。断线后已登录的当前游戏仍会落盘；重新启动需账号服务器在线才能登录。

## 检查

- 服务端：`python test_accounts.py`。验证注册、大小写重名、登录失败、密码修改与旧令牌失效、跨账号读取/编辑/删除禁止、角色上限、并发版本冲突、历史保留、数据库重新打开、删除确认、请求大小与限流。
- 游戏端：启动隔离服务 `python account_server.py --port 8788 --data ../art_source/account_system/test_server_data`，运行 Godot `--headless --path .. --script tests/fusion_3d/test_accounts.gd`。测试缓存位于项目的测试目录，不修改玩家账号设置或旧存档。
- 画面：`docs/accounts/`；测试日志：`art_source/account_system/`。

本机测试服务运行后的进程工作集约 24 MB（Windows，少量测试账号）；这仅是当前测量，不代表并发上限。空闲 CPU 与实际压力测试结果另见验收记录。

