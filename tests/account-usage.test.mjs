import test from 'node:test';import assert from 'node:assert/strict';
import {normalizeUsage} from '../src/account-usage.mjs';
import {setupStatus,connectionPrompt} from '../src/setup-status.mjs';
import path from 'node:path';import os from 'node:os';
const root=path.join(os.tmpdir(),'clawbot-account-tests');
test('usage prefers per-bucket data, interprets used percent, and converts Unix seconds',()=>{
 const value=normalizeUsage({rateLimits:{primary:{usedPercent:99,windowDurationMins:300}},rateLimitsByLimitId:{codex:{primary:{usedPercent:12,windowDurationMins:300,resetsAt:1800000000},secondary:{usedPercent:25,windowDurationMins:10080,resetsAt:1800600000}},other:{primary:{usedPercent:50,windowDurationMins:60}}}},'fixed');
 assert.equal(value.buckets.length,2);assert.equal(value.preferred_id,'codex');assert.equal(value.buckets[0].five_hour.remaining_percent,88);assert.equal(value.buckets[0].weekly.remaining_percent,75);assert.equal(value.buckets[0].five_hour.resets_at,new Date(1800000000*1000).toISOString());assert.equal(value.buckets[1].five_hour,null);assert.equal(value.buckets[1].weekly,null);assert.equal(value.at,'fixed');
});
test('absent windows, null percentages and reset times stay unknown rather than zero',()=>{
 assert.equal(normalizeUsage(null).available,false);const value=normalizeUsage({rateLimits:{primary:{usedPercent:null,windowDurationMins:300,resetsAt:null},secondary:null}});
 assert.equal(value.available,false);assert.equal(value.buckets[0].five_hour.remaining_percent,null);assert.equal(value.buckets[0].five_hour.resets_at,null);assert.equal(value.buckets[0].weekly,null);
 const invalid=normalizeUsage({rateLimits:{primary:{usedPercent:-1,windowDurationMins:300,resetsAt:'123'}}});assert.equal(invalid.buckets[0].five_hour.remaining_percent,null);assert.equal(invalid.buckets[0].five_hour.resets_at,null);
});
test('legacy quota data works and primary/secondary order does not invent window durations',()=>{
 const value=normalizeUsage({rateLimits:{secondary:{usedPercent:110,windowDurationMins:300},primary:{usedPercent:0,windowDurationMins:10080}}});assert.equal(value.available,true);assert.equal(value.buckets[0].five_hour.remaining_percent,0);assert.equal(value.buckets[0].weekly.remaining_percent,100);
});
test('manual connection detection actually probes and reports both success and failure',async()=>{
 const env={CODEX_CLI_PATH:process.execPath,CODEX_APP_TOOLS_PIPE_PATH:'\\\\.\\pipe\\fixture'};let calls=0;
 const good=await setupStatus(root,env,{readable:async()=>true,verifyClient:async()=>{calls++;}});assert.equal(good.ready,true);assert.equal(good.client_verified,true);assert.equal(calls,1);assert.ok(good.checked_at);
 const bad=await setupStatus(root,env,{readable:async()=>true,verifyClient:async()=>{throw Error('CODEX_RPC_TIMEOUT');}});assert.equal(bad.ready,false);assert.equal(bad.connection_error,'CODEX_RPC_TIMEOUT');
 const missing=await setupStatus(root,{}, {readable:async()=>true,verifyClient:async()=>{calls++;}});assert.equal(missing.ready,false);assert.equal(calls,1);assert.match(connectionPrompt(root),/新增微信用户/);assert.match(connectionPrompt(root),/并不等于/);
});
