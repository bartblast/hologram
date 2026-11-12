defmodule Hologram.Test.Fixtures.Template.Renderer.Module146 do
  use Hologram.Component

  prop :name, :string

  derived :upper, :string, fn name -> String.upcase(name) end

  derived :banner, :string, fn upper -> "[" <> upper <> "]" end

  @impl Component
  def template do
    ~HOLO"{@name} {@banner}"
  end
end
