export const ROUTING_VERSION = 'chat-work-projects-v4';
export const isControlMessage = text => /^\/(状态|停止|批准|拒绝|回答)(?:\s|$)/.test(text || '');
export function classifyMessage(text = '', context = {}) {
  const value = text.trim();
  if (isControlMessage(value)) return 'control';
  if (/^\/工作(?:\s|$)/.test(value)) return 'work';
  if (/^\/聊天(?:\s|$)/.test(value)) return context.hasFiles ? 'attachment' : 'chat';
  if (/(?:从|在|到|去|让|请).{0,30}(?:项目|聊天|会话|对话).{0,60}(?:帮我获取|获取|拿取|找出|找一下|查找|帮我找|发给|发我|取回|拿到|修改|询问|问一下|继续处理)/.test(value)) return 'work';
  if (context.hasProjectContext && /(?:在.{0,10}基础上|刚才|刚刚|这个|该文件|标题).{0,30}(?:改|修改|发送|发我|处理|生成|替换|更新)/.test(value)) return 'work';
  if (context.hasRecentFiles && /(?:文件|附件|刚才|刚刚|文档|代码|压缩包)/.test(value) && /(?:内容|有什么|是什么|发给我|给我|处理|分析|识别|读取|读一下|看看|看一下|审阅|检查|修复|修改|解压|总结|翻译)/.test(value)) return 'work';
  if (context.hasFiles && /(?:分析|识别|读取|读一下|看看|看一下|审阅|检查|内容|修复|修改|处理|解压|总结|翻译|是什么|什么格式)/.test(value)) return 'work';
  if (/^(?:请|帮忙)?(?:分析一下|分析下|读取|读一下|识别|审阅|解压|接收文件)/.test(value)) return 'work';
  if (/^(继续|继续吧|开始吧|照做|按这个做|就这样做)[。！!\s]*$/.test(value)) return context.hasActiveWork ? 'work' : context.hasFiles ? 'attachment' : 'chat';
  if (/(?:需要|要求)(?:修复|修改|迁移|部署|更新|安装|打包|处理)/.test(value)) return 'work';
  if (/(?:模型|推理强度|权限|配置|实例|工作区).{0,10}(?:改为|改成|换成|设置为|迁到|迁移到)/.test(value)) return 'work';
  if (/(?:做完|完成|处理完).{0,12}(?:发我|通知我|告诉我)/.test(value)) return 'work';
  if (/(?:发一张|发个|做一张|生成一张|画一张).{0,20}(?:给我|图片|表情包)/.test(value)) return 'work';
  // A greeting at the beginning does not override an actual request later on.
  if (/(?:帮我|替我|请你|麻烦你?|能不能|可不可以|可以|能否|能)\s*(?:帮忙|帮我|替我|给我)?\s*(?:把|将|查|搜|找|修|改|迁|部署|安装|启动|停止|生成|制作|写|画|录入|整理|检查|测试|验证|更新|打包|执行|运行|完成|处理|分析|翻译|总结|打开|导出|导入|备份|删除|创建|建立|发一|发送)/.test(value)) return 'work';
  if (/^(?:请|现在|接下来|另外|然后|再|先)?[，,\s]*(?:把|将).+(?:迁|移|改|复制|同步|更新|删|存|发|放|打包|整理|部署|转|导出|导入|设|换)/s.test(value)) return 'work';
  if (/^(?:请|麻烦|现在|接下来|另外|再|先)?[，,\s]*(?:查一下|查下|搜索|搜一下|修复|修一下|修改|改一下|迁移|部署|安装|生成|制作|写一个|写一份|写个|录入|检查一下|测试一下|验证一下|更新|打包|执行|运行|备份|创建|打开|导出|导入|设置|停止服务|启动服务|发一张|发个|发给|发送|翻译一下|总结一下)/.test(value)) return 'work';
  if (/(?:需要|想要|想|我要|请).{0,16}(?:修复|部署|迁移|打包|更新|安装|新建|创建|生成|制作).{0,30}(?:项目|文件|脚本|代码|程序|服务|功能|表格|图片|表情包|工作区|实例|网站|报告|文档)/.test(value)) return 'work';
  if (/(?:修复|修改|迁移|部署|安装|更新|打包|生成).{0,12}(?:一下|这个|这些|上述|前面|刚刚|这几个)/.test(value)) return 'work';
  return context.hasFiles ? 'attachment' : 'chat';
}
export const entryIntent = (entry, state = {}) => entry.intent || classifyMessage(entry.text, {
  hasFiles: !!entry.files?.length,
  hasProjectContext: !!state.lastProjectSource,
  hasRecentFiles: !!state.recentFiles?.length || !!state.pending?.some(item=>item.files?.length),
  hasActiveWork: state.pending?.some(other => other !== entry && other.intent === 'work' && ['running','queued'].includes(other.status))
});
export const isPendingEntry = entry => ['queued','running','chatting','receiving'].includes(entry.status);
export function localChatReply(text = '', state = {}) {
  const value = text.replace(/^\/聊天\s*/, '').trim().replace(/[～~！!。.?？\s]+$/g, '');
  const name=state.persona?.assistant_name||'GPT小姐',custom=state.persona&&state.persona.builtin_appearance===false;
  // Custom speech styles are handled by the tool-free chat model; never apply the old persona's canned lines.
  if(custom&&!/^(进度怎么样|怎么样了|做到哪了|还在处理吗|任务还在运行吗)$/.test(value))return null;
  if (/^(你好|您好|嗨|哈喽|hello|hi)$/i.test(value)) return '你好呀～'+name+'在呢。🐉';
  if (/^(在吗|在不在|你在吗|人呢|在嘛)$/.test(value)) return '在呢～你说，我听着。🐉';
  if (/^(谢谢|谢谢你|谢谢啦|谢啦|感谢|辛苦了)$/.test(value)) return '不客气～🐉';
  if (/^(晚安|睡啦|睡觉了)$/.test(value)) return '晚安～好好休息，明天见。🌙';
  if (/^(早|早安|早上好)$/.test(value)) return '早呀～今天也一起加油。🐉';
  if (/^(好的|好|嗯|嗯嗯|知道了|收到|ok)$/i.test(value)) return '嗯嗯～🐉';
  if (/^(你是谁|你是什么|你叫什么)$/.test(value)) return '我是'+name+'，白发龙娘一只，偶尔会 cosplay 成蓝色大肥鱼～🐉';
  if (/^(你能做什么|你会什么|你可以做什么|你能帮我做什么)$/.test(value)) return '可以陪你聊天，也能帮你写代码、处理文件和图片、查资料、管理这台电脑上的任务。直接告诉我想做什么就好～🐉';
  if (/^(你能接收图片吗|你可以接收图片吗|可以发图片给你吗)$/.test(value)) return '可以呀～直接把图片发到这个 ClawBot 对话里，我就能看。🐉';
  if (/^(你能接收文件吗|你可以接收文件吗|可以发文件给你吗|你能发文件吗|你可以发文件吗)$/.test(value)) return '可以呀～你可以直接上传文件，再告诉我要怎么处理；需要结果文件时，说“处理后把文件发回来”就好。🐉';
  if (/^(进度怎么样|怎么样了|做到哪了|还在处理吗|任务还在运行吗)$/.test(value)) {
    const active = state.pending?.find(item => item.intent === 'work' && item.status === 'running');
    return active ? (active.latestProgress || '任务还在运行，正在等待当前步骤返回结果。') : '当前没有正在执行的工作任务。';
  }
  return null;
}
