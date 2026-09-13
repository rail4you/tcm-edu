"use client";

/**
 * 教师端 layout：教师 + 租户管理员共享。
 *
 * - AntdRegistry: SSR 样式提取
 * - ConfigProvider: 中文 + 品牌色 cinnabar-500（与管理端一致）
 * - ProLayout: 侧边栏菜单
 * - useRequireAuth({ allow: ["teacher", "tenant_admin"] }): 未登录跳 /login
 */

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Avatar, Dropdown, Spin, Tag, type MenuProps } from "antd";
import { LogoutOutlined, UserOutlined } from "@ant-design/icons";
import { ProLayout } from "@ant-design/pro-components";
import { AntdRegistry } from "@ant-design/nextjs-registry";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import "@ant-design/v5-patch-for-react-19";

import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";

const MENU = [
  { path: "/teacher", name: "工作台" },
  { path: "/teacher/courses", name: "我的课程" },
  { path: "/teacher/students", name: "我的学生" },
];

export default function TeacherLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, signOut } = useAuth();
  const { ready } = useRequireAuth({ allow: ["teacher", "tenant_admin"] });

  const avatarMenu: MenuProps["items"] = [
    {
      key: "logout",
      icon: <LogoutOutlined />,
      label: "退出登录",
      onClick: async () => {
        await signOut();
        router.replace("/login");
      },
    },
  ];

  if (!ready || !session) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Spin size="large" />
      </div>
    );
  }

  return (
    <AntdRegistry>
      <ConfigProvider
        locale={zhCN}
        theme={{
          token: {
            colorPrimary: "#b83a2e",
            borderRadius: 6,
          },
        }}
      >
        <ProLayout
          title="中医教学 · 教师端"
          logo={false}
          layout="mix"
          location={{ pathname }}
          route={{
            routes: MENU.map((m) => ({ path: m.path, name: m.name })),
          }}
          menuItemRender={(item, dom) => <Link href={item.path ?? "/teacher"}>{dom}</Link>}
          avatarProps={{
            src: undefined,
            icon: <UserOutlined />,
            title: session.email,
            render: (_props, dom) => (
              <Dropdown menu={{ items: avatarMenu }} placement="bottomRight">
                <span style={{ cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 8 }}>
                  <Avatar icon={<UserOutlined />} />
                  <span>{session.role === "tenant_admin" ? "机构管理员" : "教师"}</span>
                  <Tag color="blue">{session.tenant}</Tag>
                  {dom}
                </span>
              </Dropdown>
            ),
          }}
        >
          {children}
        </ProLayout>
      </ConfigProvider>
    </AntdRegistry>
  );
}