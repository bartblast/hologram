defmodule Hologram.Test.Fixtures.Template.Renderer.Module26 do
  use Hologram.Layout

  prop :prop_1, :string
  prop :prop_3, :string

  @impl Layout
  def template do
    ~H"layout vars = {vars |> :maps.to_list() |> :lists.sort() |> inspect()}"
  end
end
