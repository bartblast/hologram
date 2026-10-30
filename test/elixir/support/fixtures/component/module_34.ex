# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module34 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8

  prop :entities, [PolicyModule8], from_query: fn -> sort(PolicyModule8, created_at) end

  @impl Component
  def template do
    ~HOLO""
  end
end
