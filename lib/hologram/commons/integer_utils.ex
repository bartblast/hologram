defmodule Hologram.Commons.IntegerUtils do
  def count_digits(integer) do
    integer
    |> Integer.digits()
    |> Enum.count()
  end
end
