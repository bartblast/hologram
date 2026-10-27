# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module38 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module38"

  layout LayoutFixture

  middleware :mark

  def mark(server, _opts) do
    put_response_header(server, "x-my-header", "my_value")
  end

  @impl Page
  def template do
    ~HOLO"Module38"
  end
end
