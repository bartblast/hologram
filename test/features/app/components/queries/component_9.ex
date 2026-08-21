defmodule HologramFeatureTests.Components.Queries.Component9 do
  use Hologram.Component
  use Hologram.Query

  alias HologramFeatureTests.Entities.Product

  prop :products, [Product], from_query: &products_query/0

  # No init/3, deliberately: the prop is rendered as it resolves. On the server that is the
  # query against Postgres, and on the client the same query against the client's own database -
  # which is what makes a change arriving on the stream reach this DOM without anyone asking.
  def template do
    ~HOLO"""
    <p>
      From m: <strong id="products_from_m"><code>{Enum.map_join(@products, ",", & &1.name)}</code></strong>
    </p>
    """
  end

  # The bound is a position in the list the ordering renders, so both executors have to place it
  # the same way - which is what the derived sort key is for.
  defp products_query do
    Product
    |> filter(name: {:>=, "m"})
    |> order_by(:name)
  end
end
