---
name: wechat-notify
description: 按用户授权把技能任务完成摘要提交至第一微信实例 primary。
---

调用本目录 scripts/wechat-notify.ps1 -Action Preview -MessageFile <UTF8JSON>，核对真实结果后再 -Action Send。JSON 字段 event_id、title、content，事件ID稳定且唯一。相邻 primary-bridge.ps1 使用 Windows 用户目录中的 primary，禁止改为其他实例或附加收件人。完成通知包含来源任务、结果和待办；普通回复仍归原账号。

queued 仅是入队，sent 仅表示微信接口提交成功，用户确认才称手机收到。unknown 不盲目重发，不换事件ID绕过去重。主实例离线如实报告，不回退到其他用户。认证不放进项目、文件包或协作模型。
