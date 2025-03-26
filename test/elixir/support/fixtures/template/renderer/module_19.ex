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

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Page
  def template do
    ~HOLO"page vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
