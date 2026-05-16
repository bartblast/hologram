defmodule Hologram.Realtime.Channel do
  @moduledoc false

  @doc """
  Validates a channel argument; returns the channel or raises `ArgumentError`.

  Accepted shapes:
    * bare atom (e.g. `:notifications`)
    * tagged tuple of size >= 2 with an atom tag and primitive values
      (atom, integer, string) as the remaining elements
      (e.g. `{:room, 42}`, `{:doc, "abc", "v2"}`)
  """
  @spec validate!(any) :: atom | tuple
  def validate!(channel) when is_atom(channel), do: channel

  def validate!(channel) when is_tuple(channel) and tuple_size(channel) >= 2 do
    [tag | rest] = Tuple.to_list(channel)

    unless is_atom(tag) do
      raise ArgumentError,
            "channel tuple's first element must be an atom; got #{inspect(channel)}"
    end

    Enum.each(rest, fn value ->
      unless primitive?(value) do
        raise ArgumentError,
              "channel tuple elements after the tag must be primitive (atom, integer, string); got #{inspect(value)} in #{inspect(channel)}"
      end
    end)

    channel
  end

  def validate!(channel) when is_tuple(channel) do
    raise ArgumentError,
          "channel tuple must have at least 2 elements; got #{tuple_size(channel)}-tuple #{inspect(channel)}"
  end

  def validate!(channel) when is_binary(channel) do
    raise ArgumentError,
          "channel must be a bare atom or tagged tuple; got bare string #{inspect(channel)}"
  end

  def validate!(channel) do
    raise ArgumentError,
          "channel must be a bare atom or tagged tuple; got #{inspect(channel)}"
  end

  defp primitive?(value) when is_atom(value) or is_integer(value) or is_binary(value), do: true

  defp primitive?(_value), do: false
end
