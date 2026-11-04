# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module35 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Derived.Module2, as: DerivedModule2
  alias Hologram.Test.Fixtures.Entity.Module32

  relationship :channel, Module32, optional: true

  derived :channel_name, :string, fn channel -> channel.name end

  derived :latest, [Hologram.Test.Fixtures.Entity.Module33], fn channel ->
    channel.messages
    |> DerivedModule2.recent()
    |> take(1)
  end

  derived :recent, [Hologram.Test.Fixtures.Entity.Module33], fn channel ->
    DerivedModule2.recent(channel.messages)
  end

  allow :read
end
