# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module86 do
  use Hologram.Component

  prop :my_prop_1, :string
  prop :my_prop_2, :map
  prop :my_prop_3, :list

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"component vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
