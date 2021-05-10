# TODO: refactor & test

defmodule Hologram.Compiler.Generator do
  alias Hologram.Compiler.AST.{
    AtomType,
    BooleanType,
    DotOperator,
    IntegerType,
    ListType,
    MapType,
    StringType,
    StructType
  }

  alias Hologram.Compiler.AST.{AdditionOperator, ModuleAttributeOperator}

  alias Hologram.Compiler.AST.{AccessOperator, FunctionDefinition, FunctionCall, ModuleDefinition, Variable}

  alias Hologram.Compiler.{
    AdditionOperatorGenerator,
    DotOperatorGenerator,
    MapTypeGenerator,
    ModuleDefinitionGenerator,
    ModuleAttributeOperatorGenerator,
    PrimitiveTypeGenerator,
    StructTypeGenerator
  }

  alias Hologram.Compiler.Helpers

  def generate(ast, context \\ [], opts \\ [])

  # TYPES

  def generate(%AtomType{value: value}, _, _) do
    PrimitiveTypeGenerator.generate(:atom, "'#{value}'")
  end

  def generate(%BooleanType{value: value}, _, _) do
    PrimitiveTypeGenerator.generate(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}, _, _) do
    PrimitiveTypeGenerator.generate(:integer, "#{value}")
  end

  def generate(%MapType{data: data}, context, _) do
    MapTypeGenerator.generate(data, context)
  end

  def generate(%StructType{module: module, data: data}, context, _) do
    StructTypeGenerator.generate(module, data, context)
  end

  def generate(%StringType{value: value}, _, _) do
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end

  # OPERATORS

  def generate(%AdditionOperator{left: left, right: right}, context, _) do
    AdditionOperatorGenerator.generate(left, right, context)
  end

  def generate(%DotOperator{left: left, right: right}, context, _) do
    DotOperatorGenerator.generate(left, right, context)
  end

  def generate(%ModuleAttributeOperator{name: name}, context, _) do
    ModuleAttributeOperatorGenerator.generate(name, context)
  end

  # DEFINITIONS

  def generate(%ModuleDefinition{name: name} = ast, _, _) do
    ModuleDefinitionGenerator.generate(ast, name)
  end

  # OTHER

  def generate(%FunctionCall{module: module, function: function, params: params}, context, _) do
    class = Helpers.class_name(module)

    params =
      Enum.map(params, fn param ->
        case param do
          %Variable{name: name} ->
            name

          _ ->
            generate(param, context)
        end
      end)
      |> Enum.join(", ")

    "#{class}.#{function}(#{params})"
  end

  def generate(%Variable{name: name}, _, boxed: true) do
    "{ type: 'variable', name: '#{name}' }"
  end

  def generate(%Variable{name: name}, _, _) do
    "#{name}"
  end
end
