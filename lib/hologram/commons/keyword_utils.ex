defmodule Hologram.Commons.KeywordUtils do
  @moduledoc false

  @doc """
  Recursively merges two keyword lists.

  When both values for the same key are keyword lists themselves,
  they are merged recursively. Otherwise, the value from the second
  keyword list takes precedence.

  ## Examples

      iex> deep_merge([a: 1, b: [c: 2]], [b: [d: 3], e: 4])
      [a: 1, b: [c: 2, d: 3], e: 4]
      
      iex> deep_merge([a: [b: 1]], [a: [c: 2]])
      [a: [b: 1, c: 2]]
  """
  @spec deep_merge(keyword, keyword) :: keyword
  def deep_merge(keyword_1, keyword_2) when is_list(keyword_1) and is_list(keyword_2) do
    Keyword.merge(keyword_1, keyword_2, fn _key, value_1, value_2 ->
      if Keyword.keyword?(value_1) and Keyword.keyword?(value_2) do
        deep_merge(value_1, value_2)
      else
        value_2
      end
    end)
  end
end
