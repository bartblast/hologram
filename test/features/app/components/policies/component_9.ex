defmodule HologramFeatureTests.Components.Policies.Component9 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Milestone

  prop :milestones, [Milestone], from_query: &milestones_query/0

  def template do
    ~HOLO"""
    <p>
      Milestones: <strong id="milestones"><code>{Enum.map_join(@milestones, ",", & &1.title)}</code></strong>
    </p>
    """
  end

  defp milestones_query do
    sort(Milestone, title)
  end
end
