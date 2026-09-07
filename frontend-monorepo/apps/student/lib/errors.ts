import type { AshRpcError } from "@tcm-edu/rpc-client";

/**
 * 后端 RPC 错误 → 中文友好文案。
 * - forbidden：权限不足（后端 policy 拒绝）
 * - network_error：网络问题
 * - invalid：取第一条业务校验信息
 */
export function friendlyError(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "操作失败，请稍后重试";
  if (first.type === "forbidden") return "您没有权限执行此操作";
  if (first.type === "network_error") return "网络错误，请检查连接后重试";
  if (first.type === "action_not_found") return "服务暂不可用，请稍后重试";
  return first.shortMessage || first.message || "操作失败，请稍后重试";
}
