# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module38 do
  use Hologram.Component

  # The grant entity is an entity type like any other, so a page can reach the window the
  # permission check downloads through a query of its own.
  alias Hologram.Auth.RoleGrant

  derived :grants, [RoleGrant], fn -> RoleGrant end

  @impl Component
  def template do
    ~HOLO""
  end
end
