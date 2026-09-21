"use client";

import { useCallback, useEffect, useState } from "react";
import { Card, Col, Row, Space, Spin, Statistic, Tag, Typography, message } from "antd";
import {
  DashboardOutlined,
  DatabaseOutlined,
  NotificationOutlined,
  RobotOutlined,
  ApiOutlined
} from "@ant-design/icons";

import {
  listApiKeyConfigs,
  listQuestionBanks,
  listNotifications,
  type AshRpcError
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

const { Title, Paragraph, Text } = Typography;

function errMsg(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "加载失败";
  return first.message ?? "加载失败";
}

const PROVIDER_LABEL: Record<string, { label: string; color: string } | undefined> = {
  qwen: { label: "通义千问 (Qwen)", color: "green" },
  dashscope: { label: "DashScope", color: "cyan" },
  deepseek: { label: "DeepSeek", color: "blue" }
};

export default function AdminAIDashboardPage() {
  useRequireAuth({ allow: ["super_admin", "tenant_admin"] });
  const { session } = useAuth();
  const [loading, setLoading] = useState(true);
  const [keys, setKeys] = useState<{ provider?: string; model?: string; baseUrl?: string; isActive?: boolean }[]>([]);
  const [bankCount, setBankCount] = useState(0);
  const [notifCount, setNotifCount] = useState(0);

  const load = useCallback(async () => {
    if (!session?.tenant) return;
    setLoading(true);
    try {
      const [k, b, n] = await Promise.all([
        listApiKeyConfigs({ fields: ["provider", "model", "isActive", "baseUrl"], tenant: session.tenant }),
        listQuestionBanks({ fields: ["id"], tenant: session.tenant, page: { limit: 1 } }),
        listNotifications({ fields: ["id"], tenant: session.tenant, page: { limit: 1 } })
      ]);

      if (k.success) setKeys((k.data as typeof keys) ?? []);
      if (b.success) setBankCount(((b as { data?: unknown[] }).data as unknown[])?.length ?? 0);
      if (n.success) setNotifCount(((n as { data?: unknown[] }).data as unknown[])?.length ?? 0);
    } catch (e) {
      message.error(errMsg(undefined));
    } finally {
      setLoading(false);
    }
  }, [session?.tenant]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="p-6 max-w-6xl mx-auto space-y-4">
      <Title level={3}>
        <DashboardOutlined /> AI 驾驶舱
      </Title>
      <Paragraph type="secondary">
        监控杏宁树 AI 能力配置与题库/通知数据（参考资料：qwen-flash · wanx2.1-t2i-turbo）。
      </Paragraph>

      <Spin spinning={loading}>
        <Row gutter={16}>
          <Col span={8}>
            <Card>
              <Statistic title="已配置 AI Provider" value={keys.length} prefix={<RobotOutlined />} />
            </Card>
          </Col>
          <Col span={8}>
            <Card>
              <Statistic title="题库数量" value={bankCount} prefix={<DatabaseOutlined />} />
            </Card>
          </Col>
          <Col span={8}>
            <Card>
              <Statistic title="通知条数（近页）" value={notifCount} prefix={<NotificationOutlined />} />
            </Card>
          </Col>
        </Row>

        <Card title={<><ApiOutlined /> AI Key 配置状态</>} className="mt-4">
          {keys.length === 0 ? (
            <Text type="secondary">尚未配置 AI Key（可在「AI Key 管理」页设置）</Text>
          ) : (
            keys.map((k) => {
              const meta = PROVIDER_LABEL[k.provider ?? ""] ?? { label: k.provider, color: "default" };
              return (
                <div key={k.provider} className="flex items-center justify-between border-b py-2 last:border-0">
                  <Space>
                    <Tag color={meta.color}>{meta.label}</Tag>
                    <Text code>{k.model ?? "默认模型"}</Text>
                  </Space>
                  {k.isActive ? <Tag color="green">启用</Tag> : <Tag color="red">停用</Tag>}
                </div>
              );
            })
          )}
        </Card>
      </Spin>
    </div>
  );
}