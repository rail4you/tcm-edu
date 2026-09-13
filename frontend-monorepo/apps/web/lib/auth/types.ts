/**
 * 统一 auth 类型定义。
 *
 * 后端 /api/auth/me 返回的 role 是字符串（来自 User.role atom 或 SuperAdmin），
 * 这里统一收敛为四种：super_admin / tenant_admin / teacher / student。
 */

/** 后端支持的角色（与 lib/tcm_edu/accounts/user.ex 的 role 约束对齐） */
export type Role = "super_admin" | "tenant_admin" | "teacher" | "student";

/** 登录后的会话状态 */
export interface Session {
  /** Bearer token */
  token: string;
  /** 收敛后的角色 */
  role: Role;
  /** 租户 schema 名（超管是 "public"） */
  tenant: string;
  /** 用户 UUID */
  userId: string;
  /** 显示名（邮箱或姓名） */
  name: string;
  /** 登录邮箱 */
  email: string;
}

/** 旧 demo 用权限位（学生端 posts 页面还在用） */
export type Permission = "post:create" | "post:update" | "post:delete";

/** 路由重定向表：登录成功后跳到哪儿 */
export const ROLE_HOME: Record<Role, string> = {
  super_admin: "/admin",
  tenant_admin: "/admin",
  teacher: "/teacher",
  student: "/",
};

/** 判断路径前缀属于哪个角色的门户 */
export function roleForPath(pathname: string): Role | null {
  if (pathname === "/" || pathname.startsWith("/courses") || pathname.startsWith("/course") ||
      pathname.startsWith("/learn") || pathname.startsWith("/my-learning") ||
      pathname.startsWith("/posts") || pathname.startsWith("/chat")) {
    return "student";
  }
  if (pathname.startsWith("/admin")) return "super_admin"; // 也允许 tenant_admin
  if (pathname.startsWith("/teacher")) return "teacher"; // 也允许 tenant_admin
  return null;
}

/** 该路径允许的角色集合 */
export function allowedRolesForPath(pathname: string): Role[] | null {
  if (pathname.startsWith("/admin")) return ["super_admin", "tenant_admin"];
  if (pathname.startsWith("/teacher")) return ["teacher", "tenant_admin"];
  // 学生端公开页面，无需登录
  return null;
}