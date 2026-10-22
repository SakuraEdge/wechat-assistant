export class WorkProgress {
  constructor(entry, { send, persist, now = Date.now, interval = 45000, minInterval = 30000 }) {
    this.entry = entry; this.send = send; this.persist = persist; this.now = now;
    this.interval = interval; this.minInterval = minInterval; this.lastSent = now(); this.closed = false;
  }
  update(message) { if (message?.text?.trim()) this.entry.latestProgress = message.text.trim().slice(0, 500); }
  async tick() {
    if (this.closed || this.inFlight || this.entry.waitingForUser || this.entry.status !== 'running' || this.entry.progressReceipt?.status === 'unknown') return;
    const now = this.now(); const message = this.entry.latestProgress;
    const changed = message && message !== this.entry.lastProgressText;
    if (now - this.lastSent < (changed ? this.minInterval : this.interval)) return;
    const work = async () => {
      const sequence = (this.entry.progressSequence || 0) + 1; this.entry.progressSequence = sequence;
      const receipt = { sequence, status: 'attempting' }; this.entry.progressReceipt = receipt;
      const text = changed ? message : '任务仍在运行，正在等待模型或工具返回；目前还没有新的结果。';
      await this.persist(); this.lastSent = now;
      try { await this.send(text, 'cw-progress-' + this.entry.id.slice(0, 28) + '-' + sequence); receipt.status = 'sent'; }
      catch { receipt.status = 'unknown'; }
      this.entry.lastProgressText = text; await this.persist();
    };
    this.inFlight = work(); try { await this.inFlight; } finally { this.inFlight = null; }
  }
  async close() { this.closed = true; if (this.inFlight) await this.inFlight; }
}
