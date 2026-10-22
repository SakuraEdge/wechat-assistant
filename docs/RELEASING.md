# Windows 安装包与 GitHub Release

本项目提供 Windows 10/11 x64 当前用户安装器，使用 Inno Setup 6.7.3，内置 Node.js 24.16.0。其他平台尚未适配。普通用户下载Release安装包，不需要构建环境。

## 构建

维护者需要 Windows x64、Node 24+（含npm）、Windows PowerShell/.NET Framework及 Inno Setup。依赖来源和固定哈希在`installer/dependencies.json`。Node来源为[官方版本文件](https://nodejs.org/dist/v24.16.0/)，编译器来源为[Inno Setup官方发布](https://jrsoftware.org/isdl.php)；编译器仅用于构建，不安装到用户电脑。

1. 修改`package.json`与`src/Launcher.cs`版本，同步README、功能记录和版本说明。
2. 测试与审计：`node --test tests/*.test.mjs`、`node tools/audit-package.mjs`，在Windows执行WPF SelfTest。父维护项目改核心后先同步快照。
3. 运行 `node tools/build-release.mjs --compiler "完整路径/ISCC.exe"`，也可提供`ISCC_PATH`环境变量。脚本只使用软件目录；干净暂存目录按锁文件执行npm ci、编译、生成清单并校验，缺少Node二进制时从固定官方地址下载并核对哈希。
4. 产物位于`dist/release-v<版本>/`：EXE安装器、内置Node的便携ZIP、`install-manifest.json`和`SHA256SUMS.txt`。不会包含父工作区、认证、运行队列、聊天记录或用户产物。

安装器不会更改系统PATH。管理器、实例管理及完成通知优先使用包内Node。Node许可证在`runtime/node/LICENSE`，扫码依赖许可证随相应node_modules分发；中文安装文本保留原翻译署名。当前未配置发布者代码签名，不能把编译器签名误称为本软件安装包签名。

## 验证

在独立测试安装目录执行实际安装、启动、目标目录进程保护与卸载。记录安装/卸载前后绑定身份、角色、模型、人设、线程关联的保留结果；保持其他目录运行的实例不受影响。卸载仅删除安装文件和快捷方式，不枚举删除用户数据。

对便携ZIP核对完整文件清单、路径与哈希。`node installer/verify-payload.mjs <安装目录>`可复查安装清单；安装器在安装完成时也会执行此检查。对从Git导出的独立源码再跑测试、快照审计和WPF加载，防止意外依赖父工作区。

## 发布

发布操作仅在用户明确要求后执行。`tools/publish-release.mjs`使用进程环境变量`GITHUB_TOKEN`，不得把令牌写入源码、命令参数、配置、文档或日志。

先提交并推送已验证的软件变更（中文commit）。创建对应提交的草稿Release，上传四个资产并核对远端SHA-256/大小、实际下载内容，再转为公开Release；发布后核对标签提交、资产及公开下载。现有公开版本不静默替换资产，修复使用新版本。未知结果先读取远端状态，不盲目重新创建或覆盖。

v1.3.0起管理器可主动检测此仓库正式版。保持标签`v主.次.修订`与安装器名`ClawBot-Instance-Manager-Setup-<版本>-windows-x64.exe`一致，发布`SHA256SUMS.txt`并保留GitHub资产的size/digest。客户端拒绝缺少校验信息的安装包、预发行版、非固定仓库的下载链接和降级。源码提交并不等于已有可下载的新版Release。

```powershell
node tools/publish-release.mjs --publish --commit <已推送的完整提交SHA>
```

若资产上传或验证失败，保留草稿并报告实际状态，不能声称已公开。GitHub自动生成的源码ZIP不包含被忽略的二进制；普通用户应选EXE或便携资产。
