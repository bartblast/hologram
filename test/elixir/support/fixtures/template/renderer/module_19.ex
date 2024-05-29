defmodule Hologram.Test.Fixtures.Template.Renderer.Module19 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module19"

  param :param_1, :string
  param :param_3, :integer

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(params, component, _server) do
    put_state(component, params)
  end

  @impl Page
  def template do
    ~H"page vars = {vars |> :maps.to_list() |> :lists.sort() |> inspect()}"
  end
end
