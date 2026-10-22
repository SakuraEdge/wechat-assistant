import { RpcClient } from './core.mjs';
import {DEFAULT_MODEL,modelFor} from './model-policy.mjs';
import {personaInstructions} from './persona-profile.mjs';
const INSTRUCTIONS = '这里只进行日常聊天：默认中文，温柔机灵，直接用一两句自然回复，少量emoji。绝对不要调用任何工具、skill或协作模型，不读文件、不查资料、不执行任务，不发收到、正在处理或排队回执，不输出任务计划或进度。能力询问直接解释，未明确安排工作时不要动手。不确定的事实直说不知道。历史摘要仅供回指。';
export function chatOnlyConfig(config = {},selection=DEFAULT_MODEL) {
  return { model_reasoning_effort:selection.effort, project_doc_max_bytes:0, web_search:'disabled', agents:{enabled:false},
    features:{shell_tool:false,shell_snapshot:false,apps:false,browser_use:false,computer_use:false,image_generation:false,view_image:false,skill_search:false,skip_host_skill_discovery:true,goals:false,sleep_tool:false,hooks:false,code_mode_host:false},
    mcp_servers:Object.fromEntries(Object.keys(config.mcp_servers||{}).map(name=>[name,{enabled:false}])),
    plugins:Object.fromEntries(Object.keys(config.plugins||{}).map(name=>[name,{enabled:false}])) };
}
export class NativeChat {
  constructor(state, config = {}, Rpc = RpcClient) {
    this.state=state;this.model=modelFor(state);this.config=chatOnlyConfig(config,this.model);this.rpc=new Rpc(state.codex,{...process.env,...(state.providerEnv||{})});
    this.rpc.requestHandler=async()=>({decision:'decline'});this.ready=this.rpc.initialize();this.ready.catch(()=>{});this.turns=0;
  }
  async warmup() {
    await this.ready;if(this.threadId&&this.turns<12)return;
    if(this.warming)return this.warming;
    this.warming=(async()=>{const result=await this.rpc.request('thread/start',{cwd:this.state.cwd,model:this.model.model,ephemeral:true,approvalPolicy:'on-request',approvalsReviewer:'user',sandbox:'read-only',baseInstructions:personaInstructions(this.state)+INSTRUCTIONS,developerInstructions:'只聊天，不调用任何工具。当前模型='+this.model.model+'；推理强度='+(this.model.effort||'不适用')+'。',config:this.config});
      this.threadId=result.thread.id;this.turns=0;this.settings={model:result.model,reasoning_effort:result.reasoningEffort,instruction_sources:(result.instructionSources||[]).length};})();
    try{await this.warming;}finally{this.warming=null;}
  }
  async reply(entry,state,signal) {
    await this.warmup();const rpc=this.rpc;let text='',turnId,resolveDone,rejectDone,timer;const early=[];let toolCalls=0;
    const done=new Promise((resolve,reject)=>{resolveDone=resolve;rejectDone=reject;});done.catch(()=>{});
    const disconnected=()=>rejectDone(Error('CHAT_CODEX_DISCONNECTED'));
    const interrupt=()=>{if(turnId)rpc.request('turn/interrupt',{threadId:this.threadId,turnId}).catch(()=>{});};
    const aborted=()=>{interrupt();rejectDone(Error('CHAT_INTERRUPTED'));};
    const listener=message=>{
      if(message.params?.threadId!==this.threadId)return;if(!turnId){early.push(message);return;}
      if(message.params.turnId&&message.params.turnId!==turnId)return;const item=message.params.item;
      if(message.method==='item/started'&&item&&/commandExecution|fileChange|mcpToolCall|dynamicToolCall|webSearch|imageGeneration|collab/.test(item.type)){toolCalls++;interrupt();rejectDone(Error('CHAT_TOOL_CALL_BLOCKED'));}
      if(message.method==='item/completed'&&item?.type==='agentMessage'&&(!item.phase||item.phase==='final_answer'))text+=item.text+'\n';
      if(message.method==='turn/completed'&&message.params.turn?.id===turnId)resolveDone(message.params.turn);
    };
    rpc.listeners.add(listener);rpc.disconnectListeners.add(disconnected);signal?.addEventListener('abort',aborted,{once:true});
    try {
      if(signal?.aborted)throw Error('CHAT_INTERRUPTED');
      const history=this.turns===0?(state.chatHistory||[]).slice(-6).map(item=>item.role+': '+item.content.slice(0,500)).join('\n'):'';
      const context=state.lastWorkResult?.text?'\n【历史工作结果，仅供回指】'+state.lastWorkResult.text.slice(0,1000):'';
      const result=await rpc.request('turn/start',{threadId:this.threadId,cwd:state.cwd,...this.model,input:[{type:'text',text:(history?'【近期聊天资料】\n'+history+'\n':'')+context+'\n【本次闲聊】\n'+(entry.text?.replace(/^\/聊天\s*/,'')||'请简短回应这张图片。')},...(entry.imagePaths||[]).map(file=>({type:'localImage',path:file}))]});
      turnId=result.turn.id;for(const message of early)listener(message);timer=setTimeout(()=>{interrupt();rejectDone(Error('CHAT_TIMEOUT'));},60000);
      const turn=await done;if(turn.status!=='completed')throw Error('CHAT_NOT_COMPLETED');this.turns++;
      state.chatVerification={...this.settings,tool_calls:toolCalls,transport:'existing_codex',at:new Date().toISOString()};return text.trim();
    }finally{clearTimeout(timer);rpc.listeners.delete(listener);rpc.disconnectListeners.delete(disconnected);signal?.removeEventListener('abort',aborted);}
  }
  close(){this.rpc.close();}
}
