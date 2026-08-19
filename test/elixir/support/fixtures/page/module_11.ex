# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Page.Module11 do
  use Hologram.Page

  alias Hologram.Auth
  alias Hologram.Test.Fixtures.Entity.Module2

  route "/hologram-test-fixtures-page-module11"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    nothing checked here
    """
  end

  # Checked in a COMMAND handler, which runs on the server - nothing of this reaches a bundle,
  # so this page needs no grant rows on the client.
  @impl Page
  def command(:check, _params, server) do
    put_action(server, :done, allowed: Auth.can?(nil, :read, %Module2{}))
  end
end
