# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module91 do
  use Hologram.Component

  prop :aaa, :atom, values: [:small, :large]

  # Renders vars rather than the prop itself, so that a render with the prop absent still works.
  # Can't use Hologram.Commons.KernelUtils.inspect/1 here,
  # because this module is used in client renderer tests.
  @impl Component
  def template do
    ~HOLO"component vars = {inspect(vars, custom_options: [sort_maps: true])}"
  end
end
