"use client";

import { useCallback, useEffect, useState } from "react";
import {
  Button,
  Card,
  Form,
  Input,
  List,
  Select,
  Space,
  Spin,
  Switch,
  Tag,
  Typography,
  message
} from "antd";
import { KeyOutlined, SaveOutlined } from "@ant-design/icons";

import {
  listApiKeyConfigs,
  setApiKeyConfig,
  type AshRpcError
} from "@tcm-edu/rpc-client";
import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

const { Title, Paragraph, Text } = Typography;

const PROVIDERS = [
  { value: "qwen", label: "通义千问 (Qwen)" },
  { value: "dashscope", label: "DashScope" },
  { value: "deepseek", label: "DeepSeek" }
];

function errMsg(errors: AshRpcError[] | undefined): string {
  const first = errors?.[0];
  if (!first) return "保存失败";
  return first.message ?? "保存失败";
}

export default function AdminAIKeysPage() {
  useRequireAuth({ allow: ["super_admin", "tenant_admin"] });
  const { session } = useAuth();
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [keys, setKeys] = useState<{ provider?: string; model?: string; isActive?: boolean }[]>([]);

  const tenant = session?.tenant;

  const load = useCallback(async () => {
    if (!tenant) return;
    setLoading(true);
    try {
      const res = await listApiKeyConfigs({
        fields: ["provider", "model", "isActive"],
        tenant
      });
      if (res.success) {
        setKeys((res.data as typeof keys) ?? []);
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setLoading(false);
    }
  }, [tenant]);

  useEffect(() => {
    load();
  }, [load]);

  async function onSave() {
    const values = await form.validateFields();
    setSaving(true);
    try {
      const res = await setApiKeyConfig({
        fields: ["provider", "isActive"],
        tenant: tenant!,
        input: {
          provider: values.provider,
          apiKey: values.apiKey,
          baseUrl: values.baseUrl || undefined,
          model: values.model || undefined,
          isActive: values.isActive ?? true
        }
      });
      if (res.success) {
        message.success("Key 已保存（运行时生效，无需重启）");
        form.resetFields();
        load();
      } else {
        message.error(errMsg(res.errors));
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto space-y-4">
      <Title level={3}>
        <KeyOutlined /> AI Key 管理
      </Title>
      <Paragraph type="secondary">
        沿用 kg-edu 方案：key 存数据库（<Text code>ApiKeyConfig</Text>），
        起效即时，无需重启服务。密钥不对外回传明文。
      </Paragraph>

      <Card title="已配置的 Provider">
        <Spin spinning={loading}>
          {keys.length === 0 ? (
            <Text type="secondary">暂无配置，请用下方表单设置</Text>
          ) : (
            <List
              dataSource={keys}
              renderItem={(k) => (
                <List.Item>
                  <Space>
                    <Tag color="green">{k.provider}</Tag>
                    <Text code>{k.model ?? "默认模型"}</Text>
                    {k.isActive ? <Tag color="blue">启用</Tag> : <Tag color="red">停用</Tag>}
                  </Space>
                </List.Item>
              )}
            />
          )}
        </Spin>
      </Card>

      <Card title="设置 / 更新 Key">
        <Form
          form={form}
          layout="vertical"
          onFinish={onSave}
          initialValues={{ provider: "qwen", isActive: true }}
        >
          <Form.Item name="provider" label="Provider" rules={[{ required: true }]}>
            <Select options={PROVIDERS} />
          </Form.Item>
          <Form.Item
            name="apiKey"
            label="API Key"
            rules={[{ required: true, message: "请输入 API Key" }]}
          >
            <Input.Password placeholder="sk-...（DashScope / DeepSeek）" />
          </Form.Item>
          <Form.Item name="baseUrl" label="Base URL（可选）">
            <Input placeholder="https://dashscope.aliyuncs.com/compatible-mode/v1" />
          </Form.Item>
          <Form.Item name="model" label="默认模型（可选）">
            <Input placeholder="如 qwen-flash / qwen3-vl-flash / deepseek-chat" />
          </Form.Item>
          <Form.Item name="isActive" label="启用" valuePropName="checked">
            <Switch />
          </Form.Item>
          <Form.Item>
            <Button type="primary" htmlType="submit" loading={saving} icon={<SaveOutlined />}>
              保存
            </Button>
          </Form.Item>
        </Form>
      </Card>
    </div>
  );
}