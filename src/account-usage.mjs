const number=value=>typeof value==='number'&&Number.isFinite(value);
function window(value){
 if(!value||typeof value!=='object')return null;
 const used=number(value.usedPercent)&&value.usedPercent>=0?Math.min(100,value.usedPercent):null;
 const minutes=number(value.windowDurationMins)&&value.windowDurationMins>0?value.windowDurationMins:null;
 const reset=number(value.resetsAt)&&value.resetsAt>0&&value.resetsAt<=8.64e12?value.resetsAt:null;
 return {used_percent:used,remaining_percent:used===null?null:100-used,minutes,resets_at:reset===null?null:new Date(reset*1000).toISOString()};
}
export function normalizeUsage(result,at=new Date().toISOString()){
 const many=result?.rateLimitsByLimitId;
 const entries=many&&typeof many==='object'&&Object.keys(many).length?Object.entries(many):result?.rateLimits?[[result.rateLimits.limitId||'codex',result.rateLimits]]:[];
 const buckets=entries.filter(([,value])=>value&&typeof value==='object').map(([id,value])=>{
  const windows=[window(value.primary),window(value.secondary)].filter(Boolean);
  return {id:String(id).slice(0,100),label:String(value.limitName||id).slice(0,100),five_hour:windows.find(w=>w.minutes===300)||null,weekly:windows.find(w=>w.minutes===10080)||null,windows};
 });
 return {status:'usage',available:buckets.some(b=>b.windows.some(w=>w.used_percent!==null)),buckets,preferred_id:buckets.find(b=>b.id==='codex')?.id||buckets[0]?.id||null,at,note:'当前Codex登录账号共享额度；非单个微信实例用量。未提供的窗口和重置时间不会推算。'};
}
