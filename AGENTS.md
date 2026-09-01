# GameHub 开发规范

本文件是 GameHub 仓库的强制开发约定，适用于人工开发和 Codex 自动化修改。若实现方案与本规范冲突，应先更新规范并说明迁移影响，再修改代码。

## 1. 总体架构

- GameHub 采用**单 Godot 工程、游戏模块化**架构。
- 编辑器开发时，Hub 与所有子游戏运行在同一个 Godot 进程中。
- 按 F5 后的标准流程必须是：`Boot → Hub 大厅 → GameHost → 子游戏`。
- 子游戏不得通过 `OS.create_process()` 启动独立 EXE；当前产品不以独立游戏进程作为默认方案。
- 发布阶段允许把单个游戏导出为 PCK，但 PCK 是交付形式，不是日常开发形式。
- 所有游戏使用与 GameHub 相同的 Godot 版本、渲染后端和运行时 SDK 契约。

## 2. 游戏模块目录

每个子游戏必须位于独立命名空间中：

```text
res://games/<game_id>/
├─ module.tres
├─ scene/
│  ├─ boot.tscn          # 可选；游戏自身存在较多资源时使用
│  └─ main.tscn          # 固定模块入口
├─ script/
│  ├─ models/            # 不依赖场景节点的数据模型
│  ├─ rules/             # 可独立测试的规则
│  ├─ flow/              # 回合、状态机和游戏流程
│  └─ ui/                # 场景表现和输入适配
├─ assets/
└─ resources/
```

强制要求：

- `<game_id>` 使用小写 snake_case，并作为目录、存档和目录清单的稳定主键。
- 游戏入口固定使用 `res://games/<game_id>/scene/main.tscn`。
- 游戏资源不得使用 `res://scene/main.tscn`、`res://script/main.gd` 等全局通用路径。
- `res://games/<game_id>/` 内不得包含嵌套的 `project.godot`、`.godot/`、独立 MCP 插件或第二份 GameHub SDK。
- 子游戏之间不得直接引用对方的脚本、场景或资源。真正通用的功能应提升到 GameHub SDK 或共享服务。

Tongits 的标准入口为：

```text
res://games/tongits/scene/main.tscn
```

## 3. 编辑器运行模式

开发阶段不加载 PCK，直接加载项目内资源：

```gdscript
var scene := load("res://games/tongits/scene/main.tscn") as PackedScene
var game := scene.instantiate()
game_host.add_child(game)
```

- 按 F5 必须能够从 GameHub 大厅进入游戏。
- 允许开发者打开子游戏入口场景后按 F6 单独调试。
- 子游戏不得要求命令行参数才能运行。
- 直接运行时缺少平台会话的功能应使用明确的开发态降级行为，不得崩溃。
- Hub 的 `GameHost` 同一时刻只承载一个游戏根节点。
- 退出游戏时必须释放游戏场景、断开游戏级信号并返回大厅，不得重启整个应用。

## 4. 游戏模块契约

游戏目录定义至少应包含：

- `id`
- `title`
- `description`
- `version`
- `category`
- `tags`
- `icon` / `cover`
- `entry_scene_path`
- `availability`
- 可选的 `pack_path`

游戏根节点必须遵循统一生命周期语义：

```gdscript
signal ready_to_play
signal exit_requested
signal game_finished(result: Dictionary)

func initialize(context: Dictionary) -> void:
    pass

func start_game() -> void:
    pass

func pause_game() -> void:
    pass

func resume_game() -> void:
    pass

func shutdown_game() -> void:
    pass
```

- Hub 只通过模块契约控制游戏，不访问 Tongits 的内部节点路径。
- 游戏只上报稳定 ID 和数据对象，不把 UI 节点引用传给 Hub。
- `shutdown_game()` 必须可以安全重复调用。
- 再次进入同一游戏不得残留上一次运行的节点、计时器、信号连接或网络监听。

## 5. 公共服务边界

以下能力由 GameHub 统一提供，可作为 Autoload：

- `PlatformSession`：登录态、用户资料和短期凭证。
- `NetworkService`：平台连接、匹配及游戏连接工厂。
- `AudioService`：Master、Music、SFX 总线。
- `SettingsService`：语言、显示、辅助功能和公共输入设置。
- `SaveService`：统一路径、原子写入和版本迁移。
- `GameRegistry`：游戏清单、搜索和可用状态。

子游戏不得自行注册全局 Autoload。游戏通过 `initialize(context)` 获取所需服务或会话句柄。

## 6. 联网规范

- 工程是否拆分不决定联网方式；所有客户端都通过后端协议通信。
- Hub 负责登录、用户资料、游戏目录、匹配和房间分配。
- Tongits 服务器负责牌库、发牌、回合、操作校验、胜负和计分。
- Tongits 属于回合制游戏，默认使用 HTTPS 完成登录/匹配，使用 WSS WebSocket 同步牌局消息。
- 牌局必须采用服务端权威模型；客户端不能自行决定牌库顺序、合法操作、得分或胜负。
- 同进程运行时，Tongits 复用 Hub 的平台会话，不通过命令行传递长期 Token。
- 网络消息必须包含协议版本、房间 ID、玩家 ID、递增序号和幂等操作 ID。
- 断线重连必须通过服务器状态快照恢复，不能依赖客户端本地状态作为权威数据。

## 7. 输入、存档与资源隔离

- 公共 UI 输入使用 `ui_*`。
- 游戏专属 InputMap 必须添加游戏 ID 前缀，例如 `tongits_draw`、`tongits_discard`。
- 游戏进入时注册所需输入，退出时恢复或释放游戏级输入状态。
- Hub 数据写入 `user://hub/`。
- 子游戏数据写入 `user://games/<game_id>/`。
- Tongits 数据写入 `user://games/tongits/`。
- 游戏不得读取或修改其他游戏的存档目录。
- 规则数据优先使用 Resource/JSON 等数据驱动形式，避免硬编码在 UI 脚本中。

## 8. 资源加载

- GameHub Boot 只加载进入大厅立即需要的资源。
- 游戏场景和大型游戏资源在玩家选择游戏后按需加载。
- 加载页显示进度必须来源于真实加载任务；允许缓动追赶真实目标，但不得提前超过真实进度。
- 禁止在加载页脚本中 `preload()` 目标主场景，否则会绕过加载页的异步流程。
- 动态加载应使用 `ResourceLoader`，并处理失败、资源缺失和取消流程。
- 离开游戏后必须释放节点和资源引用，避免重复进入时持续增长内存。

## 9. PCK 发布模式

开发阶段使用项目内资源；正式发布时可将单个游戏导出为 PCK：

```text
GameHub.exe
GameHub.pck
games/
└─ tongits/
   ├─ game.json
   └─ tongits-<version>.pck
```

PCK 规范：

- PCK 内资源仍必须位于 `res://games/<game_id>/...`。
- 编辑器直载和 PCK 加载必须使用相同的 `entry_scene_path`。
- 挂载游戏包时默认使用 `ProjectSettings.load_resource_pack(pack_path, false)`，避免覆盖 Hub 资源。
- PCK 不得依赖其来源工程的 Autoload、InputMap 或 `project.godot` 设置自动生效。
- Hub 必须在挂载前校验游戏 ID、兼容版本、文件哈希；正式分发应增加签名验证。
- 不依赖运行时卸载 PCK。退出游戏时释放游戏实例，但资源包的挂载生命周期按整个 Hub 进程管理。
- MCP、编辑器插件、测试产物和 `.godot/` 不得进入发布 PCK。

## 10. 代码与测试规范

- 规则层不得依赖具体 UI 节点，保证可用自动测试直接实例化。
- 场景脚本负责展示和输入适配，不重复实现规则判断。
- 为非显而易见的设计决策添加中文注释，重点解释“为什么”，不要逐行翻译代码。
- 公共接口使用明确类型；跨模块数据使用稳定 Dictionary/Resource 契约。
- 新功能至少验证正常路径、非法输入、重复进入退出和资源缺失。
- 完成改动后必须执行 Godot 资源扫描、主场景运行及编辑器/游戏错误日志检查。

## 11. Tongits 迁移约定

现有独立 Tongits 工程作为迁移来源。迁入 GameHub 的内容仅包括游戏业务资源：

```text
tongits/scene       → GameHub/games/tongits/scene
tongits/script      → GameHub/games/tongits/script
tongits/resources   → GameHub/games/tongits/resources
tongits/assets      → GameHub/games/tongits/assets
```

不得迁入：

```text
tongits/project.godot
tongits/.godot/
tongits/addons/godot_ai/
tongits/addons/gamehub_sdk/
tongits/export_presets.cfg
```

迁移完成并验证前不得删除独立 Tongits 工程。完成验证后，它可以作为历史备份归档，但 GameHub 内的 `res://games/tongits/` 是后续业务开发的唯一事实来源。

## 12. 完成标准

一个子游戏只有同时满足以下条件才算接入完成：

1. F5 启动 GameHub 后能从大厅进入游戏。
2. F6 可以直接运行游戏入口场景。
3. 游戏能接收 Hub 上下文并使用公共服务。
4. 游戏可以正常退出并返回大厅。
5. 连续进入和退出至少 10 次无残留错误。
6. 资源缺失、网络断开和非法操作都有明确失败处理。
7. 编辑器日志与游戏日志无新增错误。
8. 发布模式下可以从约定路径加载对应 PCK。
