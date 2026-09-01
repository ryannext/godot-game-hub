# GameHub SDK

大厅与同一 Godot 工程内游戏模块之间的运行时契约。

- `GameDefinition`：游戏目录元数据、入口场景和发布方式。
- `GameHubLaunchContext`：把 Hub 传入的 `Dictionary` 转为可选的强类型上下文。
- `GameModule`：所有内嵌游戏统一实现的进入、暂停、恢复和退出生命周期。

开发阶段直接加载 `res://games/<game_id>/` 中的场景；发布阶段可以先挂载
PCK，但入口场景路径和生命周期保持不变。SDK 不包含共享游戏 UI、玩法代码，
也不负责启动独立 EXE。
