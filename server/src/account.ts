import { DurableObject } from "cloudflare:workers";

/** A plan written by an agent, waiting for the app to import it. */
export interface InboxItem {
  id: string;
  /** Set when the agent updates an existing plan; absent for a new plan. */
  planId?: string;
  name: string;
  link: string;
  createdAt: string;
}

// Storage values are limited in size, so the snapshot is saved in chunks.
const CHUNK = 32_000;
const MAX_INBOX = 50;

/** One user's data: the app's secret (hashed), its latest snapshot and the agents' inbox. */
export class Account extends DurableObject {
  /** The first secret to arrive claims the account; later calls must present the same one. */
  async claim(secretHash: string): Promise<boolean> {
    const owner = await this.ctx.storage.get<string>("owner");
    if (owner === undefined) {
      await this.ctx.storage.put("owner", secretHash);
      return true;
    }
    return owner === secretHash;
  }

  /**
   * Agent tokens carry this key; replacing it cuts off every agent at once, without waiting
   * for the OAuth grants (in eventually consistent KV) to be found and revoked.
   */
  async agentsKey(): Promise<string> {
    let key = await this.ctx.storage.get<string>("agentsKey");
    if (key === undefined) {
      key = crypto.randomUUID();
      await this.ctx.storage.put("agentsKey", key);
    }
    return key;
  }

  /** The current key, without creating one: undefined for a deleted account. */
  async currentAgentsKey(): Promise<string | undefined> {
    return this.ctx.storage.get<string>("agentsKey");
  }

  async rotateAgentsKey(): Promise<void> {
    await this.ctx.storage.put("agentsKey", crypto.randomUUID());
  }

  async putSnapshot(json: string): Promise<void> {
    const previous = (await this.ctx.storage.get<number>("snapshotChunks")) ?? 0;
    const count = Math.ceil(json.length / CHUNK);
    for (let start = 0; start < count; start += 100) {
      const entries: Record<string, string> = {};
      for (let index = start; index < Math.min(count, start + 100); index++) {
        entries[`snapshot:${index}`] = json.slice(index * CHUNK, (index + 1) * CHUNK);
      }
      await this.ctx.storage.put(entries);
    }
    const stale = [];
    for (let index = count; index < previous; index++) stale.push(`snapshot:${index}`);
    if (stale.length > 0) await this.ctx.storage.delete(stale);
    await this.ctx.storage.put("snapshotChunks", count);
  }

  async getSnapshot(): Promise<string | null> {
    const count = await this.ctx.storage.get<number>("snapshotChunks");
    if (!count) return null;
    const keys = Array.from({ length: count }, (_, index) => `snapshot:${index}`);
    let json = "";
    for (let start = 0; start < keys.length; start += 100) {
      const chunks = await this.ctx.storage.get<string>(keys.slice(start, start + 100));
      for (const key of keys.slice(start, start + 100)) json += chunks.get(key) ?? "";
    }
    return json;
  }

  async addToInbox(item: InboxItem): Promise<boolean> {
    const inbox = await this.listInbox();
    if (inbox.length >= MAX_INBOX) return false;
    await this.ctx.storage.put("inbox", [...inbox, item]);
    return true;
  }

  async listInbox(): Promise<InboxItem[]> {
    return (await this.ctx.storage.get<InboxItem[]>("inbox")) ?? [];
  }

  async removeFromInbox(id: string): Promise<void> {
    const inbox = await this.listInbox();
    await this.ctx.storage.put(
      "inbox",
      inbox.filter((item) => item.id !== id),
    );
  }

  /** Deletes everything, for when the user turns the connector off. */
  async destroy(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
