alias TcmEdu.Workers.LongTaskWorker
alias TcmEdu.Chat.ChatTask

# Pick an existing user_id straight from the DB (User has a strict read policy).
user_id =
  case TcmEdu.Repo.query!("SELECT id::text FROM users LIMIT 1", [], log: false).rows do
    [[id]] -> id
    [] -> raise "no users exist; register one via /api/auth first"
  end

IO.puts("=== Using user_id #{user_id} ===")

task_id = Ecto.UUID.generate()
task_name = "smoke-#{:rand.uniform(99_999)}"
session_id = "test-session-#{System.unique_integer([:positive])}"

{:ok, job} =
  LongTaskWorker.new(%{
    "task_id" => task_id,
    "user_id" => user_id,
    "session_id" => session_id,
    "agent_name" => "chat_agent",
    "task_name" => task_name,
    "duration_ms" => 2_000
  })
  |> Oban.insert()

IO.puts "Inserted Oban job id=#{job.id}, task_id=#{task_id}"
IO.puts "Sleeping 4s to let worker run (2s mock + admin)..."

Process.sleep(4_000)

# Inspect ChatTask row
case TcmEdu.Repo.query!(
       "SELECT task_id, status, started_at, completed_at, result::text FROM chat_tasks WHERE task_id = $1",
       [task_id],
       log: false
     ).rows do
  [[tid, status, started_at, completed_at, result]] ->
    IO.puts("=== ChatTask row ===")
    IO.inspect(%{task_id: tid, status: status, started_at: started_at, completed_at: completed_at, result: result}, label: "task")

  [] ->
    IO.puts "No ChatTask row found for #{task_id}"
end

# Inspect Oban job state
job2 = Oban.Repo.get!(Oban.Job, job.id)
IO.puts "=== Final Oban job state ==="
IO.inspect(job2.state, label: "state")
IO.inspect(job2.completed_at, label: "completed_at")

# Inspect chat message
require Ash.Query

msgs =
  TcmEdu.Chat.ChatMessage
  |> Ash.Query.filter(session_id == ^session_id)
  |> Ash.Query.sort(inserted_at: :asc)
  |> Ash.read!()

IO.puts "=== Chat messages in this session ==="
for m <- msgs, do: IO.inspect(m, label: "msg")
