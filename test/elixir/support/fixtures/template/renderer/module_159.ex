defmodule Hologram.Test.Fixtures.Template.Renderer.Module159 do
  use Hologram.Component

  prop :label, :string

  derived :loud_label, :string, fn label -> String.upcase(label) end

  @impl Component
  def template do
    ~HOLO"layout {@loud_label} <slot />"
  end
end
