defmodule Hologram.Compiler.Generator do
  alias Hologram.Compiler.{Context, Encoder, Helpers, Opts}

  alias Hologram.Compiler.{
    BinaryTypeEncoder,
    DotOperatorGenerator,
    FunctionCallGenerator,
    ListTypeGenerator,
    MapTypeGenerator,
    ModuleDefinitionGenerator,
    ModuleAttributeOperatorGenerator,
    SigilHGenerator,
    StructTypeGenerator,
    TupleTypeGenerator,
    TypeOperatorEncoder
  }

  alias Hologram.Compiler.IR.{
    BinaryType,
    BooleanType,
    DotOperator,
    FunctionCall,
    IntegerType,
    ListType,
    MapType,
    ModuleAttributeOperator,
    ModuleDefinition,
    ModuleType,
    StructType,
    TupleType,
    TypeOperator,
    Variable
  }

  def generate(ir, context, opts)

  # TYPES

  def generate(%BinaryType{parts: parts}, %Context{} = context, %Opts{} = opts) do
    BinaryTypeEncoder.encode(parts, context, opts)
  end

  def generate(%BooleanType{value: value}, _, _) do
    Hologram.Compiler.Encoder.Commons.encode_primitive_type(:boolean, "#{value}")
  end

  def generate(%IntegerType{value: value}, _, _) do
    Hologram.Compiler.Encoder.Commons.encode_primitive_type(:integer, "#{value}")
  end

  def generate(%ListType{data: data}, %Context{} = context, %Opts{} = opts) do
    ListTypeGenerator.generate(data, context, opts)
  end

  def generate(%MapType{data: data}, %Context{} = context, %Opts{} = opts) do
    MapTypeGenerator.generate(data, context, opts)
  end

  def generate(%ModuleType{module: module}, _, _) do
    "{ type: 'module', className: '#{Helpers.class_name(module)}' }"
  end

  def generate(%StructType{module: module, data: data}, %Context{} = context, %Opts{} = opts) do
    StructTypeGenerator.generate(module, data, context, opts)
  end

  def generate(%TupleType{data: data}, %Context{} = context, %Opts{} = opts) do
    TupleTypeGenerator.generate(data, context, opts)
  end

  # OPERATORS

  def generate(%DotOperator{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    DotOperatorGenerator.generate(left, right, context, opts)
  end

  def generate(%ModuleAttributeOperator{name: name}, %Context{} = context, %Opts{} = opts) do
    ModuleAttributeOperatorGenerator.generate(name, context, opts)
  end

  def generate(%TypeOperator{left: left, right: right}, %Context{} = context, %Opts{} = opts) do
    TypeOperatorEncoder.encode(left, right, context, opts)
  end

  # DEFINITIONS

  def generate(%ModuleDefinition{module: module} = ir, _, %Opts{} = opts) do
    ModuleDefinitionGenerator.generate(ir, module, opts)
  end

  # OTHER

  def generate(%FunctionCall{function: :sigil_H} = ir, %Context{} = context, _) do
    SigilHGenerator.generate(ir, context)
  end

  def generate(
        %FunctionCall{module: module, function: function, params: params},
        %Context{} = context,
        %Opts{} = opts
      ) do
    FunctionCallGenerator.generate(module, function, params, context, opts)
  end

  def generate(%Variable{}, _, %Opts{placeholder: true}) do
    "{ type: 'placeholder' }"
  end

  def generate(%Variable{name: name}, _, _) do
    "#{name}"
  end

  # TODO: use Encoder protocol instead all of these generate/3 functions and remove this module
  def generate(ir, %Context{} = context, %Opts{} = opts) do
    Encoder.encode(ir, context, opts)
  end
end
