defmodule Hologram.Commons.MapUtils do
  @doc """
  Computes the difference between two maps.

  Returns a list of update instructions needed to transform `old_map` 
  into `new_map`. The result includes:

  - New entries (exist in new but not in old)
  - Modified entries (exist in both but with different values)  
  - Deleted entries (exist in old but not in new, marked with `nil`)

  Unchanged entries are omitted from the result.

  ## Parameters

  - `old_map` - The previous map state
  - `new_map` - The desired map state

  ## Returns

  A list of `{key, value}` tuples representing update instructions.
  Deleted entries are represented with `nil` values.

  ## Examples

      iex> diff(%{}, %{"new" => "value"})
      [{"new", "value"}]

      iex> diff(%{"old" => "value"}, %{})
      [{"old", nil}]

      iex> diff(%{"key" => "old"}, %{"key" => "new"})
      [{"key", "new"}]

      iex> diff(%{"same" => "value"}, %{"same" => "value"})
      []
  """
  @spec diff(%{String.t() => any()}, %{String.t() => any()}) :: [{String.t(), any()}]
  def diff(old_map, new_map) do
    changed_or_new =
      for {key, value} <- new_map,
          old_map[key] != value,
          do: {key, value}

    deleted =
      for {key, _value} <- old_map,
          not Map.has_key?(new_map, key),
          do: {key, nil}

    changed_or_new ++ deleted
  end
end
