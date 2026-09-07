"use client";

import { useMemo } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Avatar, Dropdown, Spin, type MenuProps } from "antd";
import { LogoutOutlined, UserOutlined } from "@ant-design/icons";
import { ProLayout } from "@ant-design/pro-components";
import { useAuth, useRequireAuth, type AdminRole } from "@/lib/auth";

const MENU_BY_ROLE: Record<AdminRole, { path: string; name: string }[]> = {
  super_admin: [
    { path: "/", name: "工作台" },
    { path: "/tenants", name: "租户管理" },
    { path: "/users", name: "用户管理" },
  ],
  tenant_admin: [
    { path: "/", name: "工作台" },
    { path: "/users", name: "用户管理" },
  ],
};

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { session, logout } = useAuth();
  const { loading } = useRequireAuth();

  const menuItems = useMemo(
    () => (session ? MENU_BY_ROLE[session.role] : []),
    [session]
  );

  const avatarMenu: MenuProps["items"] = [
    {
      key: "logout",
      icon: <LogoutOutlined />,
      label: "退出登录",
      onClick: () => {
        logout();
        router.replace("/login");
      },
    },
  ];

  if (loading || !session) {
    return (
      <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Spin size="large" />
      </div>
    );
  }

  return (
    <ProLayout
      title="中医教学 · 管理端"
      logo={false}
      layout="mix"
      location={{ pathname }}
      route={{
        routes: menuItems.map((m) => ({ path: m.path, name: m.name })),
      }}
      menuItemRender={(item, dom) => <Link href={item.path ?? "/"}>{dom}</Link>}
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
  );
}
