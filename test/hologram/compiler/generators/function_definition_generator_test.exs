defmodule Hologram.Compiler.FunctionDefinitionGeneratorTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.{Context, FunctionDefinitionGenerator, Opts}

  test "no vars / single expression / single variant" do
    code = "def test, do: 1"
    ir = ir(code)
    variants = [ir]

    result = FunctionDefinitionGenerator.generate(ir.name, variants, %Context{}, %Opts{})

    expected = """
    static test() {
    if (Hologram.isFunctionArgsPatternMatched([], arguments)) {
    return { type: 'integer', value: 1 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end

  test "single var" do
    code = "def test(x), do: 1"
    ir = ir(code)
    variants = [ir]

    result = FunctionDefinitionGenerator.generate(ir.name, variants, %Context{}, %Opts{})

    expected = """
    static test() {
    if (Hologram.isFunctionArgsPatternMatched([ { type: 'placeholder' } ], arguments)) {
    let x = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end

  test "multiple vars" do
    code = "def test(x, y), do: 1"
    ir = ir(code)
    variants = [ir]

    result = FunctionDefinitionGenerator.generate(ir.name, variants, %Context{}, %Opts{})

    expected = """
    static test() {
    if (Hologram.isFunctionArgsPatternMatched([ { type: 'placeholder' }, { type: 'placeholder' } ], arguments)) {
    let x = arguments[0];
    let y = arguments[1];
    return { type: 'integer', value: 1 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end

  test "multiple expressions" do
    code = """
    def test do
      1
      2
    end
    """

    ir = ir(code)
    variants = [ir]

    result = FunctionDefinitionGenerator.generate(ir.name, variants, %Context{}, %Opts{})

    expected = """
    static test() {
    if (Hologram.isFunctionArgsPatternMatched([], arguments)) {
    { type: 'integer', value: 1 };
    return { type: 'integer', value: 2 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end

  test "multiple variants" do
    code = """
    defmodule Hologram.Test.Fixtures.PlaceholderModule do
      def test(1), do: 1
      def test(2), do: 2
    end
    """

    ir = ir(code)
    name = :test
    variants = Enum.filter(ir.functions, &(&1.name == name))

    result = FunctionDefinitionGenerator.generate(name, variants, %Context{}, %Opts{})

    expected = """
    static test() {
    if (Hologram.isFunctionArgsPatternMatched([ { type: 'integer', value: 1 } ], arguments)) {
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.isFunctionArgsPatternMatched([ { type: 'integer', value: 2 } ], arguments)) {
    return { type: 'integer', value: 2 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end

  test "name" do
    code = "def test?, do: 1"
    ir = ir(code)
    variants = [ir]

    result = FunctionDefinitionGenerator.generate(ir.name, variants, %Context{}, %Opts{})

    expected = """
    static test$question() {
    if (Hologram.isFunctionArgsPatternMatched([], arguments)) {
    return { type: 'integer', value: 1 };
    }
    else {
    console.debug(arguments)
    throw 'No match for the function call'
    }
    }
    """

    assert result == expected
  end
end
