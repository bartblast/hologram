# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module16 do
  use Hologram.Component

  prop :prop_1, :string
  prop :prop_2, :integer
  prop :prop_3, :string

  @impl Component
  def template do
    ~H"component vars = {vars |> :maps.to_list() |> :lists.sort() |> inspect()}"
  end
end
