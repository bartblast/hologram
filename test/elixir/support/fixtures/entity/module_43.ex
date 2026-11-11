# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module43 do
  use Hologram.Entity

  import Hologram.Query, only: [filter: 2, take: 2]

  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33

  attribute :last_read_at, :datetime, optional: true

  relationship :channel, Module32, optional: true

  derived :piped_recent, [Module33], fn channel ->
    channel.messages
    |> recent()
    |> take(1)
  end

  derived :recent, [Module33], fn channel -> recent(channel.messages) end

  derived :unread, [Module33], fn channel, last_read_at -> unread(channel, last_read_at) end

  allow :read

  def recent(messages), do: take(messages, 2)

  defp unread(channel, last_read_at), do: filter(channel.messages, created_at > ^last_read_at)
end
