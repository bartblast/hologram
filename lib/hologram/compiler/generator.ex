defmodule Hologram.Compiler.Generator do
  alias Hologram.Compiler.{Context, Helpers}

  alias Hologram.Compiler.{
    AdditionOperatorGenerator,
    DotOperatorGenerator,
    FunctionCallGenerator,
    MapTypeGenerator,
    ModuleDefinitionGenerator,
    ModuleAttributeOperatorGenerator,
    PrimitiveTypeGenerator,
    SigilHGenerator,
    StructTypeGenerator
  }

  alias Hologram.Compiler.IR.{
    AccessOperator,
    AdditionOperator,
    AtomType,
    BooleanType,
    DotOperator,
    FunctionCall,
    FunctionDefinition,
    IntegerType,
    ListType,
    MapType,
    ModuleAttributeOperator,
    ModuleDefinition,
    StringType,
    StructType,
    Variable
  }

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

  def generate(%MapType{data: data}, %Context{} = context, opts) do
    MapTypeGenerator.generate(data, context, opts)
  end

  def generate(%StringType{value: value}, _, _) do
    PrimitiveTypeGenerator.generate(:string, "'#{value}'")
  end

  def generate(%StructType{module: module, data: data}, %Context{} = context, opts) do
    StructTypeGenerator.generate(module, data, context, opts)
  end

  # OPERATORS

  def generate(%AdditionOperator{left: left, right: right}, %Context{} = context, _) do
    AdditionOperatorGenerator.generate(left, right, context)
  end

  def generate(%DotOperator{left: left, right: right}, %Context{} = context, _) do
    DotOperatorGenerator.generate(left, right, context)
  end

  def generate(%ModuleAttributeOperator{name: name}, %Context{} = context, _) do
    ModuleAttributeOperatorGenerator.generate(name, context)
  end

  # DEFINITIONS

  def generate(%ModuleDefinition{name: name} = ir, _, _) do
    ModuleDefinitionGenerator.generate(ir, name)
  end

  # OTHER

  def generate(%FunctionCall{function: :sigil_H} = ir, %Context{} = context, _) do
    SigilHGenerator.generate(ir, context)
  end

  def generate(%FunctionCall{module: module, function: function, params: params}, %Context{} = context, _) do
    FunctionCallGenerator.generate(module, function, params, context)
  end

  def generate(%Variable{name: name}, _, placeholder: true) do
    "{ type: 'placeholder' }"
  end

  def generate(%Variable{name: name}, _, _) do
    "#{name}"
  end
end
