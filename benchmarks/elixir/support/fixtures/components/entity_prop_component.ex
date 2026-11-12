# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Benchmarks.Fixtures.Components.EntityPropComponent do
  @moduledoc false

  use Hologram.Component
  use Hologram.DB

  alias Hologram.Benchmarks.Fixtures.Entity1

  prop :entity, Entity1

  derived :entities, [Entity1], fn entity -> filter(entity.type, position >= 1) end

  def template do
    ~HOLO""
  end
end
