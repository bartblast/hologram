# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module25 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module25"

  layout LayoutFixture

  middleware :deny

  def deny(server, _opts) do
    put_status(server, :forbidden)
  end

  @impl Page
  def template do
    ~HOLO"Module25"
  end
end
