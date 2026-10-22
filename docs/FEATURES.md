# 微信助手功能记录

维护约定：每次新增、修复或改变权限都更新本表，并记录验证范围；未在真机核实的部分不得写成已送达。代码入口以源码模块为准，历史ZIP不代表当前版本。当前主维护目录为微信助手项目，软件发布子包为wechat-assistant-app/。

| 功能 | 当前行为 / 限制 | 代码与证据 |
| --- | --- | --- |
| 微信文字与多实例 | 每实例独立登录、消息游标、队列、工作聊天；只处理绑定账号私聊，语音/群聊未接入 | wechat-bot.mjs、wechat-instance.ps1；primary、user-2曾由用户确认回复正常 |
| 快速聊天与工作队列 | 本地分类；闲聊无回执、常用问候本地答复，其余无工具Sol/high；工作回执+独立队列，30–45秒真实进展 | message-routing.mjs、native-chat.mjs、work-progress.mjs；chat-work测试 |
| 形象与表情包 | 默认白发龙娘为本体、蓝发鲸鱼娘为cos；可在管理器按实例编辑名称/人设与最多4张参考图；自定义外观关闭原回执图，闲聊不临时生图 | ack-stickers.mjs；outputs/persona |
| 图片收发 | 最多4张输入图、每张20MiB，验证下载后交给视觉模型；可发本地图片 | media.mjs；用户已确认手机显示与识别正常 |
| 文件往返 | 最多4个、单个100MiB本地上限；纯上传只存储确认；明确要求后分析/编辑并回传 | file-transfer.mjs、file-delivery.mjs；用户已确认手机往返测试正常 |
| 可靠交付 | outputs真实路径验证、冻结快照、摘要与稳定事件ID；unknown不自动重试，queued/sent不冒充手机收到 | 文件与实例测试；发送回执保存在Windows配置目录 |
| 跨项目协作 | 当前应用左侧项目/聊天；现成文件直接取，修改由原聊天完成；验证项目归属并复制至本实例outputs，保存最近来源 | project-bridge.mjs；示例项目/资料聊天的示例改标题PDF已验证内容并提交微信接口 |
| 双端问题 | 桌面与primary同步同编号，首答锁定；手机答后来源代理提交原生控件并核对侧栏状态，不能只追加回执 | question-broker.mjs、wechat-question.mjs；同编号原生提交回归已验证；须客户端可访问 |
| 完成通知路由 | 技能工作完成通知固定发primary，普通结果仍归各实例绑定用户 | wechat-notify、primary-bridge.ps1；primary-only测试 |
| 主用户 / 日常用户 | primary始终owner，可管理客户端/权限/服务/项目；其他默认standard，日常功能全开；可显式授予delegate或关闭生图/文件/跨项目 | access-policy.mjs；侧车策略access-policy.json，重启生效；业务权限不是独立Windows账号隔离 |
| 工作工具范围 | owner保留官方客户端工具与原审批；standard仅跨项目所需6工具，关闭桌面控制；工作提示携带可信角色，转交也须保留角色 | core.mjs、project-bridge.mjs、access-policy.mjs；结合平台沙箱与审批，不承诺对恶意脚本的强隔离 |
| 动态模型与强度 | 按实例配置，默认Sol6.1/high；从当前客户端model/list分页读取真实模型与supportedReasoningEfforts，保存前重新读取验证，不写死选项；闲聊与工作均使用实例选择 | model-policy.mjs、controller.mjs；不改变主聊天或全局提供商；服务空闲时生效，列表不可用则不保存 |
| 可视化管理 | Windows WPF界面，实例列表/角色/绑定/最近接收/工作聊天，扫码新增、启停重启、权限开关、打开聊天与工作目录 | wechat-assistant-app/；本轮验证见软件包docs/VERIFICATION.md |
| 桌面启动读取原实例 | 自动发现同一Windows用户普通目录或Codex应用专用目录的实例登记；逻辑/物理别名去重，只映射旧默认数据路径，保留自定义目录；多份登记报冲突，不合并身份、不复制认证 | instance-paths.mjs、desktop-connection.mjs、wechat-instance.ps1；桌面真机重开显示两个原实例，动态模型与原聊天可读 |
| 独立软件包 | 双击ClawBot实例管理器.exe或打开ClawBot实例管理器.vbs，旧入口兼容；源码、运行快照、模板、文档、构建与审计均在独立目录 | README.md；公开仓库忽略认证、队列、二维码、node_modules、构建产物；平台支持与使用教程见README |
| 管理器内聊天 | 所选实例独立只读窗口，每4秒刷新，最多300条近期收发；旧版仅有摘要时明确标注。附件只显示名称；不导出工具/推理/认证 | conversation-log.mjs、Dialogs.ps1；记录随现有DPAPI状态保存 |
| 人设与命名 | 每实例独立persona/profile.json与按内容哈希保存的私人图片；默认GPT小姐两形象，可改助手自称和列表备注；不改变模型/角色权限 | persona-profile.mjs；校验格式、大小、数量、真实路径及目录链接 |
| 程序名称与图标 | ClawBot实例管理器窗口、EXE版本描述和图标统一；旧启动器转新EXE，Node后台进程仍显示运行时名称 | Launcher.cs、LegacyLauncher.cs、assets/clawbot.ico |
| Windows安装器 | 当前用户无管理员安装、桌面/开始菜单/卸载项、固定Node与扫码依赖；首次向导引导本人Codex连接和微信扫码；运行中拒绝覆盖，不复制账号或改PATH | installer/、tools/build-release.mjs；发布资产附SHA-256与安装清单 |
| 首次引导与检测反馈 | 四步流程；重新检测立即显示忙碌状态，实际请求客户端模型接口，带时间的状态气泡和结果弹窗；检测后可直接新增用户，自动打开引导不阻塞检测计时器 | Dialogs.ps1、setup-status.mjs、Manager.ps1；新用户仍需本人登录、初始化和扫码 |
| Codex账号额度 | 五小时/每周的剩余与已用比例、本机时区重置时间；多分组选择，连接就绪读取、5分钟刷新或手动刷新；未提供不当成零 | account-usage.mjs、Dashboard.ps1；官方account/rateLimits/read，只读账号共享额度，不兑换重置 |
| 检测更新与安装 | 用户触发正式Release检测；固定仓库、版本比较、GitHub下载地址、大小/SHA-256验证；安装版只停本目录空闲实例，退出后交接安装，之后尝试恢复服务 | updates.mjs、ApplyUpdate.ps1、update-processes.ps1；源码/便携版仅下载到独立目录，不原地覆盖；不自动发布新Release |
| 安装完整性与卸载 | 安装后逐文件核对哈希；安装/卸载检查目标目录进程，不强杀；卸载保留用户目录认证/队列/设置/聊天/工作文件 | SetupGuard.cs、verify-payload.mjs、installer测试；同机隔离安装目录验收，不声称已在另一电脑测试 |
| 迁移与依赖 | 新电脑需Windows、Node24+、已登录运行的Codex；旧机器DPAPI不迁移，微信重新扫码；首用在客户端初始化连接，后续本机可双击 | initialize.ps1、docs/MIGRATION.md；不含模型，不绕过客户端 |

## 版本与验证

- 2026-10-22 · v1.2.0后续源码修复：新增7项路径回归，独立软件37项测试通过；本机桌面重开后原有两个实例、角色、绑定与Sol/high配置可见，model/list返回7模型，主实例原聊天记录可读，既有监听进程持续运行。未发布新安装包。

- 2026-10-22 · v1.2.0：新增6项安装相关测试，覆盖文件篡改、清单路径/链接逃逸、首次连接状态与无全局Node的内置运行环境选择。安装、启动、保护和卸载使用本机隔离目录验收，发布结果以README和Release为准。

- 2026-10-22 · v1.1.0：81项主回归、24项独立包测试通过；三类WPF窗口加载与新EXE版本信息通过。人设、模型、聊天记录隔离，参考图路径和格式拒绝测试通过；具体真机验收见软件包docs/VERIFICATION.md。

- 2026-10-22前一轮：57项测试通过；真实手机已确认文字、图片及文件往返；跨项目PDF6页内容与正文标题核对通过；原生问题框与侧栏状态完成回归。
- 2026-10-22本轮：主项目74项回归、独立软件包17项测试通过；两实例角色更新、登录/提供商/聊天保留、真实权限与模型保存、官方聊天导航已验证。动态列表实际返回7模型，界面强度随模型变化。详见outputs/manager-verification.json及软件包docs/VERIFICATION.md。

## 继续维护时

先查看对应源码和本记录再改动；保留消息去重、身份绑定、文件范围、首答锁定和primary通知路由。更新根项目源码后运行软件包tools/sync-runtime.mjs，同步后重新测试与审计，再构建。新功能记清用户可用行为、实际限制与证据，详细问答命令保存在OPERATIONS.md。
