# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module65 do
  use Hologram.Component

  prop :prop_1, :string, default: "abc"
  prop :prop_2, :atom
  prop :prop_3, :integer, default: 123

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"component vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
