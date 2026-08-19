# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module26 do
  use Hologram.Component

  alias Hologram.Auth.RoleGrant

  # The grant entity is an entity type like any other, so a page can reach the window the
  # permission check downloads through a query of its own.
  prop :grants, [RoleGrant], from_query: fn -> RoleGrant end

  @impl Component
  def template do
    ~HOLO""
  end
end
