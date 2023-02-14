defmodule Hologram.Compiler.OverhaulTransformer do
  alias Hologram.Compiler.IR

  alias Hologram.Compiler.{
    AliasDirectiveTransformer,
    BinaryTypeTransformer,
    CallTransformer,
    CaseExpressionTransformer,
    EqualToOperatorTransformer,
    ForExpressionTransformer,
    FunctionDefinitionTransformer,
    IfExpressionTransformer,
    ImportDirectiveTransformer,
    MembershipOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    MultiplicationOperatorTransformer,
    NotEqualToOperatorTransformer,
    QuoteTransformer,
    PipeOperatorTransformer,
    RelaxedBooleanAndOperatorTransformer,
    RelaxedBooleanNotOperatorTransformer,
    RelaxedBooleanOrOperatorTransformer,
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
    ProtocolDefinition,
    Typespec
  }

  # OPERATORS

  def transform({{:., _, _}, _, _} = ast) do
    DotOperatorTransformer.transform(ast)
  end

  def transform({:in, _, _} = ast) do
    MembershipOperatorTransformer.transform(ast)
  end

  # must be defined before module attribute operator
  def transform({:@, _, [{:spec, _, [{:"::", _, _}]}]}) do
    %Typespec{}
  end

  def transform({:*, _, _} = ast) do
    MultiplicationOperatorTransformer.transform(ast)
  end

  def transform({:!=, _, _} = ast) do
    NotEqualToOperatorTransformer.transform(ast)
  end

  def transform({:|>, _, _} = ast) do
    PipeOperatorTransformer.transform(ast)
  end

  def transform({:&&, _, _} = ast) do
    RelaxedBooleanAndOperatorTransformer.transform(ast)
  end

  def transform({:__block__, _, [{:!, _, _}]} = ast) do
    RelaxedBooleanNotOperatorTransformer.transform(ast)
  end

  def transform({:!, _, _} = ast) do
    RelaxedBooleanNotOperatorTransformer.transform(ast)
  end

  def transform({:||, _, _} = ast) do
    RelaxedBooleanOrOperatorTransformer.transform(ast)
  end

  def transform({:and, _, _} = ast) do
    StrictBooleanAndOperatorTransformer.transform(ast)
  end

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

  # TYPES

  def transform({:<<>>, _, _} = ast) do
    BinaryTypeTransformer.transform(ast)
  end

  # DEFINITIONS

  def transform({:def, _, _} = ast) do
    FunctionDefinitionTransformer.transform(ast)
  end

  def transform({:defp, _, _} = ast) do
    FunctionDefinitionTransformer.transform(ast)
  end

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

  def transform({:@, _, [{_, _, exprs}]} = ast) when is_list(exprs) do
    ModuleAttributeDefinitionTransformer.transform(ast)
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

  def transform({name, _, args} = ast)
      when is_atom(name) and is_list(args) do
    CallTransformer.transform(ast)
  end

  def transform({_, [context: _, imports: _], _} = ast) do
    CallTransformer.transform(ast)
  end
end
