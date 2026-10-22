import fs from 'node:fs/promises';import path from 'node:path';
export function connectionPrompt(root){
 if(!path.isAbsolute(root)||/[\r\n\0]/.test(root))throw Error('INVALID_INSTALL_ROOT');
 const script=path.join(root,'initialize.ps1').replaceAll("'","''");
 return '请在当前Codex客户端的工具环境中，运行以下初始化命令，并核对连接结果。保留当前提供商、主聊天模型和平台审批，不复制任何账号或认证数据。\n\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \''+script+'\' -NoLaunch\n\n完成后告诉我回到ClawBot实例管理器点击“重新检测连接”，再由我本人微信扫码。';
}
export async function setupStatus(root,environment,{readable=async file=>fs.access(file).then(()=>true,()=>false)}={}){
 const cli=environment.CODEX_CLI_PATH,pipe=environment.CODEX_APP_TOOLS_PIPE_PATH;
 const cli_available=typeof cli==='string'&&path.isAbsolute(cli)&&await readable(cli);
 const desktop_configured=typeof pipe==='string'&&pipe.startsWith('\\\\.\\pipe\\');
 return {status:'setup_status',version:'1.2.0',node_version:process.versions.node,bundled_node:path.resolve(process.execPath).toLowerCase()===path.resolve(root,'runtime/node/node.exe').toLowerCase(),cli_available,desktop_configured,ready:cli_available&&desktop_configured,prompt:connectionPrompt(root),note:'配置就绪后可读取模型校验连接；客户端退出或更新后可能需要重新初始化。'};
}
