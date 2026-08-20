defmodule HologramFeatureTests.Components.Queries.Component5 do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Entities.Review

  prop :sort_field, :atom
  prop :reviews, [Review], from_query: &reviews_query/1

  def template do
    ~HOLO"""
    <p>
      Dynamic order: <strong id="dynamic_order"><code>{Enum.map_join(@reviews, ",", & &1.body)}</code></strong>
    </p>
    """
  end

  # The column to order by is not known until the component is given one.
  defp reviews_query(sort_field) do
    order_by(Review, sort_field)
  end
end
