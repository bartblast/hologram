# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module92 do
  use Hologram.Component

  prop :aaa, :atom, values: [:small, :large], from_context: :my_context_key

  @impl Component
  def template do
    ~HOLO"prop_aaa = {@aaa}"
  end
end
