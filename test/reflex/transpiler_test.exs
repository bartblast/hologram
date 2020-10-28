defmodule Reflex.TranspilerTest do
  use ExUnit.Case
  alias Reflex.Transpiler

  test "valid code" do
    assert {:ok, _} = Transpiler.parse_file("lib/reflex.ex")
  end

  test "invalid code" do
    assert {:error, _} = Transpiler.parse_file("README.md")
  end
end
