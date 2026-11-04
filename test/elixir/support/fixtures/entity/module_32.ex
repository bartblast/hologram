# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module32 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module33

  attribute :name, :string

  relationship :messages, [Module33], inverse: channel, sort: position

  derived :first_message, Module33, fn messages -> one(messages) end

  derived :first_messages, [Module33], fn messages -> take(messages, 3) end

  derived :message_count, :integer, fn messages -> count(messages) end

  derived :recent_messages, [Module33], fn messages ->
    messages
    |> sort(position: :desc)
    |> take(2)
  end

  allow :read
end
