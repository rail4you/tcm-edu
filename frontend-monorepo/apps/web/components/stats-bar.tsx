export interface SiteStats {
  courseCount: number;
  studentCount: number;
  teacherCount: number;
  lessonCount: number;
}

export default function StatsBar({ stats }: { stats: SiteStats }) {
  const items = [
    { value: stats.courseCount, label: "门精品课程" },
    { value: stats.studentCount, label: "人次在学" },
    { value: stats.teacherCount, label: "位授课讲师" },
    { value: stats.lessonCount, label: "个精讲课时" },
  ];
  return (
    <div className="grid grid-cols-2 gap-px overflow-hidden rounded-2xl border border-rice-200 bg-rice-200 md:grid-cols-4">
      {items.map((it) => (
        <div key={it.label} className="flex flex-col items-center gap-1 bg-white px-4 py-6">
          <span className="font-song text-3xl font-bold text-cinnabar-600">
            {it.value.toLocaleString("zh-CN")}
          </span>
          <span className="text-sm text-ink-600">{it.label}</span>
        </div>
      ))}
    </div>
  );
}
