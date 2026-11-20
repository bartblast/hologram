# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module55 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module37

  attribute :note, :string

  relationship :channel, Module37, optional: true

  derived :channel_pinned, :integer, fn channel -> channel.pinned_count end

  derived :status, :string, fn channel_pinned ->
    if channel_pinned > 3, do: "busy", else: "quiet"
  end

  derived :tag, :string, fn status, note -> status <> note end

  allow :read
end
