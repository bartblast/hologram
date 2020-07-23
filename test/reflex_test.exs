defmodule ReflexTest do
  use ExUnit.Case
  doctest Reflex

  test "greets the world" do
    assert Reflex.hello() == :world
  end
end
