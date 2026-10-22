import path from 'node:path';
const keys=['CODEX_APP_TOOLS_PIPE_PATH','CODEX_CLI_PATH','CODEX_ELECTRON_RESOURCES_PATH','CODEX_MCP_NODE_PATH','CODEX_BROWSER_USE_NODE_PATH','CODEX_APP_TOOLS_CALLER_HOST_ID'];
export async function desktopEnvironment(Store,helper,env=process.env) {
  const directory=path.join(env.LOCALAPPDATA,'Codex','wechat-manager');const store=new Store(directory,helper);
  const current=Object.fromEntries(keys.filter(key=>typeof env[key]==='string'&&env[key]).map(key=>[key,env[key]]));
  if(current.CODEX_APP_TOOLS_PIPE_PATH){await store.save(current,'desktop-connection');return {...env,...current};}
  let cached;try{cached=await store.load('desktop-connection');}catch{return env;}
  return {...env,...Object.fromEntries(keys.filter(key=>typeof cached?.[key]==='string').map(key=>[key,cached[key]]))};
}
