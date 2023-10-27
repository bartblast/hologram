defmodule Hologram.Commons.StringUtils do
  @doc """
  Appends the suffix to the given string.

  ## Examples

      iex> append("abc", "xyz")
      "abcxyz"
  """
  @spec append(String.t(), String.t()) :: String.t()
  def append(str, prefix) do
    str <> prefix
  end

  @doc """
  Prepends the prefix to the given string.

  ## Examples

      iex> prepend("abc", "xyz")
      "xyzabc"
  """
  @spec prepend(String.t(), String.t()) :: String.t()
  def prepend(str, prefix) do
    prefix <> str
  end

  @doc """
  Checks whether a string starts with a lowercase letter.

  - This function uses a binary pattern matching to extract the first UTF-8 character of the string.
  - It converts the first character to lowercase using `String.downcase/1` and compares it with the original character to determine if it is lowercase.
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
  def starts_with_lowercase?(""), do: false

  def starts_with_lowercase?(<<first_char::utf8, _rest::binary>>) do
    String.downcase(<<first_char::utf8>>) == <<first_char::utf8>>
  end

  @doc """
  Wraps the given string with one string on the left side and another string on the right side.

  ## Examples

      iex> wrap("ab", "cd", "ef")
      "cdabef"
  """
  @spec wrap(String.t(), String.t(), String.t()) :: String.t()
  def wrap(str, left, right) do
    str
    |> prepend(left)
    |> append(right)
  end

  @doc """
  Unwraps the given string with one string on the left side and another string on the right side.

  ## Examples

      iex> unwrap("cdabef", "cd", "ef")
      "ab"

      iex> unwrap("ab", "cd", "ef")
      "ab"
  """
  @spec unwrap(String.t(), String.t(), String.t()) :: String.t()
  def unwrap(str, left, right) do
    str
    |> String.replace_prefix(left, "")
    |> String.replace_suffix(right, "")
  end
end
