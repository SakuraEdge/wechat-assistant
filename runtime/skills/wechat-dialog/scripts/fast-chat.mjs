import { localChatReply } from './message-routing.mjs';
export async function fastChat(state, entry, { nativeReply } = {}) {
  const started = performance.now();
  const immediate = !(entry.imagePaths?.length) && localChatReply(entry.text, state);
  if (!immediate && !nativeReply) throw Error('CHAT_NATIVE_CONNECTION_REQUIRED');
  const text = (immediate || await nativeReply(entry, state)).trim().slice(0, 1200);
  if (!text) throw Error('CHAT_EMPTY_REPLY');
  state.chatHistory = [...(state.chatHistory || []), { role: 'user', content: entry.text || '[图片]' }, { role: 'assistant', content: text }].slice(-12);
  state.lastChat = { route: immediate ? 'local' : 'codex_no_tools', elapsed_ms: Math.round(performance.now() - started), at: new Date().toISOString() };
  return { status: 'completed', text };
}
