defmodule Hologram.Compiler.JSEncoder.CaseExpressionTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Context, JSEncoder, Opts}

  defp encode(code) do
    code
    |> ir()
    |> JSEncoder.encode(%Context{}, %Opts{})
  end

  test "single clause / single expression clause body / no bindings" do
    code = """
    case x do
      1 -> :ok
    end
    """

    result = encode(code)

    expected = """
    Elixir_Kernel_SpecialForms.case(x, function($condition) {
    if (Hologram.isCaseClausePatternMatched({ type: 'integer', value: 1 }, $condition)) {
    return { type: 'atom', value: 'ok' };
    }
    else {
    throw 'No case clause matching'
    }
    })\
    """

    assert result == expected
  end

  test "multiple clauses" do
    code = """
    case x do
      1 -> :ok_1
      2 -> :ok_2
    end
    """

    result = encode(code)

    expected = """
    Elixir_Kernel_SpecialForms.case(x, function($condition) {
    if (Hologram.isCaseClausePatternMatched({ type: 'integer', value: 1 }, $condition)) {
    return { type: 'atom', value: 'ok_1' };
    }
    else if (Hologram.isCaseClausePatternMatched({ type: 'integer', value: 2 }, $condition)) {
    return { type: 'atom', value: 'ok_2' };
    }
    else {
    throw 'No case clause matching'
    }
    })\
    """

    assert result == expected
  end

  test "multiple expression clause body" do
    code = """
    case x do
      1 ->
        :expr_1
        :expr_2
    end
    """

    result = encode(code)

    expected = """
    Elixir_Kernel_SpecialForms.case(x, function($condition) {
    if (Hologram.isCaseClausePatternMatched({ type: 'integer', value: 1 }, $condition)) {
    { type: 'atom', value: 'expr_1' };
    return { type: 'atom', value: 'expr_2' };
    }
    else {
    throw 'No case clause matching'
    }
    })\
    """

    assert result == expected
  end

  test "single binding" do
    code = """
    case x do
      %{a: a} -> :ok
    end
    """

    result = encode(code)

    expected = """
    Elixir_Kernel_SpecialForms.case(x, function($condition) {
    if (Hologram.isCaseClausePatternMatched({ type: 'map', data: { '~atom[a]': { type: 'placeholder' } } }, $condition)) {
    let a = $condition.data['~atom[a]'];
    return { type: 'atom', value: 'ok' };
    }
    else {
    throw 'No case clause matching'
    }
    })\
    """

    assert result == expected
  end

  test "multiple bindings" do
    code = """
    case x do
      %{a: a, b: b} -> :ok
    end
    """

    result = encode(code)

    expected = """
    Elixir_Kernel_SpecialForms.case(x, function($condition) {
    if (Hologram.isCaseClausePatternMatched({ type: 'map', data: { '~atom[a]': { type: 'placeholder' }, '~atom[b]': { type: 'placeholder' } } }, $condition)) {
    let a = $condition.data['~atom[a]'];
    let b = $condition.data['~atom[b]'];
    return { type: 'atom', value: 'ok' };
    }
    else {
    throw 'No case clause matching'
    }
    })\
    """

    assert result == expected
  end
end
