defmodule Hologram.Compiler.ModuleDefinitionGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.{Context, ModuleDefinitionGenerator, Opts}
  alias Hologram.Compiler.IR.{AtomType, FunctionDefinition, IntegerType, ModuleAttributeDefinition, ModuleDefinition, Variable}

  @module Abc.Bcd

  # this case is not possible, because such module would be pruned:
  # test "empty module"

  describe "attributes" do
    test "single attribute" do
      ir = %ModuleDefinition{
        attributes: [
          %ModuleAttributeDefinition{
            name: :abc,
            value: %IntegerType{value: 123}
          }
        ]
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static $abc = { type: 'integer', value: 123 };
      }
      """

      assert result == expected
    end

    test "multiple attributes" do
      ir = %ModuleDefinition{
        attributes: [
          %ModuleAttributeDefinition{
            name: :abc,
            value: %IntegerType{value: 123}
          },
          %ModuleAttributeDefinition{
            name: :bcd,
            value: %AtomType{value: :bcd_value}
          }
        ]
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static $abc = { type: 'integer', value: 123 };
      static $bcd = { type: 'atom', value: 'bcd_value' };
      }
      """

      assert result == expected
    end
  end

  describe "functions" do
    test "single function with single variant" do
      ir = %ModuleDefinition{
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
        module: @module
      }


      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static test() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end

    test "single function with multiple variants" do
      ir = %ModuleDefinition{
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
        module: @module
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static test() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }, { type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      let b = arguments[1];
      return { type: 'integer', value: 2 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end

    test "multiple functions with single variant" do
      ir = %ModuleDefinition{
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
        module: @module
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static test_1() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }

      static test_2() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 2 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end

    test "multiple functions with multiple variants" do
      ir = %ModuleDefinition{
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
        module: @module
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static test_1() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }, { type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      let b = arguments[1];
      return { type: 'integer', value: 2 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }

      static test_2() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 3 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end

    test "has preceding attributes section" do
      ir = %ModuleDefinition{
        attributes: [
          %ModuleAttributeDefinition{
            name: :abc,
            value: %IntegerType{value: 123}
          }
        ],
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
      }

      result = ModuleDefinitionGenerator.generate(ir, @module, %Context{}, %Opts{})

      expected = """
      window.Elixir_Abc_Bcd = class Elixir_Abc_Bcd {

      static $abc = { type: 'integer', value: 123 };

      static test() {
      if (Hologram.patternMatchFunctionArgs([{ type: 'placeholder' }], arguments)) {
      let a = arguments[0];
      return { type: 'integer', value: 1 };
      }
      else {
      console.debug(arguments)
      throw 'No match for the function call'
      }
      }
      }
      """

      assert result == expected
    end
  end
end
