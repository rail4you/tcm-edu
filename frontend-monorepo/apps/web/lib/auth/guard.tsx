"use client";

/**
 * 路由守卫：基于 session.role 判断是否允许访问。
 *
 * 用法：
 *   useRequireAuth({ allow: ["super_admin", "tenant_admin"] })  ← /admin/* layout 用
 *   useRequireAuth({ allow: ["teacher", "tenant_admin"] })       ← /teacher/* layout 用
 *
 * 未登录跳 /login；role 不符跳 ROLE_HOME[当前 role]（已登录但进错门户）。
 */

import { useEffect } from "react";
import { useRouter, usePathname } from "next/navigation";
import { useAuth } from "./context";
import { ROLE_HOME, type Role } from "./types";

interface RequireAuthOptions {
  /** 允许通过的角色集合；不传 = 仅要求登录 */
  allow?: Role[];
  /** 未登录时的重定向（默认 /login） */
  loginRedirect?: string;
}

export function useRequireAuth(opts: RequireAuthOptions = {}) {
  const { session, ready } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    if (!ready) return;
    if (!session) {
      const redirect = opts.loginRedirect ?? "/login";
      const target = pathname ? `${redirect}?next=${encodeURIComponent(pathname)}` : redirect;
      router.replace(target);
      return;
    }
    if (opts.allow && !opts.allow.includes(session.role)) {
      router.replace(ROLE_HOME[session.role]);
    }
  }, [ready, session, opts.allow, opts.loginRedirect, pathname, router]);

  return { session, ready };
}