import { DurableObject } from "cloudflare:workers";
import type { Entitlement } from "./subscription";

/** A plan written by an agent, waiting for the app to import it. */
export interface InboxItem {
  id: string;
  /** Set when the agent updates an existing plan; absent for a new plan. */
  planId?: string;
  name: string;
  link: string;
  createdAt: string;
}

/** An agent the user connected, for the app's list. */
export interface ConnectedAgent {
  name: string;
  connectedAt: string;
}

/** Whether a pairing code is still waiting, was used (and by which agent), or expired. */
export type PairingStatus = { status: "waiting" } | { status: "connected"; agent: string } | { status: "expired" };

interface Pairing {
  expiresAt: number;
  agent?: string;
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
    await this.ctx.storage.delete("agents");
  }

  async agents(): Promise<ConnectedAgent[]> {
    return (await this.ctx.storage.get<ConnectedAgent[]>("agents")) ?? [];
  }

  /** Remembers a code the app is showing, so the app can ask whether it was used. */
  async issuePairingCode(code: string, expiresAt: number): Promise<void> {
    const pairings = await this.pairings();
    pairings[code] = { expiresAt };
    await this.ctx.storage.put("pairings", pairings);
  }

  /** An agent signed in with `code`: add it to the list and mark the code as used. */
  async completePairing(code: string, agent: string): Promise<void> {
    const pairings = await this.pairings();
    pairings[code] = { expiresAt: pairings[code]?.expiresAt ?? Date.now(), agent };
    await this.ctx.storage.put("pairings", pairings);
    const agents = await this.agents();
    await this.ctx.storage.put("agents", [...agents, { name: agent, connectedAt: new Date().toISOString() }]);
  }

  async pairingStatus(code: string): Promise<PairingStatus> {
    const pairing = (await this.pairings())[code];
    if (pairing?.agent) return { status: "connected", agent: pairing.agent };
    if (!pairing || pairing.expiresAt <= Date.now()) return { status: "expired" };
    return { status: "waiting" };
  }

  /** Codes from the last hour; older ones are dropped. */
  private async pairings(): Promise<Record<string, Pairing>> {
    const all = (await this.ctx.storage.get<Record<string, Pairing>>("pairings")) ?? {};
    const cutoff = Date.now() - 3_600_000;
    return Object.fromEntries(Object.entries(all).filter(([, pairing]) => pairing.expiresAt > cutoff));
  }

  /** The AI Agents subscription, from the latest Apple-signed transaction. */
  async entitlement(): Promise<Entitlement | undefined> {
    return this.ctx.storage.get<Entitlement>("entitlement");
  }

  async setEntitlement(entitlement: Entitlement | undefined): Promise<void> {
    if (entitlement) await this.ctx.storage.put("entitlement", entitlement);
    else await this.ctx.storage.delete("entitlement");
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
