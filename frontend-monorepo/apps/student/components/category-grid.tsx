import Link from "next/link";

export interface CategoryItem {
  id: string;
  name: string;
  slug?: string | null;
  icon?: string | null;
}

const FALLBACK_ICONS = ["本", "诊", "药", "方", "针", "典"];

/** seed 里的 icon 存的是 antd 图标名，首页统一映射为单字印章 */
const ICON_CHAR: Record<string, string> = {
  book: "本",
  experiment: "药",
  profile: "方",
  thunderbolt: "针",
  heart: "心",
  read: "读",
  medicine: "医",
  diagnosis: "诊",
};

function iconChar(c: CategoryItem, i: number): string {
  if (c.icon) {
    if (ICON_CHAR[c.icon]) return ICON_CHAR[c.icon];
    // 已是单字则直接用
    if ([...c.icon].length === 1) return c.icon;
  }
  return c.name.slice(0, 1) || FALLBACK_ICONS[i % FALLBACK_ICONS.length];
}

export default function CategoryGrid({ categories }: { categories: CategoryItem[] }) {
  if (categories.length === 0) return null;
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
      {categories.map((c, i) => (
        <Link
          key={c.id}
          href="/#courses"
          className="group flex flex-col items-center gap-2 rounded-2xl border border-rice-200 bg-white px-3 py-6 text-center shadow-sm transition hover:-translate-y-0.5 hover:border-cinnabar-500 hover:shadow-md"
        >
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-rice-100 font-song text-xl text-cinnabar-600 transition group-hover:bg-cinnabar-500 group-hover:text-white">
            {iconChar(c, i)}
          </span>
          <span className="text-sm font-medium text-ink-900">{c.name}</span>
        </Link>
      ))}
    </div>
  );
}
