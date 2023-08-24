defmodule Hologram.Commons.StringUtils do
  @doc """
  Prepends the prefix to the given string.
  """
  @spec prepend(String.t(), String.t()) :: String.t()
  def prepend(str, prefix) do
    prefix <> str
  end

  @doc """
  Checks whether a string starts with a lowercase letter.

  - This function uses the `String.next_grapheme/1` function to extract the first letter of the string.
  - It converts the first letter to lowercase using `String.downcase/1` and compares it with the original first letter to determine if it is lowercase.
  - If the input string is empty, the function returns `false`.

  ## Parameters

  - `str` - The input string to be checked.

  ## Returns

  Returns `true` if the string starts with a lowercase letter, and `false` otherwise.

  ## Examples

      iex> starts_with_lowercase?("Hello")
      false

      iex> starts_with_lowercase?("world")
      true
  """
  @spec starts_with_lowercase?(String.t()) :: boolean
  def starts_with_lowercase?(str) do
    case String.next_grapheme(str) do
      {first_letter, _rest} ->
        String.downcase(first_letter) == first_letter

      nil ->
        false
    end
  end

  @doc """
  Wraps the given string with one string on the left side and another string on the right side.

  ## Examples

      iex> wrap("ab", "cd", "ef")
      "cdabef"
  """
  @spec wrap(String.t(), String.t(), String.t()) :: String.t()
  def wrap(str, left, right) do
    left <> str <> right
  end
end
