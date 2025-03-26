defmodule Hologram.Test.Fixtures.Template.Renderer.Module23 do
  use Hologram.Component

  prop :key_1, :string
  prop :key_2, :string

  @impl Component
  def init(_props, component, _server) do
    put_state(component, key_2: "state_value_2", key_3: "state_value_3")
  end

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"layout vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
