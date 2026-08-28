defmodule HologramFeatureTests.Components.Mutations.Jobs do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Jobs.RestockItem

  # The jobs reach this list through the ordinary read path - a registered query filled by the sync
  # stream - so a job the worker moved to done shows here without the page being fetched again.
  prop :jobs, [RestockItem], from_query: &jobs_query/0

  def template do
    ~HOLO"""
    <p>
      Jobs: <strong id="jobs"><code>{Enum.map_join(@jobs, ",", &"#{&1.amount}:#{&1.status}")}</code></strong>
    </p>
    """
  end

  defp jobs_query do
    order_by(RestockItem, :amount)
  end
end
