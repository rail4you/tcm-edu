/**
 * Shared auth token storage for the three dev apps (student :3001,
 * admin :3002, teacher :3003).
 *
 * localStorage is per-origin *including port*, so the three apps cannot see
 * each other's tokens. Cookies ignore the port, so we mirror the Bearer
 * token into a `tcm_auth_token` cookie on write and use it as a fallback on
 * read. This makes cross-app debugging (e.g. enroll as student, then check
 * the teacher console) work without logging in three times.
 *
 * Each app still validates the adopted token via `/api/auth/me` and only
 * accepts roles it supports.
 */

const TOKEN_KEY = "auth_token";
const COOKIE_KEY = "tcm_auth_token";
const COOKIE_MAX_AGE = 60 * 60 * 24 * 7;

function isBrowser(): boolean {
  return typeof window !== "undefined" && typeof document !== "undefined";
}

function readCookie(): string | null {
  if (!isBrowser()) return null;
  const match = document.cookie
    .split(";")
    .map((c) => c.trim())
    .find((c) => c.startsWith(`${COOKIE_KEY}=`));
  return match ? decodeURIComponent(match.slice(COOKIE_KEY.length + 1)) : null;
}

function writeCookie(token: string): void {
  if (!isBrowser()) return;
  document.cookie =
    `${COOKIE_KEY}=${encodeURIComponent(token)}; path=/; max-age=${COOKIE_MAX_AGE}; SameSite=Lax`;
}

function clearCookie(): void {
  if (!isBrowser()) return;
  document.cookie = `${COOKIE_KEY}=; path=/; max-age=0; SameSite=Lax`;
}

/** localStorage first, shared cookie as fallback. */
export function readAuthToken(): string | null {
  if (!isBrowser()) return null;
  try {
    return localStorage.getItem(TOKEN_KEY) ?? readCookie();
  } catch {
    return readCookie();
  }
}

/** localStorage only (per-app session shape lives next to it). */
export function readLocalAuthToken(): string | null {
  if (!isBrowser()) return null;
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function writeAuthToken(token: string): void {
  if (!isBrowser()) return;
  try {
    localStorage.setItem(TOKEN_KEY, token);
  } catch {
    // private mode etc. — cookie still shared
  }
  writeCookie(token);
}

export function clearAuthToken(): void {
  if (!isBrowser()) return;
  try {
    localStorage.removeItem(TOKEN_KEY);
  } catch {
    // ignore
  }
  clearCookie();
}
