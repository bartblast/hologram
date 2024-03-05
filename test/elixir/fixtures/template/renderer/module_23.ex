defmodule Hologram.Test.Fixtures.Template.Renderer.Module23 do
  use Hologram.Component

  prop :key_1, :string
  prop :key_2, :string

  @impl Component
  def init(_props, component, _server) do
    put_state(component, key_2: "state_value_2", key_3: "state_value_3")
  end

  @impl Component
  def template do
    ~H"layout vars = {vars |> :maps.to_list() |> :lists.sort() |> inspect()}"
  end
end
