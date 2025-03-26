# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module16 do
  use Hologram.Component

  prop :prop_1, :string
  prop :prop_2, :integer
  prop :prop_3, :string

  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"component vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
