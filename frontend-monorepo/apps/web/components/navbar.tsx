"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { useAuth } from "@/lib/auth/compat";

const LINKS = [
  { href: "/", label: "首页" },
  { href: "/courses", label: "课程" },
  { href: "/#teachers", label: "名师" },
  { href: "/#about", label: "关于" },
];

export default function Navbar() {
  const pathname = usePathname();
  const router = useRouter();
  const { isAuthenticated, user, logout } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        setMenuOpen(false);
      }
    }
    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, []);

  async function handleLogout() {
    await logout();
    setMenuOpen(false);
    router.push("/");
  }

  const displayName = user?.email?.split("@")[0] ?? "学员";

  return (
    <header className="sticky top-0 z-40 border-b border-rice-200 bg-rice-50/95 backdrop-blur">
      <div className="mx-auto flex h-16 w-full max-w-6xl items-center gap-6 px-4 sm:px-6">
        <Link href="/" className="flex items-center gap-2">
          <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-cinnabar-500 font-song text-lg text-white">
            岐
          </span>
          <span className="font-song text-lg font-semibold tracking-wide text-ink-900">
            中医教学
          </span>
        </Link>

        {/* 桌面导航 */}
        <nav className="hidden items-center gap-1 md:flex">
          {LINKS.map((l) => {
            const active = l.href === "/" ? pathname === "/" : l.href.startsWith("/#") ? false : pathname.startsWith(l.href);
            return (
              <Link
                key={l.href}
                href={l.href}
                className={`rounded-md px-3 py-2 text-sm transition ${
                  active
                    ? "font-medium text-cinnabar-600"
                    : "text-ink-600 hover:bg-rice-100 hover:text-ink-900"
                }`}
              >
                {l.label}
              </Link>
            );
          })}
        </nav>

        <div className="ml-auto flex items-center gap-2">
          {isAuthenticated ? (
            <div ref={menuRef} className="relative hidden md:block">
              <button
                onClick={() => setMenuOpen((v) => !v)}
                className="flex items-center gap-2 rounded-full border border-rice-200 bg-white py-1.5 pl-1.5 pr-3 text-sm transition hover:border-cinnabar-500"
              >
                <span className="flex h-7 w-7 items-center justify-center rounded-full bg-bamboo-500 text-xs font-medium text-white">
                  {displayName.slice(0, 1).toUpperCase()}
                </span>
                <span className="max-w-28 truncate text-ink-900">{displayName}</span>
              </button>
              {menuOpen && (
                <div className="absolute right-0 mt-2 w-44 overflow-hidden rounded-xl border border-rice-200 bg-white shadow-lg">
                  <Link
                    href="/my-learning"
                    onClick={() => setMenuOpen(false)}
                    className="block px-4 py-2.5 text-sm text-ink-900 transition hover:bg-rice-100"
                  >
                    我的学习
                  </Link>
                  <button
                    onClick={handleLogout}
                    className="block w-full px-4 py-2.5 text-left text-sm text-ink-600 transition hover:bg-rice-100"
                  >
                    退出登录
                  </button>
                </div>
              )}
            </div>
          ) : (
            <Link
              href="/login"
              className="hidden rounded-lg bg-cinnabar-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-cinnabar-600 md:block"
            >
              登录 / 注册
            </Link>
          )}

          {/* 移动端汉堡 */}
          <button
            onClick={() => setMobileOpen((v) => !v)}
            aria-label="菜单"
            className="rounded-md p-2 text-ink-600 transition hover:bg-rice-100 md:hidden"
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              {mobileOpen ? (
                <path d="M6 6l12 12M18 6L6 18" />
              ) : (
                <path d="M4 7h16M4 12h16M4 17h16" />
              )}
            </svg>
          </button>
        </div>
      </div>

      {/* 移动端抽屉 */}
      {mobileOpen && (
        <nav className="border-t border-rice-200 bg-rice-50 px-4 py-3 md:hidden">
          {LINKS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              onClick={() => setMobileOpen(false)}
              className="block rounded-md px-3 py-2.5 text-sm text-ink-900 transition hover:bg-rice-100"
            >
              {l.label}
            </Link>
          ))}
          {isAuthenticated ? (
            <>
              <Link
                href="/my-learning"
                onClick={() => setMobileOpen(false)}
                className="block rounded-md px-3 py-2.5 text-sm text-ink-900 transition hover:bg-rice-100"
              >
                我的学习
              </Link>
              <button
                onClick={() => {
                  handleLogout();
                  setMobileOpen(false);
                }}
                className="block w-full rounded-md px-3 py-2.5 text-left text-sm text-ink-600 transition hover:bg-rice-100"
              >
                退出登录
              </button>
            </>
          ) : (
            <Link
              href="/login"
              onClick={() => setMobileOpen(false)}
              className="mt-1 block rounded-lg bg-cinnabar-500 px-3 py-2.5 text-center text-sm font-medium text-white"
            >
              登录 / 注册
            </Link>
          )}
        </nav>
      )}
    </header>
  );
}
