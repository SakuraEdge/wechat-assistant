# GPT 小姐表情包

- stickers/received-dragon-v1.png：白毛龙娘「收到啦～正在处理」，复用已有人设图片。
- stickers/waiting-fish-v1.png：大肥鱼 cosplay「马上来～」，适合排队回执。
- stickers/done-dragon-v1.png：白毛龙娘「搞定啦！」，适合任务完成。

后两张使用内置 image_gen 生成。每张图片的完整提示词保存在同名 .prompt.txt 文件；参考图位于 references/，图片校验值见 manifest.json。

自动回执由 ack-config.json 控制：文字先发，每条任务至多一张图片；图片失败仍继续处理任务，结果未知不自动重发。回执只复用本地图片，不临时调用生图。

使用方式与支持范围见仓库README；普通聊天不发送工作回执。本目录仅保存软件形象素材，不包含账号或特定机器的激活状态。
