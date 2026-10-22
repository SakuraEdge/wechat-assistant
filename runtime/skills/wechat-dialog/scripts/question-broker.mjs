import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
const hash=value=>createHash('sha256').update(value).digest('hex');
async function writeMeta(directory,id,value) {
  const temporary=path.join(directory,id+'.'+process.pid+'.'+Date.now()+'.meta.tmp');
  await fs.writeFile(temporary,JSON.stringify(value),{flag:'wx'});await fs.rename(temporary,path.join(directory,id+'.meta.json'));
}
export const QUESTION_BROKER_VERSION='dual-questions-v2';
export class QuestionBroker {
  constructor(directory,store,{now=()=>Date.now()}={}){this.directory=directory;this.store=store;this.now=now;}
  async create({thread_id,event_id,question,options=[],ttl_ms=86400000}) {
    if(!/^[a-zA-Z0-9-]{8,80}$/.test(thread_id||'')||typeof event_id!=='string'||!event_id||event_id.length>256||typeof question!=='string'||!question.trim()||question.length>3000||!Array.isArray(options)||options.length>8||options.some(value=>typeof value!=='string'||!value.trim()||value.length>300)||ttl_ms<60000||ttl_ms>86400000)throw Error('INVALID_QUESTION');
    const id=hash(thread_id+':'+event_id);await fs.mkdir(this.directory,{recursive:true});
    const existing=await this.store.load(id);if(existing){if(existing.question!==question||JSON.stringify(existing.options)!==JSON.stringify(options))throw Error('QUESTION_EVENT_CONFLICT');const answer=await this.store.load(id+'.answer');await writeMeta(this.directory,id,{id,short_id:existing.short_id,thread_id,status:answer?'answered':'pending'});return existing;}
    const questionRecord={id,short_id:id.slice(0,12),thread_id,question,options,created_at:new Date(this.now()).toISOString(),expires_at:new Date(this.now()+ttl_ms).toISOString()};
    try{const lock=await fs.open(path.join(this.directory,id+'.create.reserved'),'wx');await lock.close();}
    catch(error){if(error.code!=='EEXIST')throw error;for(let attempt=0;attempt<20;attempt++){const saved=await this.store.load(id);if(saved){if(saved.question!==question||JSON.stringify(saved.options)!==JSON.stringify(options))throw Error('QUESTION_EVENT_CONFLICT');return saved;}await new Promise(resolve=>setTimeout(resolve,100));}throw Error('QUESTION_CREATION_UNCONFIRMED');}
    await this.store.save(questionRecord,id);
    await writeMeta(this.directory,id,{id,short_id:questionRecord.short_id,thread_id,status:'pending'});
    return questionRecord;
  }
  async find(id) {
    if(!/^(?:[a-f0-9]{12}|[a-f0-9]{64})$/.test(id||''))throw Error('INVALID_QUESTION_ID');
    const names=await fs.readdir(this.directory);const matches=names.filter(name=>/^[a-f0-9]{64}\.meta\.json$/.test(name)&&name.startsWith(id));
    if(matches.length!==1)throw Error(matches.length?'QUESTION_ID_AMBIGUOUS':'QUESTION_NOT_FOUND');
    const record=await this.store.load(matches[0].slice(0,-10));if(!record)throw Error('QUESTION_NOT_FOUND');return record;
  }
  async status(id) {
    const question=await this.find(id);const answer=await this.store.load(question.id+'.answer');
    if(answer)return {status:'answered',question,answer};
    try{await fs.access(path.join(this.directory,question.id+'.answer.reserved'));return {status:'resolving',question};}catch(error){if(error.code!=='ENOENT')throw error;}
    return {status:this.now()>Date.parse(question.expires_at)?'expired':'pending',question};
  }
  async resolve(id,answer,channel) {
    if(typeof answer!=='string'||!answer.trim()||answer.length>6000||!['desktop','wechat'].includes(channel))throw Error('INVALID_QUESTION_ANSWER');
    const current=await this.status(id);if(current.status!=='pending')return {...current,won:false};
    try{const lock=await fs.open(path.join(this.directory,current.question.id+'.answer.reserved'),'wx');await lock.close();}
    catch(error){if(error.code!=='EEXIST')throw error;return {...await this.status(id),won:false};}
    const text=answer.trim();const selected=/^[1-8]$/.test(text)?current.question.options[Number(text)-1]:null;
    const response={question_id:current.question.id,answer:selected||text,channel,at:new Date(this.now()).toISOString()};
    await this.store.save(response,current.question.id+'.answer');
    await writeMeta(this.directory,current.question.id,{id:current.question.id,short_id:current.question.short_id,thread_id:current.question.thread_id,status:'answered'});
    return {status:'answered',question:current.question,answer:response,won:true};
  }
  async list(status) {
    let names;try{names=await fs.readdir(this.directory);}catch(error){if(error.code==='ENOENT')return [];throw error;}
    const records=[];for(const name of names.filter(value=>/^[a-f0-9]{64}\.meta\.json$/.test(value))){const meta=JSON.parse(await fs.readFile(path.join(this.directory,name),'utf8'));if(!status||meta.status===status)records.push(meta);}return records;
  }
}
export function formatQuestion(question) {
  return 'GPT小姐有个问题需要你回复 🐉\n问题编号：'+question.short_id+'\n'+question.question+(question.options.length?'\n'+question.options.map((value,index)=>(index+1)+'. '+value).join('\n'):'')+'\n\n回复：/回答 '+question.short_id+' 你的答案\n客户端或微信先回复的一端生效，另一端会提示已收到。';
}
export async function queueQuestionNotice({directory,store,question,answer}) {
  const id=hash('dual-question:'+question.id+':'+(answer?'received':'ask'));await fs.mkdir(path.join(directory,'outbox'),{recursive:true});
  try{const lock=await fs.open(path.join(directory,'outbox',id+'.reserved'),'wx');await lock.close();}catch(error){if(error.code==='EEXIST')return {status:'duplicate',event_hash:id};throw error;}
  const content=answer?'已收到你在'+(answer.channel==='desktop'?'客户端':'微信')+'对问题 '+question.short_id+' 的回复，将据此继续处理。🐉':formatQuestion(question);
  await store.save({id,title:'',content,kind:'question'},'outbox/'+id);return {status:'queued',event_hash:id};
}
