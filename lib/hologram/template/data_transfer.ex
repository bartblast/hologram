defmodule Hologram.Template.DataTransfer do
  @moduledoc false

  # What the $data_transfer attribute takes, judged by the build for a literal value and by the
  # server renderer for the value the attribute renders with, so both refuse a value with the same
  # message.
  #
  # WARNING: must match the client renderer's #renderDataTransfer and #dataTransferEntries
  # (renderer.mjs).

  defmodule Unknown do
    @moduledoc false

    # A value in a $data_transfer literal that only the render knows, like an assign.
    defstruct []
  end

  @drop_effects [:none, :copy, :move, :link]

  @doc """
  Judges a $data_transfer value: a keyword list or a map of the keys the attribute takes, each
  given once, with a drop effect only on a tag with a $drop binding. A map's entries are judged in
  the order of their keys, a keyword list's in the order written.

  A `%Unknown{}` value stops the judging, since what comes after it depends on what it turns out
  to be. Returns `:ok`, or `{:error, message}`.
  """
  @spec check(any, boolean) :: :ok | {:error, String.t()}
  def check(value, has_drop?) do
    with {:ok, entries} <- entries(value) do
      check_entries(entries, has_drop?)
    end
  end

  defp check_entries([], _has_drop?), do: :ok

  defp check_entries([{:drop_effect, %Unknown{}} | _rest], _has_drop?), do: :ok

  defp check_entries([{:drop_effect, value} | rest], has_drop?) do
    cond do
      value not in @drop_effects ->
        {:error,
         "the $data_transfer drop_effect takes :none, :copy, :move or :link, got #{inspect(value)}"}

      not has_drop? ->
        {:error,
         "the $data_transfer drop_effect goes on a tag with a $drop binding, which makes it a drop target"}

      true ->
        check_entries(rest, has_drop?)
    end
  end

  defp check_entries([{key, _value} | _rest], _has_drop?) do
    {:error, "the $data_transfer attribute takes the :drop_effect key, got #{inspect(key)}"}
  end

  defp duplicate_key(keys) do
    Enum.reduce_while(keys, MapSet.new(), fn key, seen_keys ->
      if MapSet.member?(seen_keys, key) do
        {:halt, {:duplicate, key}}
      else
        {:cont, MapSet.put(seen_keys, key)}
      end
    end)
  end

  defp entries(%_struct{} = value), do: invalid_value_error(value)

  defp entries(value) when is_map(value) do
    entries =
      value
      |> Map.to_list()
      |> List.keysort(0)

    {:ok, entries}
  end

  defp entries(value) when is_list(value) do
    if Keyword.keyword?(value) do
      case value
           |> Keyword.keys()
           |> duplicate_key() do
        {:duplicate, key} ->
          {:error,
           "the $data_transfer attribute takes each key once, but got the #{inspect(key)} key twice"}

        _seen_keys ->
          {:ok, value}
      end
    else
      invalid_value_error(value)
    end
  end

  defp entries(value), do: invalid_value_error(value)

  defp invalid_value_error(value) do
    {:error, "the $data_transfer attribute takes a keyword list or a map, got #{inspect(value)}"}
  end
end
