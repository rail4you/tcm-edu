import { Suspense } from "react";
import CourseDetail from "./detail-client";

export const metadata = {
  title: "课程详情 · 中医教学",
  description: "查看课程介绍、章节目录与讲师，登录后选课学习。",
};

export default function CoursePage() {
  return (
    <Suspense
      fallback={
        <main className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6">
          <div className="skeleton h-8 w-1/2 rounded" />
        </main>
      }
    >
      <CourseDetail />
    </Suspense>
  );
}
