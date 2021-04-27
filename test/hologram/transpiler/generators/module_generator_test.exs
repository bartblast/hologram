defmodule Hologram.Transpiler.ModuleGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{Function, IntegerType, Module, Variable}
  alias Hologram.Transpiler.Generator

  # TODO: test aliases

  test "single function without muliptle variants" do
    ast = %Module{
      aliases: [],
      functions: [
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Prefix, :Test]
    }

    result = Generator.generate(ast)

    expected = """
    class PrefixTest {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    }
    """

    assert result == expected
  end

  test "single function with multiple variants" do
    ast = %Module{
      aliases: [],
      functions: [
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a}
          ]
        },
        %Function{
          bindings: [
            [%Variable{name: :a}],
            [%Variable{name: :b}]
          ],
          body: [
            %IntegerType{value: 1},
            %IntegerType{value: 2}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a},
            %Variable{name: :b}
          ]
        }
      ],
      name: [:Prefix, :Test]
    }

    result = Generator.generate(ast)

    expected = """
    class PrefixTest {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([ { type: 'variable' }, { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    let b = arguments[1];
    { type: 'integer', value: 1 };
    return { type: 'integer', value: 2 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    }
    """

    assert result == expected
  end

  test "multiple functions without multiple variants" do
    ast = %Module{
      aliases: [],
      functions: [
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a}
          ]
        },
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_2,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Prefix, :Test]
    }

    result = Generator.generate(ast)

    expected = """
    class PrefixTest {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    static test_2() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    }
    """

    assert result == expected
  end

  test "multiple functions with multiple variants" do
    ast = %Module{
      aliases: [],
      functions: [
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a}
          ]
        },
        %Function{
          bindings: [
            [%Variable{name: :a}],
            [%Variable{name: :b}]
          ],
          body: [
            %IntegerType{value: 1},
            %IntegerType{value: 2}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a},
            %Variable{name: :b}
          ]
        },
        %Function{
          bindings: [
            [%Variable{name: :a}]
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test_2,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Prefix, :Test]
    }

    result = Generator.generate(ast)

    expected = """
    class PrefixTest {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([ { type: 'variable' }, { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    let b = arguments[1];
    { type: 'integer', value: 1 };
    return { type: 'integer', value: 2 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    static test_2() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    }
    """

    assert result == expected
  end
end
