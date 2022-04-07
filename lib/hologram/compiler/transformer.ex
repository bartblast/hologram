defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.{Context, Reflection}

  alias Hologram.Compiler.{
    AccessOperatorTransformer,
    AdditionOperatorTransformer,
    AliasDirectiveTransformer,
    AnonymousFunctionTypeTransformer,
    BinaryTypeTransformer,
    BlockTransformer,
    CaseExpressionTransformer,
    DivisionOperatorTransformer,
    DotOperatorTransformer,
    EqualToOperatorTransformer,
    FunctionDefinitionTransformer,
    FunctionCallTransformer,
    IfExpressionTransformer,
    ImportDirectiveTransformer,
    ListConcatenationOperatorTransformer,
    ListSubtractionOperatorTransformer,
    ListTypeTransformer,
    MacroDefinitionTransformer,
    MapTypeTransformer,
    MatchOperatorTransformer,
    MembershipOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    ModuleTypeTransformer,
    MultiplicationOperatorTransformer,
    QuoteTransformer,
    PipeOperatorTransformer,
    RelaxedBooleanAndOperatorTransformer,
    RelaxedBooleanNotOperatorTransformer,
    RelaxedBooleanOrOperatorTransformer,
    RequireDirectiveTransformer,
    StrictBooleanAndOperatorTransformer,
    StructTypeTransformer,
    SubtractionOperatorTransformer,
    TypeOperatorTransformer,
    TupleTypeTransformer,
    UnaryNegativeOperatorTransformer,
    UnaryPositiveOperatorTransformer,
    UnquoteTransformer,
    UseDirectiveTransformer
  }

  alias Hologram.Compiler.IR.{
    AtomType,
    BooleanType,
    IntegerType,
    ModuleAttributeOperator,
    ModulePseudoVariable,
    NilType,
    ProtocolDefinition,
    StringType,
    Typespec,
    Variable
  }

  # TYPES

  def transform({:fn, _, _} = ast, %Context{} = context) do
    AnonymousFunctionTypeTransformer.transform(ast, context)
  end

  def transform(ast, %Context{} = context) when is_atom(ast) and ast not in [nil, false, true] do
    if Reflection.module?(ast) do
      ModuleTypeTransformer.transform(ast, context)
    else
      %AtomType{value: ast}
    end
  end

  def transform({:<<>>, _, _} = ast, %Context{} = context) do
    BinaryTypeTransformer.transform(ast, context)
  end

  def transform(ast, _) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast, _) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform(ast, %Context{} = context) when is_list(ast) do
    ListTypeTransformer.transform(ast, context)
  end

  def transform({:%{}, _, _} = ast, %Context{} = context) do
    MapTypeTransformer.transform(ast, context)
  end

  def transform({:__aliases__, _, _} = ast, %Context{} = context) do
    ModuleTypeTransformer.transform(ast, context)
  end

  def transform(nil, _) do
    %NilType{}
  end

  def transform(ast, _) when is_binary(ast) do
    %StringType{value: ast}
  end

  def transform({:%, _, _} = ast, %Context{} = context) do
    StructTypeTransformer.transform(ast, context)
  end

  def transform({:{}, _, _} = ast, %Context{} = context) do
    TupleTypeTransformer.transform(ast, context)
  end

  def transform({_, _} = ast, %Context{} = context) do
    TupleTypeTransformer.transform(ast, context)
  end

  # OPERATORS

  def transform({{:., _, [Access, :get]}, _, _} = ast, %Context{} = context) do
    AccessOperatorTransformer.transform(ast, context)
  end

  # needs to be defined before binary addition operator
  def transform({:+, _, [_]} = ast, %Context{} = context) do
    UnaryPositiveOperatorTransformer.transform(ast, context)
  end

  def transform({:+, _, _} = ast, %Context{} = context) do
    AdditionOperatorTransformer.transform(ast, context)
  end

  def transform({:/, _, _} = ast, %Context{} = context) do
    DivisionOperatorTransformer.transform(ast, context)
  end

  def transform({{:., _, _}, [no_parens: true, line: _], _} = ast, %Context{} = context) do
    DotOperatorTransformer.transform(ast, context)
  end

  def transform({:==, _, _} = ast, %Context{} = context) do
    EqualToOperatorTransformer.transform(ast, context)
  end

  def transform({:++, _, _} = ast, %Context{} = context) do
    ListConcatenationOperatorTransformer.transform(ast, context)
  end

  def transform({:--, _, _} = ast, %Context{} = context) do
    ListSubtractionOperatorTransformer.transform(ast, context)
  end

  def transform({:=, _, _} = ast, %Context{} = context) do
    MatchOperatorTransformer.transform(ast, context)
  end

  def transform({:in, _, _} = ast, %Context{} = context) do
    MembershipOperatorTransformer.transform(ast, context)
  end

  # needs to be defined before module attribute operator
  def transform({:@, _, [{:spec, _, [{:"::", _, _}]}]}, _) do
    %Typespec{}
  end

  def transform({:@, _, [{name, _, ast}]}, _) when not is_list(ast) do
    %ModuleAttributeOperator{name: name}
  end

  def transform({:*, _, _} = ast, %Context{} = context) do
    MultiplicationOperatorTransformer.transform(ast, context)
  end

  def transform({:|>, _, _} = ast, %Context{} = context) do
    PipeOperatorTransformer.transform(ast, context)
  end

  def transform({:&&, _, _} = ast, %Context{} = context) do
    RelaxedBooleanAndOperatorTransformer.transform(ast, context)
  end

  def transform({:__block__, _, [{:!, _, _}]} = ast, %Context{} = context) do
    RelaxedBooleanNotOperatorTransformer.transform(ast, context)
  end

  def transform({:!, _, _} = ast, %Context{} = context) do
    RelaxedBooleanNotOperatorTransformer.transform(ast, context)
  end

  def transform({:||, _, _} = ast, %Context{} = context) do
    RelaxedBooleanOrOperatorTransformer.transform(ast, context)
  end

  def transform({:and, _, _} = ast, %Context{} = context) do
    StrictBooleanAndOperatorTransformer.transform(ast, context)
  end

  # needs to be defined before binary subtraction operator
  def transform({:-, _, [_]} = ast, %Context{} = context) do
    UnaryNegativeOperatorTransformer.transform(ast, context)
  end

  def transform({:-, _, _} = ast, %Context{} = context) do
    SubtractionOperatorTransformer.transform(ast, context)
  end

  def transform({:"::", _, _} = ast, %Context{} = context) do
    TypeOperatorTransformer.transform(ast, context)
  end

  # DEFINITIONS

  def transform({:def, _, _} = ast, %Context{} = context) do
    FunctionDefinitionTransformer.transform(ast, context)
  end

  def transform({:defp, _, _} = ast, %Context{} = context) do
    FunctionDefinitionTransformer.transform(ast, context)
  end

  def transform({:defmacro, _, _} = ast, %Context{} = context) do
    MacroDefinitionTransformer.transform(ast, context)
  end

  def transform({:defmodule, _, _} = ast, _) do
    ModuleDefinitionTransformer.transform(ast)
  end

  # DEFER: implement
  def transform({:defprotocol, _, _}, _) do
    %ProtocolDefinition{}
  end

  def transform({:@, _, [{_, _, exprs}]} = ast, %Context{} = context) when is_list(exprs) do
    ModuleAttributeDefinitionTransformer.transform(ast, context)
  end

  # DIRECTIVES

  def transform({:alias, _, _} = ast, _) do
    AliasDirectiveTransformer.transform(ast)
  end

  def transform({:import, _, _} = ast, _) do
    ImportDirectiveTransformer.transform(ast)
  end

  def transform({:require, _, _} = ast, _) do
    RequireDirectiveTransformer.transform(ast)
  end

  def transform({:use, _, _} = ast, _) do
    UseDirectiveTransformer.transform(ast)
  end

  # CONTROL FLOW

  def transform({:case, _, _} = ast, %Context{} = context) do
    CaseExpressionTransformer.transform(ast, context)
  end

  def transform({:if, _, _} = ast, %Context{} = context) do
    IfExpressionTransformer.transform(ast, context)
  end

  # OTHER

  def transform({:__block__, _, _} = ast, %Context{} = context) do
    BlockTransformer.transform(ast, context)
  end

  def transform({{:., _, _}, _, _} = ast, %Context{} = context) do
    FunctionCallTransformer.transform(ast, context)
  end

  def transform({:quote, _, _} = ast, %Context{} = context) do
    QuoteTransformer.transform(ast, context)
  end

  def transform({:unquote, _, _} = ast, %Context{} = context) do
    UnquoteTransformer.transform(ast, context)
  end

  # needs to be defined before variable case
  def transform({:__MODULE__, _, _}, _) do
    %ModulePseudoVariable{}
  end

  def transform({name, _, nil}, _) when is_atom(name) do
    %Variable{name: name}
  end

  def transform({name, _, module}, _) when is_atom(name) and is_atom(module) do
    %Variable{name: name}
  end

  # needs to be defined after variable case
  def transform({function, _, _} = ast, %Context{} = context) when is_atom(function) do
    FunctionCallTransformer.transform(ast, context)
  end
end
