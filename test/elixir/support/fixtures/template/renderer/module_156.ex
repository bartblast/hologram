defmodule Hologram.Test.Fixtures.Template.Renderer.Module156 do
  use Hologram.Component

  prop :theme, :string, from_context: {Hologram.Test.Fixtures.Template.Renderer.Module156, :theme}

  derived :label, :string, fn theme -> "theme " <> theme end

  @impl Component
  def template do
    ~HOLO"{@label}"
  end
end
