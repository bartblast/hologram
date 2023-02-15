defmodule Hologram.Compiler.OverhaulTransformer do
  alias Hologram.Compiler.IR

  alias Hologram.Compiler.{
    AliasDirectiveTransformer,
    CaseExpressionTransformer,
    ForExpressionTransformer,
    IfExpressionTransformer,
    ImportDirectiveTransformer,
    ModuleDefinitionTransformer,
    QuoteTransformer,
    RequireDirectiveTransformer,
    StrictBooleanAndOperatorTransformer,
    SubtractionOperatorTransformer,
    TypeOperatorTransformer,
    UnaryNegativeOperatorTransformer,
    UnquoteTransformer,
    UseDirectiveTransformer
  }

  alias Hologram.Compiler.IR

  alias Hologram.Compiler.IR.{
    ProtocolDefinition
  }

  # OPERATORS

  # must be defined before binary subtraction operator
  def transform({:-, _, [_]} = ast) do
    UnaryNegativeOperatorTransformer.transform(ast)
  end

  def transform({:-, _, _} = ast) do
    SubtractionOperatorTransformer.transform(ast)
  end

  def transform({:"::", _, _} = ast) do
    TypeOperatorTransformer.transform(ast)
  end

  # DEFINITIONS

  def transform({:defmacro, _, _}) do
    %IR.IgnoredExpression{type: :macro_definition}
  end

  def transform({:defmodule, _, _} = ast) do
    ModuleDefinitionTransformer.transform(ast)
  end

  # TODO: implement
  def transform({:defprotocol, _, _}) do
    %ProtocolDefinition{}
  end

  # DIRECTIVES

  def transform({:alias, _, _} = ast) do
    AliasDirectiveTransformer.transform(ast)
  end

  def transform({:import, _, _} = ast) do
    ImportDirectiveTransformer.transform(ast)
  end

  def transform({:require, _, _} = ast) do
    RequireDirectiveTransformer.transform(ast)
  end

  def transform({:use, _, _} = ast) do
    UseDirectiveTransformer.transform(ast)
  end

  # CONTROL FLOW

  def transform({:case, _, _} = ast) do
    CaseExpressionTransformer.transform(ast)
  end

  def transform({:for, _, _} = ast) do
    ForExpressionTransformer.transform(ast)
  end

  def transform({:if, _, _} = ast) do
    IfExpressionTransformer.transform(ast)
  end

  # OTHER

  def transform({:quote, _, _} = ast) do
    QuoteTransformer.transform(ast)
  end

  def transform({:unquote, _, _} = ast) do
    UnquoteTransformer.transform(ast)
  end
end
