defmodule Hologram.CookieStore do
  @moduledoc false

  @doc """
  Computes the difference between two cookie sets.

  Returns a list of update instructions needed to transform `old_cookies` 
  into `new_cookies`. The result includes:

  - New cookies (exist in new but not in old)
  - Modified cookies (exist in both but with different values)  
  - Deleted cookies (exist in old but not in new, marked with `nil`)

  Unchanged cookies are omitted from the result.

  ## Parameters

  - `old_cookies` - The previous cookie state as a map
  - `new_cookies` - The desired cookie state as a map

  ## Returns

  A list of `{key, value}` tuples representing update instructions.
  Deleted cookies are represented with `nil` values.

  ## Examples

      iex> CookieStore.diff(%{}, %{"new" => "value"})
      [{"new", "value"}]

      iex> CookieStore.diff(%{"old" => "value"}, %{})
      [{"old", nil}]

      iex> CookieStore.diff(%{"key" => "old"}, %{"key" => "new"})
      [{"key", "new"}]

      iex> CookieStore.diff(%{"same" => "value"}, %{"same" => "value"})
      []
  """
  @spec diff(%{String.t() => any()}, %{String.t() => any()}) :: [{String.t(), any()}]
  def diff(old_cookies, new_cookies) do
    changed_or_new =
      for {key, value} <- new_cookies,
          old_cookies[key] != value,
          do: {key, value}

    deleted =
      for {key, _value} <- old_cookies,
          not Map.has_key?(new_cookies, key),
          do: {key, nil}

    changed_or_new ++ deleted
  end
end
