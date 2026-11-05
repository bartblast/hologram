# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module99 do
  use Hologram.Component

  prop :words, :list

  @impl Component
  def template do
    ~HOLO"""
    <ul>{%for word <- @words}<li $key={word}>{word}</li>{/for}</ul>
    """
  end
end
