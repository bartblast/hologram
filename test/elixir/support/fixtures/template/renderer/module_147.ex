defmodule Hologram.Test.Fixtures.Template.Renderer.Module147 do
  use Hologram.Component

  prop :name, :string

  state :suffix, :string, default: "!"

  derived :shout, :string, fn name, suffix -> name <> suffix end

  @impl Component
  def template do
    ~HOLO"{@shout}"
  end
end
