"use client";

/**
 * 管理端 layout：超管 + 租户管理员共享。
 *
 * - AntdRegistry: SSR 样式提取（@ant-design/nextjs-registry）
 * - ConfigProvider: 中文 + 品牌色 cinnabar-500
 * - ProLayout: 侧边栏菜单（按 role 过滤）
 * - useRequireAuth({ allow: ["super_admin", "tenant_admin"] }): 未登录跳 /login
 *
 * 注意：Antd 用 CSS-in-JS，与 Tailwind preflight 不冲突；
 * AntdRegistry 必须在 ConfigProvider 外层才能正确收集样式。
 */

import { useMemo } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Avatar, Dropdown, Spin, type MenuProps } from "antd";
import { LogoutOutlined, UserOutlined } from "@ant-design/icons";
import { ProLayout } from "@ant-design/pro-components";
import { AntdRegistry } from "@ant-design/nextjs-registry";
import { ConfigProvider } from "antd";
import zhCN from "antd/locale/zh_CN";
import "@ant-design/v5-patch-for-react-19";

import { useAuth } from "@/lib/auth/context";
import { useRequireAuth } from "@/lib/auth/guard";
import type { Role } from "@/lib/auth/types";

const MENU_BY_ROLE: Record<"super_admin" | "tenant_admin", { path: string; name: string }[]> = {
  super_admin: [
    { path: "/admin", name: "工作台" },
    { path: "/admin/tenants", name: "租户管理" },
    { path: "/admin/users", name: "用户管理" },
  ],
  tenant_admin: [
    { path: "/admin", name: "工作台" },
    { path: "/admin/users", name: "用户管理" },
  ],
};

function isAdminRole(r: Role): r is "super_admin" | "tenant_admin" {
  return r === "super_admin" || r === "tenant_admin";
}

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, signOut } = useAuth();
  const { ready } = useRequireAuth({ allow: ["super_admin", "tenant_admin"] });

  const menuItems = useMemo(() => {
    if (!session || !isAdminRole(session.role)) return [];
    return MENU_BY_ROLE[session.role];
  }, [session]);

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

  if (!ready || !session || !isAdminRole(session.role)) {
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
          title="中医教学 · 管理端"
          logo={false}
          layout="mix"
          location={{ pathname }}
          route={{
            routes: menuItems.map((m) => ({ path: m.path, name: m.name })),
          }}
          menuItemRender={(item, dom) => <Link href={item.path ?? "/admin"}>{dom}</Link>}
          avatarProps={{
            src: undefined,
            icon: <UserOutlined />,
            title: session.email,
            render: (_props, dom) => (
              <Dropdown menu={{ items: avatarMenu }} placement="bottomRight">
                <span style={{ cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 8 }}>
                  <Avatar icon={<UserOutlined />} />
                  <span>{session.role === "super_admin" ? "超级管理员" : "租户管理员"}</span>
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