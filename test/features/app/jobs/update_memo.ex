defmodule HologramFeatureTests.Jobs.UpdateMemo do
  use Hologram.Job, max_attempts: 1
  use Hologram.DB

  alias HologramFeatureTests.Entities.Memo

  # A plain id rather than a relationship, so other tests can truncate the memo table alone.
  attribute :memo_id, :id

  allow :create
  allow :read, when: actor_id == user_id()

  # Claims no trust. Memo has no rule covering its body, so the update is refused unless the job
  # runs as the server.
  @impl Hologram.Job
  def run(%{memo_id: memo_id}) do
    DB.update!(Memo, memo_id, body: "changed_by_job")
  end
end
