defmodule Hologram.Compiler.Generator do
  alias Hologram.Compiler.Context

  alias Hologram.Compiler.{
    AdditionOperatorGenerator,
    DotOperatorGenerator,
    FunctionCallGenerator,
    ListTypeGenerator,
    MapTypeGenerator,
    ModuleDefinitionGenerator,
    ModuleAttributeOperatorGenerator,
    PrimitiveTypeGenerator,
    SigilHGenerator,
    StructTypeGenerator,
    TupleTypeGenerator,
  }

  alias Hologram.Compiler.IR.{
    AdditionOperator,
    AtomType,
    BooleanType,
    DotOperator,
    FunctionCall,
    IntegerType,
    ListType,
    MapType,
    ModuleAttributeOperator,
    ModuleDefinition,
    StringType,
    StructType,
    TupleType,
    Variable
  }

  def generate(ir, context, opts \\ [])

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

  def generate(%ListType{data: data}, %Context{} = context, opts) do
    ListTypeGenerator.generate(data, context, opts)
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

  def generate(%TupleType{data: data}, %Context{} = context, opts) do
    TupleTypeGenerator.generate(data, context, opts)
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

  def generate(%ModuleDefinition{module: module} = ir, %Context{} = context, _) do
    ModuleDefinitionGenerator.generate(ir, module, context)
  end

  # OTHER

  def generate(%FunctionCall{function: :sigil_H} = ir, %Context{} = context, _) do
    SigilHGenerator.generate(ir, context)
  end

  def generate(%FunctionCall{module: module, function: function, params: params}, %Context{} = context, _) do
    FunctionCallGenerator.generate(module, function, params, context)
  end

  def generate(%Variable{}, _, placeholder: true) do
    "{ type: 'placeholder' }"
  end

  def generate(%Variable{name: name}, _, _) do
    "#{name}"
  end
end
