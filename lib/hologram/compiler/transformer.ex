defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.IR.{
    AtomType,
    BooleanType,
    IntegerType,
    ModuleAttributeOperator,
    ModuleMacro,
    NilType,
    StringType,
    Variable
  }

  alias Hologram.Compiler.{
    AdditionOperatorTransformer,
    AliasTransformer,
    AnonymousFunctionTypeTransformer,
    BinaryTypeTransformer,
    DotOperatorTransformer,
    EqualToOperatorTransformer,
    FunctionDefinitionTransformer,
    FunctionCallTransformer,
    IfExpressionTransformer,
    ImportTransformer,
    ListTypeTransformer,
    MacroDefinitionTransformer,
    MapTypeTransformer,
    MatchOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    ModuleTypeTransformer,
    QuoteTransformer,
    PipeOperatorTransformer,
    RequireDirectiveTransformer,
    StructTypeTransformer,
    TypeOperatorTransformer,
    TupleTypeTransformer,
    UnquoteTransformer,
    UseDirectiveTransformer
  }

  alias Hologram.Compiler.{Context, Reflection}

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

  def transform({:<<>>, _, parts}, %Context{} = context) do
    BinaryTypeTransformer.transform(parts, context)
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

  def transform({:%{}, _, ast}, %Context{} = context) do
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

  def transform({:%, _, [{_, _, module_segs}, ast]}, %Context{} = context) do
    StructTypeTransformer.transform(ast, module_segs, context)
  end

  def transform({:{}, _, ast}, %Context{} = context) do
    TupleTypeTransformer.transform(ast, context)
  end

  def transform({_, _} = ast, %Context{} = context) do
    TupleTypeTransformer.transform(ast, context)
  end

  # OPERATORS

  def transform({:+, _, [left, right]}, %Context{} = context) do
    AdditionOperatorTransformer.transform(left, right, context)
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}, %Context{} = context) do
    DotOperatorTransformer.transform(left, right, context)
  end

  def transform({:==, _, _} = ast, %Context{} = context) do
    EqualToOperatorTransformer.transform(ast, context)
  end

  def transform({:=, _, [left, right]}, %Context{} = context) do
    MatchOperatorTransformer.transform(left, right, context)
  end

  def transform({:@, _, [{name, _, ast}]}, _) when not is_list(ast) do
    %ModuleAttributeOperator{name: name}
  end

  def transform({:|>, _, _,} = ast, %Context{} = context) do
    PipeOperatorTransformer.transform(ast, context)
  end

  def transform({:"::", _, ast}, %Context{} = context) do
    TypeOperatorTransformer.transform(ast, context)
  end

  # DEFINITIONS

  def transform({:def, _, _} = ast, %Context{} = context) do
    FunctionDefinitionTransformer.transform(ast, context)
  end

  def transform({:defmacro, _, _} = ast, %Context{} = context) do
    MacroDefinitionTransformer.transform(ast, context)
  end

  def transform({:defmodule, _, _} = ast, _) do
    ModuleDefinitionTransformer.transform(ast)
  end

  def transform({:@, _, [{_, _, exprs}]} = ast, %Context{} = context) when is_list(exprs) do
    ModuleAttributeDefinitionTransformer.transform(ast, context)
  end

  # DIRECTIVES

  def transform({:alias, _, ast}, _) do
    AliasTransformer.transform(ast)
  end

  def transform({:import, _, ast}, _) do
    ImportTransformer.transform(ast)
  end

  def transform({:require, _, ast}, _) do
    RequireDirectiveTransformer.transform(ast)
  end

  def transform({:use, _, [{:__aliases__, _, module_segs}]}, _) do
    UseDirectiveTransformer.transform(module_segs)
  end

  # CONTROL FLOW

  def transform({:if, _, _} = ast, %Context{} = context) do
    IfExpressionTransformer.transform(ast, context)
  end

  # OTHER

  def transform({{:., _, _}, _, _} = ast, %Context{} = context) do
    FunctionCallTransformer.transform(ast, context)
  end

  def transform({:quote, _, _} = ast, %Context{} = context) do
    QuoteTransformer.transform(ast, context)
  end

  def transform({:unquote, _, _} = ast, %Context{} = context) do
    UnquoteTransformer.transform(ast, context)
  end

  # this needs to be defined before variable case
  def transform({:__MODULE__, _, _}, _) do
    %ModuleMacro{}
  end

  def transform({name, _, nil}, _) when is_atom(name) do
    %Variable{name: name}
  end

  def transform({name, _, module}, _) when is_atom(name) and is_atom(module) do
    %Variable{name: name}
  end

  # this needs to be defined after variable case
  def transform({function, _, _} = ast, %Context{} = context) when is_atom(function) do
    FunctionCallTransformer.transform(ast, context)
  end
end
