"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

const SLIDES = [
  {
    eyebrow: "岐黄问道 · 学无止境",
    title: "系统学中医，",
    accent: "从这里开始",
    desc: "基础理论、诊断、中药、方剂、针灸——名师带教的完整学习路径，陪你从入门到临床。",
    cta: { href: "/#courses", label: "浏览课程" },
  },
  {
    eyebrow: "经典筑基",
    title: "读懂《黄帝内经》，",
    accent: "辨证有据",
    desc: "阴阳五行、藏象经络，化繁为简的经典导读课，配课后习题与学习进度跟踪。",
    cta: { href: "/#path", label: "查看学习路径" },
  },
  {
    eyebrow: "名师讲授",
    title: "跟着临床大家，",
    accent: "学以致用",
    desc: "每一门课都由一线教师打磨：章节清晰、课时精炼，免费试看先行。",
    cta: { href: "/#teachers", label: "认识讲师" },
  },
];

export default function HeroBanner() {
  const [index, setIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setIndex((i) => (i + 1) % SLIDES.length);
    }, 6000);
    return () => clearInterval(timer);
  }, []);

  const slide = SLIDES[index];

  return (
    <section className="relative overflow-hidden bg-ink-900 text-rice-50">
      {/* 背景纹理：同心圆 + 竖排装饰字 */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-20"
        style={{
          backgroundImage:
            "radial-gradient(circle at 85% 20%, rgba(184,58,46,0.55) 0, transparent 42%), radial-gradient(circle at 10% 90%, rgba(90,125,101,0.5) 0, transparent 40%)",
        }}
      />
      <div
        aria-hidden
        className="pointer-events-none absolute right-6 top-1/2 hidden -translate-y-1/2 select-none font-song text-[11rem] leading-none text-white/5 lg:block"
        style={{ writingMode: "vertical-rl" }}
      >
        岐黄之术
      </div>

      <div className="relative mx-auto flex w-full max-w-6xl flex-col gap-8 px-4 py-16 sm:px-6 md:py-24">
        <div key={index} className="hero-enter max-w-2xl">
          <p className="text-xs font-semibold uppercase tracking-[0.3em] text-rice-200">
            {slide.eyebrow}
          </p>
          <h1 className="mt-4 font-song text-4xl font-bold leading-tight md:text-6xl">
            {slide.title}
            <span className="text-cinnabar-100">{slide.accent}</span>
          </h1>
          <p className="mt-5 max-w-xl leading-7 text-rice-100/80">{slide.desc}</p>
          <div className="mt-8 flex flex-wrap gap-3">
            <Link
              href={slide.cta.href}
              className="rounded-lg bg-cinnabar-500 px-6 py-3 text-sm font-medium text-white transition hover:bg-cinnabar-600"
            >
              {slide.cta.label}
            </Link>
            <Link
              href="/login"
              className="rounded-lg border border-rice-100/30 px-6 py-3 text-sm font-medium text-rice-50 transition hover:border-rice-100/60 hover:bg-white/5"
            >
              免费注册学习
            </Link>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {SLIDES.map((s, i) => (
            <button
              key={s.title}
              aria-label={`切换到第 ${i + 1} 张`}
              onClick={() => setIndex(i)}
              className={`h-1.5 rounded-full transition-all ${
                i === index ? "w-8 bg-cinnabar-500" : "w-3 bg-white/25 hover:bg-white/50"
              }`}
            />
          ))}
        </div>
      </div>
    </section>
  );
}
