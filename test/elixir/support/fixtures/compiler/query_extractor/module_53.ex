# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53 do
  # Query builders derived fields call.

  import Hologram.Query

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55

  def by_flag(channel, flag) do
    if flag do
      channel.messages
    else
      take(channel.messages, 1)
    end
  end

  def capitalized(nickname), do: String.capitalize(nickname)

  def constant, do: 5

  def either_way(messages, :all), do: messages

  def either_way(messages, _kind), do: messages

  def length_of(nickname), do: nickname.length

  def looping(messages), do: looping(messages)

  def member_messages(member), do: member.channel.messages

  def message_total(_messages), do: 3

  def missing(member), do: member.nothing

  def recent_or_all(messages, :recent), do: take(messages, 2)

  def recent_or_all(messages, _kind), do: messages

  def senders(channel), do: channel.messages.channel

  def unread_through_helper(channel, last_read_at) do
    channel
    |> Module55.messages_of()
    |> filter(created_at > ^Module55.as_given(last_read_at))
  end

  def unread_count(channel, last_read_at) do
    channel
    |> unread_messages(last_read_at)
    |> count()
  end

  def unread_messages(channel, last_read_at) do
    filter(channel.messages, created_at > ^last_read_at)
  end
end
