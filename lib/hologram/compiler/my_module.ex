defmodule MyModule do
  def my_fun do
    h = 1
    t = [1, 2]
    abc = [h | t]
    xyz = %{a: 1, b: 2}
    xyz_2 = %{xyz | b: 4453}

    if :rand.uniform(100) > 50 do
      xyz_2
    else
      abc
    end
  end
end
