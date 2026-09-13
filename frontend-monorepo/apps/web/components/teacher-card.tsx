export interface TeacherItem {
  id: string;
  name?: string | null;
  avatarUrl?: string | null;
  jobTitle?: string | null;
  school?: string | null;
  bio?: string | null;
}

export default function TeacherCard({ teacher }: { teacher: TeacherItem }) {
  const initial = (teacher.name ?? "师").slice(0, 1);
  return (
    <div className="flex flex-col items-center gap-3 rounded-2xl border border-rice-200 bg-white px-4 py-8 text-center shadow-sm transition hover:-translate-y-1 hover:shadow-lg">
      {teacher.avatarUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={teacher.avatarUrl}
          alt={teacher.name ?? "讲师"}
          loading="lazy"
          className="h-20 w-20 rounded-full border-2 border-rice-200 object-cover"
        />
      ) : (
        <span className="flex h-20 w-20 items-center justify-center rounded-full bg-bamboo-500 font-song text-3xl text-white">
          {initial}
        </span>
      )}
      <div>
        <h3 className="font-song text-lg font-semibold text-ink-900">
          {teacher.name || "特邀讲师"}
        </h3>
        {(teacher.jobTitle || teacher.school) && (
          <p className="mt-1 text-xs text-ink-400">
            {[teacher.jobTitle, teacher.school].filter(Boolean).join(" · ")}
          </p>
        )}
      </div>
      {teacher.bio && (
        <p className="line-clamp-3 text-sm leading-6 text-ink-600">{teacher.bio}</p>
      )}
    </div>
  );
}
