# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.QueryPropComponent do
  @moduledoc false

  use Hologram.Component
  use Hologram.DB

  alias Hologram.Benchmarks.Fixtures.Entity1

  prop :min_position, :integer

  derived :entities, [Entity1], fn min_position -> filter(Entity1, position >= ^min_position) end

  def template do
    ~HOLO""
  end
end
