# TODO: refactor & test

defmodule Hologram.Transpiler.Generator do
  alias Hologram.Transpiler.AST.{
    AtomType,
    BooleanType,
    DotOperator,
    IntegerType,
    ListType,
    MapType,
    StringType,
    StructType
  }

  alias Hologram.Transpiler.AST.AdditionOperator

  alias Hologram.Transpiler.AST.{Function, FunctionCall, MapAccess, Module, Variable}

  alias Hologram.Transpiler.{
    AdditionOperatorGenerator,
    DotOperatorGenerator,
    MapTypeGenerator,
    ModuleGenerator,
    PrimitiveTypeGenerator,
    StructTypeGenerator
  }

  alias Hologram.Transpiler.Helpers

  def generate(ast, opts \\ [])

  # TYPES

  def generate(%AtomType{value: value}, _) do
    PrimitiveTypeGenerator.generate(:atom, "'#{value}'")
  end

  def generate(%BooleanType{value: value}, _) do
    PrimitiveTypeGenerator.generate(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}, _) do
    PrimitiveTypeGenerator.generate(:integer, "#{value}")
  end

  def generate(%MapType{data: data}, _) do
    MapTypeGenerator.generate(data)
  end

  def generate(%StructType{module: module, data: data}, _) do
    StructTypeGenerator.generate(module, data)
  end

  def generate(%StringType{value: value}, _) do
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end

  # OPERATORS

  def generate(%AdditionOperator{left: left, right: right}, _) do
    AdditionOperatorGenerator.generate(left, right)
  end

  def generate(%DotOperator{left: left, right: right}, _) do
    DotOperatorGenerator.generate(left, right)
  end

  # OTHER

  def generate(%Module{name: name} = ast, _) do
    ModuleGenerator.generate(ast, name)
  end

  def generate(%Variable{name: name}, boxed: true) do
    "{ type: 'variable', name: '#{name}' }"
  end

  def generate(%Variable{name: name}, _) do
    "#{name}"
  end

  def generate(%FunctionCall{module: module, function: function, params: params}, _) do
    class = Helpers.class_name(module)

    params =
      Enum.map(params, fn param ->
        case param do
          %Variable{name: name} ->
            name

          _ ->
            generate(param)
        end
      end)
      |> Enum.join(", ")

    "#{class}.#{function}(#{params})"
  end
end
