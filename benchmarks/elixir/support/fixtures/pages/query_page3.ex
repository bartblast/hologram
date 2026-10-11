# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.QueryPage3 do
  @moduledoc false

  use Hologram.Page

  alias Hologram.Benchmarks.Fixtures.Components.EntityPropComponent
  alias Hologram.Benchmarks.Fixtures.Components.QueryPropComponent
  alias Hologram.Benchmarks.Fixtures.Entity1

  route "/query-page-3"

  layout Hologram.Benchmarks.Fixtures.Components.DefaultLayout

  def template do
    ~HOLO"""
    <EntityPropComponent cid="entity_prop" entity={%Entity1{name: "entity", position: 1}} />
    <QueryPropComponent cid="query_prop" min_position={1} />
    """
  end
end
