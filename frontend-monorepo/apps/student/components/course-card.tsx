import Link from "next/link";
import { useAuth } from "@/app/auth-context";

export interface CourseItem {
  id: string;
  title: string;
  subtitle?: string | null;
  coverImageUrl?: string | null;
  level?: string | null;
  priceCents?: number | null;
  lessonCount?: number | null;
  studentCount?: number | null;
}

const LEVEL_LABEL: Record<string, string> = {
  beginner: "初级",
  intermediate: "中级",
  advanced: "高级",
};

export function formatPrice(priceCents?: number | null): string {
  if (priceCents == null || priceCents === 0) return "免费";
  return `¥${(priceCents / 100).toFixed(2)}`;
}

export default function CourseCard({ course }: { course: CourseItem }) {
  const { isAuthenticated } = useAuth();

  return (
    <div className="group flex flex-col overflow-hidden rounded-2xl border border-rice-200 bg-white shadow-sm transition hover:-translate-y-1 hover:shadow-lg">
      <Link href={isAuthenticated ? `/course?id=${course.id}` : "/login"} className="block">
        <div className="relative aspect-[16/9] overflow-hidden bg-rice-100">
          {course.coverImageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={course.coverImageUrl}
              alt={course.title}
              loading="lazy"
              className="h-full w-full object-cover transition duration-300 group-hover:scale-105"
            />
          ) : (
            <div className="flex h-full w-full flex-col items-center justify-center gap-1 bg-gradient-to-br from-rice-100 via-rice-50 to-bamboo-100">
              <span className="font-song text-4xl text-cinnabar-500/70">
                {course.title.slice(0, 1)}
              </span>
              <span className="px-4 text-center font-song text-xs text-ink-400">
                {course.title}
              </span>
            </div>
          )}
          <span className="absolute left-3 top-3 rounded-full bg-ink-900/80 px-2.5 py-1 text-xs text-white">
            {LEVEL_LABEL[course.level ?? ""] ?? "全部水平"}
          </span>
          {(course.priceCents == null || course.priceCents === 0) && (
            <span className="absolute right-3 top-3 rounded-full bg-bamboo-500 px-2.5 py-1 text-xs font-medium text-white">
              免费
            </span>
          )}
        </div>
      </Link>

      <div className="flex flex-1 flex-col gap-2 p-4">
        <Link href={isAuthenticated ? `/course?id=${course.id}` : "/login"}>
          <h3 className="font-song font-semibold leading-6 text-ink-900 transition group-hover:text-cinnabar-600">
            {course.title}
          </h3>
        </Link>
        {course.subtitle && (
          <p className="line-clamp-2 text-sm leading-5 text-ink-600">{course.subtitle}</p>
        )}
        <div className="mt-auto flex items-center justify-between pt-2 text-xs text-ink-400">
          <span>{course.lessonCount ?? 0} 课时</span>
          <span>{course.studentCount ?? 0} 人在学</span>
          <span className="text-sm font-semibold text-cinnabar-600">
            {formatPrice(course.priceCents)}
          </span>
        </div>
      </div>
    </div>
  );
}
