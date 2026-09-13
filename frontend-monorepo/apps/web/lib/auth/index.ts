/**
 * 统一 auth 入口（barrel）。
 *
 * 管理端 / 教师端代码推荐从这个路径导入：
 *   import { useAuth, useRequireAuth, ROLE_HOME } from "@/lib/auth";
 *
 * 学生端需要兼容旧 API 时：
 *   import { useAuth } from "@/lib/auth/compat";
 */

export { AuthProvider, useAuth, homePathFor } from "./context";
export { useRequireAuth } from "./guard";
export type { Role, Session, Permission } from "./types";
export { ROLE_HOME, roleForPath, allowedRolesForPath } from "./types";