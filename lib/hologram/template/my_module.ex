defmodule MyModule do
  def my_fun_d(x = 1 = y), do: x + y

  def test do
    fn x = 1 = y -> x + y end
  end
end
