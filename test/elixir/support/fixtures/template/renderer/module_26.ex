defmodule Hologram.Test.Fixtures.Template.Renderer.Module26 do
  use Hologram.Component

  prop :prop_1, :string
  prop :prop_3, :string

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"layout vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
