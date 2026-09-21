defmodule TcmEdu.Chat.ChatTask do
  @moduledoc """
  Tracks a long-running background task that was kicked off from a chat tool call.

  Created by the chat controller when the `start_long_task` tool is invoked.
  Updated by `TcmEdu.Workers.LongTaskWorker` as the Oban job progresses.
  """

  use Ash.Resource,
    otp_app: :tcm_edu,
    domain: TcmEdu.ChatDomain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshTypescript.Resource],
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table("chat_tasks")
    repo(TcmEdu.Repo)
  end

  typescript do
    type_name("ChatTask")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :task_id, :string do
      allow_nil?(false)
      public?(true)
      description("Public UUID returned to the LLM/tool caller.")
    end

    attribute :user_id, :uuid do
      allow_nil?(false)
      public?(true)
    end

    attribute :session_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :agent_name, :string do
      allow_nil?(false)
      public?(true)
      default("chat_agent")
    end

    attribute :task_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :duration_ms, :integer do
      allow_nil?(false)
      public?(true)
      default(15_000)
    end

    attribute :status, :atom do
      allow_nil?(false)
      public?(true)
      constraints(one_of: [:pending, :running, :completed, :failed])
      default(:pending)
    end

    attribute :job_id, :integer do
      public?(true)
      description("Oban job id, set after Oban.insert/1 succeeds.")
    end

    attribute :result, :map do
      public?(true)
    end

    attribute :error_message, :string do
      public?(true)
    end

    create_timestamp(:inserted_at, public?: true)
    update_timestamp(:updated_at, public?: true)

    attribute :started_at, :utc_datetime do
      public?(true)
    end

    attribute :completed_at, :utc_datetime do
      public?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      primary?(true)

      accept([
        :task_id,
        :user_id,
        :session_id,
        :agent_name,
        :task_name,
        :duration_ms,
        :status,
        :job_id
      ])
    end

    update :mark_running do
      require_atomic?(false)
      accept([])
      change(set_attribute(:status, :running))
      change(set_attribute(:started_at, &DateTime.utc_now/0))
    end

    update :mark_completed do
      require_atomic?(false)
      accept([:result])
      change(set_attribute(:status, :completed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    update :mark_failed do
      require_atomic?(false)
      accept([:error_message])
      change(set_attribute(:status, :failed))
      change(set_attribute(:completed_at, &DateTime.utc_now/0))
    end

    read :active_for_user do
      argument(:user_id, :uuid, allow_nil?: false)

      filter(expr(user_id == ^arg(:user_id) and status in [:pending, :running]))
    end

    read :by_task_id do
      argument(:task_id, :string, allow_nil?: false)
      get?(true)
      filter(expr(task_id == ^arg(:task_id)))
    end
  end

  policies do
    # Authentication is enforced by the controller (we only have one user per
    # session). Internal worker writes bypass Ash by going through the Repo
    # directly via Ash changeset APIs.
    policy always() do
      authorize_if(always())
    end
  end
end
