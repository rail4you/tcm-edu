import Link from "next/link";

const STEPS = [
  {
    no: "壹",
    title: "经典筑基",
    desc: "中医基础理论、中医诊断学：建立阴阳五行与辨证思维。",
  },
  {
    no: "贰",
    title: "中药方剂",
    desc: "常用中药性味归经、经典方剂配伍，理论联系临床。",
  },
  {
    no: "叁",
    title: "经络针灸",
    desc: "经络腧穴总论与针灸推拿入门，手法与取穴并重。",
  },
  {
    no: "肆",
    title: "临床精进",
    desc: "跟师临证思路、各科专病精讲，学以致用。",
  },
];

export default function LearningPath() {
  return (
    <div className="relative grid gap-4 md:grid-cols-4">
      {STEPS.map((s, i) => (
        <div
          key={s.no}
          className="relative rounded-2xl border border-rice-200 bg-white p-6 shadow-sm"
        >
          <span className="font-song text-4xl font-bold text-rice-200">{s.no}</span>
          <h3 className="mt-3 font-song text-lg font-semibold text-ink-900">{s.title}</h3>
          <p className="mt-2 text-sm leading-6 text-ink-600">{s.desc}</p>
          {i < STEPS.length - 1 && (
            <span
              aria-hidden
              className="absolute -right-3 top-1/2 hidden h-6 w-6 -translate-y-1/2 items-center justify-center rounded-full bg-cinnabar-500 text-xs text-white md:flex"
            >
              →
            </span>
          )}
        </div>
      ))}
    </div>
  );
}

export function LearningPathCta() {
  return (
    <div className="mt-6 text-center">
      <Link
        href="/#courses"
        className="inline-block rounded-lg border border-cinnabar-500 px-6 py-2.5 text-sm font-medium text-cinnabar-600 transition hover:bg-cinnabar-500 hover:text-white"
      >
        按路径选课 →
      </Link>
    </div>
  );
}
