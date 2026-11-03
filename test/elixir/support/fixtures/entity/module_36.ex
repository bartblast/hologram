# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module36 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34

  attribute :last_read_at, :datetime, optional: true

  relationship :channel, Module32, optional: true
  relationship :member, Module34, optional: true

  derived :member_messages, [Module33], fn member -> Module53.member_messages(member) end

  derived :recent_unread, [Module33], fn channel, last_read_at ->
    channel
    |> Module53.unread_messages(last_read_at)
    |> take(5)
  end

  derived :unread_count, :integer, fn channel, last_read_at ->
    Module53.unread_count(channel, last_read_at)
  end

  derived :unread_through_helper, [Module33], fn channel, last_read_at ->
    Module53.unread_through_helper(channel, last_read_at)
  end

  allow :read
end
