defmodule Hologram.Compiler.ForExpressionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{Context, ForExpressionTransformer, Transformer}

  test "single generator, single binding" do
    code = "for n <- [1, 2], do: n * n"

    expected_code = """
    Enum.reduce([1, 2], [], fn holo__, acc ->
      n = holo__
      acc ++ [n * n]
    end)
    """

    result_ast =
      code
      |> ast()
      |> ForExpressionTransformer.transform(%Context{})

    expected_ast =
      expected_code
      |> ast()
      |> Transformer.transform(%Context{})

    assert result_ast == expected_ast
  end

  test "multiple generators" do
    code = "for n <- [1, 2], m <- [3, 4], do: n * m"

    expected_code = """
    Enum.reduce([1, 2], [], fn holo__, acc ->
      n = holo__
      acc ++ Enum.reduce([3, 4], [], fn holo__, acc ->
        m = holo__
        acc ++ [n * m]
      end)
    end)
    """

    result_ast =
      code
      |> ast()
      |> ForExpressionTransformer.transform(%Context{})

    expected_ast =
      expected_code
      |> ast()
      |> Transformer.transform(%Context{})

    assert result_ast == expected_ast
  end

  test "single generator, multiple bindings" do
    code = "for {a, b} <- [{1, 2}, {3, 4}], do: a * b"

    expected_code = """
    Enum.reduce([{1, 2}, {3, 4}], [], fn holo__, acc ->
      {a, b} = holo__
      acc ++ [a * b]
    end)
    """

    result_ast =
      code
      |> ast()
      |> ForExpressionTransformer.transform(%Context{})

    expected_ast =
      expected_code
      |> ast()
      |> Transformer.transform(%Context{})

    assert result_ast == expected_ast
  end
end
