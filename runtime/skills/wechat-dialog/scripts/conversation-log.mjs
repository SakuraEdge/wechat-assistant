import path from 'node:path';

export const CONVERSATION_LIMIT=300;
export function safeText(value){return String(value||'').replace(/\bBearer\s+[A-Za-z0-9._~+/=-]{12,}/gi,'Bearer [已隐藏]').replace(/\bsk-[A-Za-z0-9_-]{16,}/g,'[密钥已隐藏]').slice(0,4000);}
const attachment=item=>({kind:['image','file'].includes(item?.kind)?item.kind:'file',name:safeText(path.win32.basename(path.basename(String(item?.name||'附件')))).slice(0,160)});
function row(value){return {id:String(value.id||'').slice(0,160),role:value.role==='user'?'user':'assistant',text:safeText(value.text),at:Number.isFinite(Date.parse(value.at))?new Date(value.at).toISOString():null,delivery:['received','sent','unknown','failed','attempting','legacy'].includes(value.delivery)?value.delivery:'unknown',attachments:(Array.isArray(value.attachments)?value.attachments:[]).slice(0,4).map(attachment)};}
export function recordMessage(state,value){
 if(!value.id)return;const records=state.conversationLog||=[];const clean=row(value);const index=records.findIndex(item=>item.id===clean.id);if(index<0)records.push(clean);else records[index]={...records[index],...clean};state.conversationLog=records.slice(-CONVERSATION_LIMIT);
}
export function exportConversation(state){
 if(Array.isArray(state.conversationLog)&&state.conversationLog.length)return {source:'wechat',messages:state.conversationLog.slice(-CONVERSATION_LIMIT).map(row)};
 const messages=(state.chatHistory||[]).slice(-12).map((item,index)=>row({id:'legacy-'+index,role:item.role,text:item.content,at:item.at,delivery:'legacy'}));
 if(state.lastWorkResult?.text)messages.push(row({id:'legacy-work',role:'assistant',text:state.lastWorkResult.text,at:state.lastWorkResult.at,delivery:'legacy'}));
 return {source:'legacy-summary',messages};
}
export function observeOutgoing(api,state){
 for(const [method,describe]of Object.entries({send:text=>({text}),sendImage:file=>({text:'[图片]',attachments:[{kind:'image',name:path.basename(file)}]}),sendFile:file=>({text:'[文件]',attachments:[{kind:'file',name:file.name||path.basename(file.path)}]})})){
  const original=api[method].bind(api);api[method]=async(owner,context,value,id)=>{
   const message={id:'out-'+id,role:'assistant',at:new Date().toISOString(),...describe(value)};
   recordMessage(state,{...message,delivery:'attempting'});
   try{const result=await original(owner,context,value,id);recordMessage(state,{...message,delivery:'sent'});return result;}
   catch(error){recordMessage(state,{...message,delivery:/^WECHAT_(HTTP_4|API_)/.test(error.message)?'failed':'unknown'});throw error;}
  };
 }
 return api;
}
