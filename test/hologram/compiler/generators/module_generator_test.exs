defmodule Hologram.Compiler.ModuleGeneratorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{Function, IntegerType, Module, Variable}
  alias Hologram.Compiler.Generator

  # TODO: test aliases

  test "single function without muliptle variants" do
    ast = %Module{
      aliases: [],
      attributes: [],
      functions: [
        %Function{
          bindings: [
            a: {0, [%Variable{name: :a}]}
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
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
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
      attributes: [],
      functions: [
        %Function{
          bindings: [
            a: {0, [%Variable{name: :a}]}
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
            a: {0, [%Variable{name: :a}]},
            b: {1, [%Variable{name: :b}]}
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
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' }, { type: 'variable', name: 'b' } ], arguments)) {
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
      attributes: [],
      functions: [
        %Function{
          bindings: [
            a: {0, [%Variable{name: :a}]}
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
            a: {0, [%Variable{name: :a}]}
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
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    static test_2() {
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
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
      attributes: [],
      functions: [
        %Function{
          bindings: [
            a: {0, [%Variable{name: :a}]}
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
            a: {0, [%Variable{name: :a}]},
            b: {1, [%Variable{name: :b}]}
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
            a: {0, [%Variable{name: :a}]}
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
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' }, { type: 'variable', name: 'b' } ], arguments)) {
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
    if (Hologram.patternMatchFunctionArgs([ { type: 'variable', name: 'a' } ], arguments)) {
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
