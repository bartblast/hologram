# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module34 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module32

  @busy 3

  @ranks [1, 2]

  attribute :nickname, :string
  attribute :score, :integer

  relationship :channel, Module32, optional: true

  derived :active, :boolean, fn score -> score > 0 and score < @busy end

  derived :badge, :string, fn score -> if score >= @busy, do: "top" end

  derived :channel_load, :integer, fn channel -> channel.message_count end

  derived :display_name, :string, fn nickname, channel ->
    nickname <> " (" <> channel.name <> ")"
  end

  derived :featured, :boolean, fn score, nickname -> score not in [0] or nickname == "lead" end

  derived :level, :enum, [values: [:busy, :quiet]], fn channel_load ->
    if channel_load > @busy, do: :busy, else: :quiet
  end

  derived :named_after_channel, :boolean, fn nickname, channel -> nickname == channel.name end

  derived :ranked, :boolean, fn score, channel ->
    score in @ranks or (channel.name in ["general"] and score > -1)
  end

  derived :recent_count, :integer, fn channel ->
    channel.messages
    |> filter(position > 1)
    |> count()
  end

  derived :score_label, :string, fn score ->
    if score > 5 do
      "high"
    else
      "low"
    end
  end

  @busy 10

  derived :top_score, :integer, fn -> @busy end

  allow :read
end
