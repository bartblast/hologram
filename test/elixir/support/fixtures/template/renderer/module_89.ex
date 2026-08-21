# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module89 do
  use Hologram.Component

  prop :aaa, :string, required: true

  @impl Component
  def template do
    ~HOLO"prop_aaa = {@aaa}"
  end
end
