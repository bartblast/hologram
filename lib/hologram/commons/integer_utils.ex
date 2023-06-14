defmodule Hologram.Commons.IntegerUtils do
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
end
