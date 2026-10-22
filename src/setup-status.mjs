import fs from 'node:fs/promises';import path from 'node:path';
export function connectionPrompt(root){
 if(!path.isAbsolute(root)||/[\r\n\0]/.test(root))throw Error('INVALID_INSTALL_ROOT');
 const script=path.join(root,'initialize.ps1').replaceAll("'","''");
 return '请在当前Codex客户端的工具环境中，运行以下初始化命令，并核对连接结果。保留当前提供商、主聊天模型和平台审批，不复制任何账号或认证数据。\n\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \''+script+'\' -NoLaunch\n\n运行结束后，请明确提醒我：回到ClawBot实例管理器点击“重新检测连接”；检测通过后点击“下一步：新增微信用户”或主界面“新增微信用户”，输入名称，最后由本人微信扫码。连接客户端并不等于已经新增或绑定微信用户。';
}
export async function setupStatus(root,environment,{readable=async file=>fs.access(file).then(()=>true,()=>false),verifyClient=null}={}){
 const cli=environment.CODEX_CLI_PATH,pipe=environment.CODEX_APP_TOOLS_PIPE_PATH;
 const cli_available=typeof cli==='string'&&path.isAbsolute(cli)&&await readable(cli);
 const desktop_configured=typeof pipe==='string'&&pipe.startsWith('\\\\.\\pipe\\');
 let client_verified=null,connection_error=null;
 if(verifyClient){client_verified=false;if(cli_available&&desktop_configured){try{await verifyClient();client_verified=true;}catch(error){connection_error=/^[A-Z0-9_-]+$/.test(error.message)?error.message:'CLIENT_CHECK_FAILED';}}}
 return {status:'setup_status',node_version:process.versions.node,bundled_node:path.resolve(process.execPath).toLowerCase()===path.resolve(root,'runtime/node/node.exe').toLowerCase(),cli_available,desktop_configured,client_verified,connection_error,checked_at:new Date().toISOString(),ready:cli_available&&desktop_configured&&client_verified!==false,prompt:connectionPrompt(root),note:'检测会实际请求客户端模型接口；桌面连接配置就绪不代表已绑定微信。下一步：新增微信用户并本人扫码。'};
}
