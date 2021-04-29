# TODO: refactor

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

  alias Hologram.Transpiler.AST.{Function, FunctionCall, MapAccess, Module, Variable}

  alias Hologram.Transpiler.{
    DotOperatorGenerator,
    MapTypeGenerator,
    ModuleGenerator,
    PrimitiveTypeGenerator,
    StructTypeGenerator
  }

  alias Hologram.Transpiler.Helpers

  # TYPES

  def generate(%AtomType{value: value}) do
    PrimitiveTypeGenerator.generate(:atom, "'#{value}'")
  end

  def generate(%BooleanType{value: value}) do
    PrimitiveTypeGenerator.generate(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}) do
    PrimitiveTypeGenerator.generate(:integer, "#{value}")
  end

  def generate(%MapType{data: data}) do
    MapTypeGenerator.generate(data)
  end

  def generate(%StructType{module: module, data: data}) do
    StructTypeGenerator.generate(module, data)
  end

  def generate(%StringType{value: value}) do
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end

  # OPERATORS

  def generate(%DotOperator{left: left, right: right}) do
    DotOperatorGenerator.generate(left, right)
  end

  # OTHER

  def generate(%Module{name: name} = ast) do
    ModuleGenerator.generate(ast, name)
  end

  def generate(%Variable{name: name}) do
    "{ type: 'variable', name: '#{name}' }"
  end

  def generate(%FunctionCall{module: module, function: function, params: params}) do
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
