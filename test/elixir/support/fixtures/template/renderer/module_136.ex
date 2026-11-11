# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module136 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26

  prop :channels, [Entity26], from_query: &channels_query/0

  @impl Component
  def template do
    ~HOLO"""
    channel = {Enum.map_join(@channels, ",", fn channel -> Enum.map_join(channel.messages, ",", &inspect(&1.channel)) end)}
    """
  end

  defp channels_query do
    Entity26
    |> filter(any(message <- messages, message.channel.name != "nothing"))
    |> include(messages)
  end
end
