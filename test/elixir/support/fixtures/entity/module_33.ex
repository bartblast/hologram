# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module33 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module32

  @default_tier :low

  attribute :body, :string
  attribute :position, :integer

  relationship :channel, Module32, optional: true

  derived :channel_name, :string, fn channel -> channel.name end

  derived :later_count, :integer, fn channel, position ->
    channel.messages
    |> filter(position > ^position)
    |> count()
  end

  derived :tier, :enum, [values: [:low, :high]], fn -> @default_tier end

  allow :read
end
