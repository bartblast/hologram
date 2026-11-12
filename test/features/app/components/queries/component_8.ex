defmodule HologramFeatureTests.Components.Queries.Component8 do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Entities.Review

  prop :sort_field, :atom

  derived :reviews, [Review], fn sort_field -> reviews_query(sort_field) end

  def template do
    ~HOLO"""
    <p>
      Dynamic string order: <strong id="dynamic_string_order"><code>{Enum.map_join(@reviews, ",", & &1.body)}</code></strong>
    </p>
    """
  end

  # The column to order by is not known until the component is given one.
  defp reviews_query(sort_field) do
    sort(Review, ^sort_field)
  end
end
