defmodule Hologram.Test.Fixtures.Template.Renderer.Module21 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module21"

  param :key_1, :string
  param :key_2, :string

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, key_2: "state_value_2", key_3: "state_value_3")
  end

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Page
  def template do
    ~HOLO"page vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
