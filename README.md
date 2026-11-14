# 映造插件

映造为 Codex 提供图片与素材制作工作流、设计自审、实时工作台及可拖拽的丫鸭桌面入口。

这是公开分发仓库。应用核心源码保存在维护者的私有项目；此处只维护市场索引、启动和更新脚本及发行说明。

## 安装

在 Windows 10 / 11 x64 的 Codex 中添加 GitHub 插件市场：

```powershell
codex plugin marketplace add leovyy/yingzao-plugin
codex plugin add yingzao@yingzao-plugin
```

启用映造后显示丫鸭。首次连接会下载经签名及 SHA256 校验的运行时；如宿主首次连接超时，可先运行插件目录里的 `scripts/Update-Yingzao.ps1`，然后重新连接。

“启用映造”管理插件工作流和桌面入口。“使用映造内部 API”独立控制新任务能否使用你在本机配置的服务；未配置时打开本机配置页。关闭后不自动切换其他收费服务。

## 更新与回退

在映造设置的“本地资料与更新”中检查、安装更新或回退上一已校验版本；重新连接插件后生效。运行时采用版本目录，更新不覆盖在用文件，不强制终止制作任务。市场清单更新可运行：

```powershell
codex plugin marketplace upgrade yingzao-plugin
```

只下载 [Releases](https://github.com/leovyy/yingzao-plugin/releases) 中的运行时资产；GitHub 自动生成的 Source code ZIP 仅包含公开分发层。

## 本地资料

- 默认保存在 `%LOCALAPPDATA%\YingzaoPlugin\data`；已有安装会保留已登记的数据目录。
- 包体审美库只读，与个人本地喂图一起检索。个人喜欢、不喜欢及隐藏操作只写本地覆盖记录。
- 记忆采用 SQLite 保存来源、范围及修订，并提供可阅读的 Markdown 索引；工作回执不自动成为个人偏好。
- 不接入 Cloudflare 云库，不上传个人喂图、记忆或素材。插件不含向 GitHub 上传审美库的功能；只有维护者私有源码项目的发布工具可整理包体资料。
- 原图与制作记录保留。最终交付使用一份产物包，检查证据独立留在本地；不会把中间自审写成人工验收。

## 自动化与授权

AI 默认使用映造内部工作流、领域指导和审美检索，并结合宿主联网搜索。设计阶段记录实际参考取舍，制作后按全图、原尺寸细节、参考和上一候选自审；中间由 AI 修正与继续，最终产物留给用户审查。缺少真实应用能力或请求结果未知时，先核对原回执，不伪造进度或重复计费。

公开市场安装不等于已进入 OpenAI 官方全局插件目录。

## 许可

映造应用核心为专有软件。第三方组件遵循各自许可证，随运行时保留对应声明；GIMP PDB 适配器按 GPL-3.0-or-later 提供其源码，位于 `runtime/_internal/third_party/gimp-adapter`。这不改变核心代码的许可。
