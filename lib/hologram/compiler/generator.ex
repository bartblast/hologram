defmodule Hologram.Compiler.Generator do
  alias Hologram.Compiler.{Context, Encoder, Opts}

  alias Hologram.Compiler.{
    DotOperatorGenerator,
    FunctionCallGenerator,
    ModuleDefinitionGenerator,
    ModuleAttributeOperatorGenerator,
    SigilHGenerator,
    StructTypeGenerator,
  }

  alias Hologram.Compiler.IR.{
    DotOperator,
    FunctionCall,
    ModuleAttributeOperator,
    ModuleDefinition,
    StructType,
  }

  def generate(ir, context, opts)

  # OPERATORS

  def generate(%ModuleAttributeOperator{name: name}, %Context{} = context, %Opts{} = opts) do
    ModuleAttributeOperatorGenerator.generate(name, context, opts)
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

  # TODO: use Encoder protocol instead all of these generate/3 functions and remove this module
  def generate(ir, %Context{} = context, %Opts{} = opts) do
    Encoder.encode(ir, context, opts)
  end
end
