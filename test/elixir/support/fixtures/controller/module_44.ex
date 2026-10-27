# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module44 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module4
  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module44"

  layout LayoutFixture

  middleware :go_elsewhere_with_a_body

  def go_elsewhere_with_a_body(server, _opts) do
    server
    |> put_response_header("content-type", "text/plain")
    |> put_response_body("sending you elsewhere")
    |> put_redirect(Module4)
  end

  @impl Page
  def template do
    ~HOLO"Module44"
  end
end
