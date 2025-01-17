defmodule Hologram.Commons.IntegerUtils do
  @moduledoc false

  @doc """
  Counts the number of digits in the given integer.

  ## Examples

      iex> count_digits(123)
      3

      iex> count_digits(0)
      1

      iex> count_digits(-123)
      3
  """
  @spec count_digits(integer) :: non_neg_integer
  def count_digits(integer) do
    integer
    |> Integer.digits()
    |> Enum.count()
  end

  @doc """
  Returns the ordinal number (number with suffix "st", "nd", "rd", or "th") for a given integer.

  ## Examples

      iex> ordinal(1)
      "1st"
      
      iex> ordinal(42)
      "42nd"
      
      iex> ordinal(11)
      "11th"
  """
  @spec ordinal(integer) :: String.t()
  def ordinal(int) do
    # Based on: https://stackoverflow.com/a/39466341/13040586
    suffix_idx = rem(rem(int + 90, 100) - 10, 10)

    suffix = Map.get(%{1 => "st", 2 => "nd", 3 => "rd"}, suffix_idx, "th")

    "#{int}#{suffix}"
  end

  @doc """
  Parses a text representation of an integer.

  Raises an error if the text representation can't be parsed,
  or if the base is less than 2 or more than 36,
  or if only part of the text representation can be parsed.
  """
  @spec parse!(String.t(), integer) :: integer
  def parse!(binary, base \\ 10) do
    case Integer.parse(binary, base) do
      {integer, ""} ->
        integer

      :error ->
        raise ArgumentError, message: "invalid text representation"

      {_integer, _remainder} ->
        raise ArgumentError, message: "only part of the text representation can be parsed"
    end
  end
end
