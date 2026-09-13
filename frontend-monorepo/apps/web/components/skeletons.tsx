export function CourseCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-2xl border border-rice-200 bg-white">
      <div className="skeleton aspect-[16/9] w-full" />
      <div className="flex flex-col gap-2 p-4">
        <div className="skeleton h-5 w-3/4 rounded" />
        <div className="skeleton h-4 w-full rounded" />
        <div className="skeleton h-4 w-1/2 rounded" />
      </div>
    </div>
  );
}

export function CategorySkeleton() {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
      {Array.from({ length: 6 }).map((_, i) => (
        <div
          key={i}
          className="flex flex-col items-center gap-2 rounded-2xl border border-rice-200 bg-white px-3 py-6"
        >
          <div className="skeleton h-12 w-12 rounded-full" />
          <div className="skeleton h-4 w-16 rounded" />
        </div>
      ))}
    </div>
  );
}

export function TeacherSkeleton() {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {Array.from({ length: 4 }).map((_, i) => (
        <div
          key={i}
          className="flex flex-col items-center gap-3 rounded-2xl border border-rice-200 bg-white px-4 py-8"
        >
          <div className="skeleton h-20 w-20 rounded-full" />
          <div className="skeleton h-5 w-24 rounded" />
          <div className="skeleton h-4 w-32 rounded" />
        </div>
      ))}
    </div>
  );
}
