# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module171 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26

  derived :channels, [Entity26], fn ->
    Entity26
    |> filter(any(message <- messages, message.channel.name != "nothing"))
    |> include(messages)
  end

  @impl Component
  def template do
    ~HOLO"""
    channel = {Enum.map_join(@channels, ",", fn channel -> Enum.map_join(channel.messages, ",", &inspect(&1.channel)) end)}
    """
  end
end
