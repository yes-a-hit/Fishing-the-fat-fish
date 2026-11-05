# Issue 跟踪器：本地 Markdown

本仓库 钓肥鱼（Godot 4.7.2 游戏）的 issue 与 spec 都以 markdown 文件存放在 `.scratch/`。本仓库不建 `AGENTS.md`，三个配置文件都在 `docs/agents/`，按路径直接读。

## 约定

- 一个特性一个目录：`.scratch/<feature-slug>/`
- spec 是 `.scratch/<feature-slug>/spec.md`
- 实现工单一个文件一个：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 起编号，不用单个 tickets 汇总文件
- 分诊状态写在每个 issue 文件顶部附近的 `Status:` 行（角色字符串见 `triage-labels.md`）
- 评论与会话记录追加到文件末尾的 `## Comments` 标题下

## 技能说「发布到 issue 跟踪器」时

在 `.scratch/<feature-slug>/` 下新建文件，需要时先建目录。

## 技能说「取相关工单」时

直接读取给定路径的文件；主人通常会给路径或工单号。

## Wayfinding 操作

供 `wayfinder` 使用。**map** 是一个文件，每张 **child** 工单一个文件。

- **Map**：`.scratch/<effort>/map.md`（Notes / Decisions-so-far / Fog 三段正文）。
- **子工单**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 起编号，正文写问题。`Type:` 行记录类型（`research`/`prototype`/`grilling`/`task`），`Status:` 行记录 `claimed`/`resolved`。
- **阻塞**：顶部附近的 `Blocked by: NN, NN` 行。列出的文件全部 `resolved` 才算解锁。
- **Frontier**：扫 `.scratch/<effort>/issues/`，取开放、未阻塞、未认领的最小号。
- **认领**：动工前把 `Status:` 改成 `claimed` 并保存。
- **完结**：在 `## Answer` 标题下写答案，`Status:` 改成 `resolved`，再把一段上下文指针（要点 + 链接）追加到 `map.md` 的 Decisions-so-far。
