# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module37 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module38

  attribute :last_read_at, :datetime, optional: true
  attribute :name, :string

  relationship :members, [Module2]
  relationship :messages, [Module38], inverse: channel

  derived :authored_messages, [Module38], fn messages -> include(messages, author) end

  derived :busy, :boolean, fn pinned_count -> pinned_count > 3 end

  derived :colleague_count, :integer, fn messages -> count(messages.channel.messages) end

  derived :member_count, :integer, fn members -> count(members) end

  derived :pinned_count, :integer, fn messages ->
    messages
    |> filter(pinned == true)
    |> count()
  end

  derived :nothing, [Module38], fn -> nil end

  derived :picked, [Module38], fn messages, name ->
    if name == "general", do: take(messages, 1), else: messages.channel.messages
  end

  derived :picked_count, :integer, fn picked -> count(picked) end

  derived :recent_messages, [Module38], fn messages ->
    messages
    |> sort(created_at: :desc)
    |> take(3)
  end

  derived :unread_count, :integer, fn messages, last_read_at ->
    messages
    |> filter(created_at > ^last_read_at)
    |> count()
  end

  allow :read
end
