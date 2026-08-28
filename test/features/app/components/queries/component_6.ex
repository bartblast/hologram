defmodule HologramFeatureTests.Components.Queries.Component6 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Review

  prop :entity_type, :atom
  prop :rows, [Review], from_query: &rows_query/1

  def template do
    ~HOLO"""
    <p>
      Dynamic entity: <strong id="dynamic_entity"><code>{Enum.map_join(@rows, ",", & &1.body)}</code></strong>
    </p>
    """
  end

  # The entity type itself arrives at run time. The build forks over every type of the build and
  # keeps the ones this query admits - here only Review declares a rating.
  defp rows_query(entity_type) do
    filter(entity_type, rating: 5)
  end
end
