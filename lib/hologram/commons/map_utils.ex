defmodule Hologram.Commons.MapUtils do
  @doc """
  Computes the difference between two maps.

  Returns a map with three keys describing the changes needed to transform `old_map` 
  into `new_map`:

  - `:added` - New entries (exist in new but not in old) as `{key, value}` tuples
  - `:edited` - Modified entries (exist in both but with different values) as `{key, new_value}` tuples  
  - `:removed` - Deleted entries (exist in old but not in new) as a list of keys

  Unchanged entries are omitted from the result.

  ## Performance

  This implementation is optimized for maps with smaller number of items (typically < 100).
  It uses direct list comprehensions which have lower overhead for small collections
  compared to more complex reduction-based approaches.

  ## Parameters

  - `old_map` - The previous map state
  - `new_map` - The desired map state

  ## Returns

  A map with keys `:added`, `:removed`, and `:edited` containing the respective changes.

  ## Examples

      iex> diff(%{}, %{new: "value"})
      %{added: [{:new, "value"}], removed: [], edited: []}

      iex> diff(%{"old" => "value"}, %{})
      %{added: [], removed: ["old"], edited: []}

      iex> diff(%{key: "old"}, %{key: "new"})
      %{added: [], removed: [], edited: [{:key, "new"}]}

      iex> diff(%{"same" => "value"}, %{"same" => "value"})
      %{added: [], removed: [], edited: []}

      iex> diff(%{:abc => 1, 2 => "two"}, %{:abc => 10, 3 => "three"})
      %{added: [{3, "three"}], removed: [2], edited: [{:abc, 10}]}
  """
  @spec diff(map(), map()) :: %{
          added: [{any(), any()}],
          removed: [any()],
          edited: [{any(), any()}]
        }
  def diff(old_map, new_map) do
    # Direct comprehensions are more efficient for small maps

    added =
      for {key, value} <- new_map,
          not Map.has_key?(old_map, key),
          do: {key, value}

    edited =
      for {key, value} <- new_map,
          Map.has_key?(old_map, key) and old_map[key] !== value,
          do: {key, value}

    removed =
      for {key, _value} <- old_map,
          not Map.has_key?(new_map, key),
          do: key

    %{added: added, removed: removed, edited: edited}
  end

  @doc """
  Puts a value in a nested path within a map-like structure (maps and structs).

  This function works with both maps and structs, unlike `Kernel.put_in/3` which only 
  works with structures that implement the Access behavior.

  ## Parameters

  - `data` - The map or struct to update
  - `keys` - A list of keys representing the nested path
  - `value` - The value to put at the specified path

  ## Returns

  The updated map or struct with the value set at the specified nested path.
  Missing intermediate paths will be created as empty maps.

  ## Examples

      iex> put_nested(%{a: %{b: 1}}, [:a, :b], 2)
      %{a: %{b: 2}}

      iex> put_nested(%{}, [:a, :b, :c], "value")
      %{a: %{b: %{c: "value"}}}

      iex> put_nested(%MyStruct{field: %{nested: 1}}, [:field, :nested], 99)
      %MyStruct{field: %{nested: 99}}
  """
  @spec put_nested(map, [any], any) :: map
  def put_nested(data, [key], value) do
    Map.put(data, key, value)
  end

  def put_nested(data, [key | rest], value) do
    nested_data = Map.get(data, key, %{})
    Map.put(data, key, put_nested(nested_data, rest, value))
  end
end
