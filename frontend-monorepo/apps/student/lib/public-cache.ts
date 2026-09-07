"use client";

/**
 * 公开查询的轻量内存缓存（首页热门/分类/名师）。
 * 路由切换回首页时直接读缓存，避免重复打后端；TTL 到期自动刷新。
 * 登录态变更（选课/人数变化实时性要求不高，60s 可接受）。
 */

interface Entry {
  at: number;
  value: unknown;
}

const store = new Map<string, Entry>();

export async function cachedQuery<T>(
  key: string,
  ttlMs: number,
  fetcher: () => Promise<T>
): Promise<T> {
  const hit = store.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.value as T;
  const value = await fetcher();
  store.set(key, { at: Date.now(), value });
  return value;
}

export function invalidateQuery(keyPrefix?: string): void {
  if (!keyPrefix) {
    store.clear();
    return;
  }
  for (const key of [...store.keys()]) {
    if (key.startsWith(keyPrefix)) store.delete(key);
  }
}
