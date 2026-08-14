# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module29 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module29"

  layout LayoutFixture

  middleware :go_elsewhere

  def go_elsewhere(server, _opts) do
    put_redirect(server, Module4)
  end

  @impl Page
  def template do
    ~HOLO"Module29"
  end
end
