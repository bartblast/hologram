defmodule Hologram.Utils do
  def atomize_keys(data) when is_struct(data), do: data

  def atomize_keys(data) when is_map(data) do
    data
    |> Enum.map(fn {key, value} ->
      {to_string(key) |> String.to_atom(), atomize_keys(value)}
    end)
    |> Enum.into(%{})
  end

  def atomize_keys([head | tail]) do
    [atomize_keys(head) | atomize_keys(tail)]
  end

  def atomize_keys(data), do: data

  def prepend(str, prefix), do: prefix <> str
end
