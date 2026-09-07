import Link from "next/link";

export default function Footer() {
  return (
    <footer id="about" className="border-t border-rice-200 bg-ink-900 text-rice-100">
      <div className="mx-auto grid w-full max-w-6xl gap-8 px-4 py-12 sm:px-6 md:grid-cols-4">
        <div>
          <div className="flex items-center gap-2">
            <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-cinnabar-500 font-song text-lg text-white">
              岐
            </span>
            <span className="font-song text-lg font-semibold tracking-wide">中医教学</span>
          </div>
          <p className="mt-3 text-sm leading-6 text-rice-100/70">
            传承岐黄之术，弘扬中医文化。系统化课程、名师讲授、学练结合。
          </p>
        </div>
        <div>
          <h3 className="font-song text-sm font-semibold tracking-widest text-rice-200">学堂</h3>
          <ul className="mt-3 space-y-2 text-sm text-rice-100/70">
            <li><Link href="/#courses" className="transition hover:text-white">全部课程</Link></li>
            <li><Link href="/#teachers" className="transition hover:text-white">名师风采</Link></li>
            <li><Link href="/#path" className="transition hover:text-white">学习路径</Link></li>
          </ul>
        </div>
        <div>
          <h3 className="font-song text-sm font-semibold tracking-widest text-rice-200">学员</h3>
          <ul className="mt-3 space-y-2 text-sm text-rice-100/70">
            <li><Link href="/login" className="transition hover:text-white">登录 / 注册</Link></li>
            <li><Link href="/my-learning" className="transition hover:text-white">我的学习</Link></li>
          </ul>
        </div>
        <div>
          <h3 className="font-song text-sm font-semibold tracking-widest text-rice-200">关于</h3>
          <p className="mt-3 text-sm leading-6 text-rice-100/70">
            多机构入驻的中医在线教学平台：管理员、教师、学生分端协作。
          </p>
        </div>
      </div>
      <div className="border-t border-white/10">
        <div className="mx-auto w-full max-w-6xl px-4 py-4 text-xs text-rice-100/50 sm:px-6">
          © 2026 中医教学 TCM-Edu · 传承精华，守正创新
        </div>
      </div>
    </footer>
  );
}
