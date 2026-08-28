defmodule HologramFeatureTests.Jobs.RestockItem do
  use Hologram.Job
  use Hologram.DB

  alias HologramFeatureTests.Entities.Item

  attribute :amount, :integer

  relationship :item, Item

  allow :create
  allow :read, actor_id: user_id()

  # Runs as the user who created the job: the item is read through their read policies and moved
  # under their update policies, both of which Item grants to anyone. A move below the item's
  # declared minimum is refused by the write, which is what the failing scenario rests on - the
  # refusal raises out of here and lands on this job's own row.
  @impl Hologram.Job
  def run(%{amount: amount, item_id: item_id}) do
    Item
    |> DB.read(item_id)
    |> increment(:stock, amount)
    |> DB.update!()
  end
end
