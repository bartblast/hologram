defmodule Hologram.Realtime.Channel do
  @moduledoc false

  alias Hologram.Identifier

  @doc """
  Returns the given channel, or raises `ArgumentError` when it isn't an identifier: an atom, like
  `:notifications`, or a tuple of an atom followed by one or more integers, strings or atoms, like
  `{:room, 42}` or `{:doc, "abc", "v2"}`, with no `nil`, `true` or `false` among its atoms and only valid UTF-8 strings.
  """
  @spec validate!(any) :: atom | tuple
  def validate!(channel) do
    Identifier.validate!(
      channel,
      "a channel must be an identifier, like :search or {:message, 42}"
    )
  end
end
