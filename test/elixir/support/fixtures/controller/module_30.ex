# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module30 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module30"

  layout LayoutFixture

  middleware :answer_with_a_body

  # A terminal response that succeeded, which is what makes status alone useless for telling a page
  # payload from a page's own answer.
  def answer_with_a_body(server, _opts) do
    server
    |> put_status(200)
    |> put_response_body("answered by middleware")
  end

  @impl Page
  def template do
    ~HOLO"Module30"
  end
end
