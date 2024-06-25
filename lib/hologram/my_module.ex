defmodule MyModule do
  import Bitwise

  def test1 do
    9 &&& 3
  end

  def test2 do
    9 ||| 3
  end

  def test3 do
    1 <<< 2
  end

  def test4 do
    1 >>> 2
  end
end
