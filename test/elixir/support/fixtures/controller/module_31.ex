# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module31 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module31"

  layout LayoutFixture

  middleware :go_elsewhere_with_a_header

  def go_elsewhere_with_a_header(server, _opts) do
    server
    |> put_response_header("x-my-header", "my_value")
    |> put_redirect(Module4)
  end

  @impl Page
  def template do
    ~HOLO"Module31"
  end
end
