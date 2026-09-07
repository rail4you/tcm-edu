/**
 * AshTypescript lifecycle hooks for RPC actions.
 *
 * - `beforeRequest`: Attaches the Bearer token from localStorage to
 *   every RPC request so the backend can identify the authenticated user.
 * - `afterRequest`: Detects 401 responses and clears stale tokens.
 */

import { clearAuthToken, readAuthToken } from "./sharedAuth";

export interface ActionHookContext {
  /** Optional correlation ID for request tracing */
  correlationId?: string;
}

/**
 * Called before every RPC HTTP request.
 * Injects the stored Bearer token into the Authorization header.
 * Falls back to the shared cross-app cookie (see sharedAuth.ts).
 */
export function beforeRequest(
  _actionName: string,
  config: Record<string, any>
): Record<string, any> {
  const token = readAuthToken();

  if (token) {
    return {
      ...config,
      headers: {
        ...(config.headers as Record<string, string> | undefined),
        Authorization: `Bearer ${token}`,
      },
    };
  }

  return config;
}

/**
 * Called after every RPC HTTP request completes.
 * If we get a 401, the token is stale — clear it so the UI can
 * redirect to the login page.
 */
export function afterRequest(
  _actionName: string,
  response: Response,
  _result: unknown,
  _config: Record<string, any>
): void {
  if (response.status === 401 && typeof window !== "undefined") {
    clearAuthToken();
    // Dispatch a custom event so the auth context can react
    window.dispatchEvent(new Event("auth:logout"));
  }
}
