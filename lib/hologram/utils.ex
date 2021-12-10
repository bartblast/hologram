defmodule Hologram.Utils do
  def append(str, suffix), do: str <> suffix

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

  # DEFER: test
  def await_tasks(tasks) do
    Enum.map(tasks, &(Task.await(&1, :infinity)))
  end

  def deserialize(data) do
    :erlang.binary_to_term(data)
  end

  # DEFER: test
  def map_async(enumerable, callback) do
    Enum.map(enumerable, fn elem ->
      Task.async(fn -> callback.(elem) end)
    end)
  end

  def prepend(str, prefix), do: prefix <> str

  def serialize(data) do
    :erlang.term_to_binary(data, compressed: 9)
  end

  def uuid do
    Ecto.UUID.generate()
  end

  def uuid(:hex) do
    uuid()
    |> String.replace("-", "")
  end

  def uuid_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end

  def uuid_regex do
    ~r/^[0-9a-f]{8}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{12}$/
  end
end
