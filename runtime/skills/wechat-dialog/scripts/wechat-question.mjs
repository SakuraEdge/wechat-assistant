// Desktop agents use this companion to mirror native questions and commit the first answer.
import fs from 'node:fs/promises';import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {SecureStore} from './core.mjs';import {QuestionBroker,queueQuestionNotice} from './question-broker.mjs';
const scriptDir=path.dirname(fileURLToPath(import.meta.url));
const questionDir=path.join(process.env.LOCALAPPDATA,'Codex','wechat-questions');
const primaryDir=path.join(process.env.LOCALAPPDATA,'Codex','wechat-dialog');
const helper=path.join(scriptDir,'secure-store.ps1');
const broker=new QuestionBroker(questionDir,new SecureStore(questionDir,helper));const primary=new SecureStore(primaryDir,helper);
const args=process.argv.slice(2);const option=name=>{const i=args.indexOf(name);return i<0?undefined:args[i+1];};
try {
  let result;
  if(args[0]==='ask') {
    const input=JSON.parse(await fs.readFile(option('--file'),'utf8'));
    const thread_id=process.env.CODEX_THREAD_ID||input.thread_id;
    const question=await broker.create({...input,thread_id});
    const queued=await queueQuestionNotice({directory:primaryDir,store:primary,question});
    result={status:'pending',question_id:question.short_id,question:question.question,options:question.options,wechat:queued,desktop_instruction:'使用客户端原生提问工具展示同一问题，并附问题编号；任一端答复后用resolve/status取得锁定答案。'};
  } else if(args[0]==='resolve') {
    const response=JSON.parse(await fs.readFile(option('--file'),'utf8'));
    const original=await broker.find(option('--id'));
    if(process.env.CODEX_THREAD_ID!==original.thread_id)throw Error('QUESTION_ORIGIN_MISMATCH');
    result=await broker.resolve(option('--id'),response.answer,'desktop');
    if(result.won)await queueQuestionNotice({directory:primaryDir,store:primary,question:result.question,answer:result.answer});
  } else if(args[0]==='ui-complete') {
    result=await broker.status(option('--id'));
    if(process.env.CODEX_THREAD_ID!==result.question.thread_id||result.status!=='answered')throw Error('QUESTION_ORIGIN_MISMATCH');
    const outcome=option('--result');if(!['submitted','already_closed','unconfirmed'].includes(outcome))throw Error('INVALID_UI_RESULT');
    await fs.writeFile(path.join(questionDir,result.question.id+'.ui.receipt.json'),JSON.stringify({status:outcome,at:new Date().toISOString(),answer_channel:result.answer.channel}));
    result={status:outcome,question_id:result.question.short_id};
  } else if(args[0]==='status'||args[0]==='wait') {
    const deadline=Date.now()+(args[0]==='wait'?45000:0);
    do{result=await broker.status(option('--id'));if(result.status!=='pending'||Date.now()>=deadline)break;await new Promise(resolve=>setTimeout(resolve,1000));}while(true);
  } else throw Error('INVALID_QUESTION_ACTION');
  console.log(JSON.stringify(result));
}catch(error){console.log(JSON.stringify({status:'error',error:/^[A-Z][A-Z0-9_-]*$/.test(error.message||'')?error.message:'QUESTION_OPERATION_FAILED'}));process.exitCode=1;}
