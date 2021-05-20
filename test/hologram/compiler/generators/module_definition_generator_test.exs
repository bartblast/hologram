defmodule Hologram.Compiler.ModuleDefinitionGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{FunctionDefinition, IntegerType, ModuleDefinition, Variable}
  alias Hologram.Compiler.Generator

  test "single function with single variant" do
    ir = %ModuleDefinition{
      aliases: [],
      attributes: [],
      functions: [
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]}
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Abc, :Bcd]
    }

    result = Generator.generate(ir)

    expected = """
    class AbcBcd {

    static test() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
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
    ir = %ModuleDefinition{
      aliases: [],
      attributes: [],
      functions: [
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]}
          ],
          body: [
            %IntegerType{value: 1}
          ],
          name: :test,
          params: [
            %Variable{name: :a}
          ]
        },
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]},
            b: {1, [%Variable{name: :b}]}
          ],
          body: [
            %IntegerType{value: 2}
          ],
          name: :test,
          params: [
            %Variable{name: :a},
            %Variable{name: :b}
          ]
        }
      ],
      name: [:Abc, :Bcd]
    }

    result = Generator.generate(ir)

    expected = """
    class AbcBcd {

    static test() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }, { type: 'variable', name: 'b' }], arguments)) {
    let a = arguments[0];
    let b = arguments[1];
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

  test "multiple functions with single variant" do
    ir = %ModuleDefinition{
      aliases: [],
      attributes: [],
      functions: [
        %FunctionDefinition{
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
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]}
          ],
          body: [
            %IntegerType{value: 2}
          ],
          name: :test_2,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Abc, :Bcd]
    }

    result = Generator.generate(ir)

    expected = """
    class AbcBcd {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    static test_2() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
    let a = arguments[0];
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

  test "multiple functions with multiple variants" do
    ir = %ModuleDefinition{
      aliases: [],
      attributes: [],
      functions: [
        %FunctionDefinition{
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
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]},
            b: {1, [%Variable{name: :b}]}
          ],
          body: [
            %IntegerType{value: 2}
          ],
          name: :test_1,
          params: [
            %Variable{name: :a},
            %Variable{name: :b}
          ]
        },
        %FunctionDefinition{
          bindings: [
            a: {0, [%Variable{name: :a}]}
          ],
          body: [
            %IntegerType{value: 3}
          ],
          name: :test_2,
          params: [
            %Variable{name: :a}
          ]
        }
      ],
      name: [:Abc, :Bcd]
    }

    result = Generator.generate(ir)

    expected = """
    class AbcBcd {

    static test_1() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 1 };
    }
    else if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }, { type: 'variable', name: 'b' }], arguments)) {
    let a = arguments[0];
    let b = arguments[1];
    return { type: 'integer', value: 2 };
    }
    else {
    throw 'No match for the function call'
    }
    }

    static test_2() {
    if (Hologram.patternMatchFunctionArgs([{ type: 'variable', name: 'a' }], arguments)) {
    let a = arguments[0];
    return { type: 'integer', value: 3 };
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
