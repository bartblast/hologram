# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module115 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module32, as: Entity32
  alias Hologram.Test.Fixtures.Entity.Module37, as: Entity37

  prop :channels, [Entity32], from_query: &channels_query/0
  prop :rooms, [Entity37], from_query: &rooms_query/0

  @impl Component
  def template do
    ~HOLO"""
    counts = {Enum.map_join(@channels, ",", & &1.message_count)}
    recent = {Enum.map_join(@channels, ",", fn channel -> Enum.map_join(channel.recent_messages, "-", & &1.position) end)}
    messages = {Enum.map_join(@channels, ",", &inspect(&1.messages))}
    authors = {Enum.map_join(@rooms, ",", fn room -> Enum.map_join(room.authored_messages, "-", &inspect(&1.author)) end)}
    room messages = {Enum.map_join(@rooms, ",", &inspect(&1.messages))}
    """
  end

  defp channels_query do
    include(Entity32, [message_count, recent_messages])
  end

  defp rooms_query do
    include(Entity37, authored_messages)
  end
end
