defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.IR.{
    AtomType,
    BooleanType,
    IntegerType,
    ModuleAttributeOperator,
    NotSupportedExpression,
    StringType,
    Variable
  }

  alias Hologram.Compiler.{
    AdditionOperatorTransformer,
    AliasTransformer,
    BinaryTypeTransformer,
    DotOperatorTransformer,
    FunctionDefinitionTransformer,
    FunctionCallTransformer,
    ImportTransformer,
    ListTypeTransformer,
    MacroDefinitionTransformer,
    MapTypeTransformer,
    MatchOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    ModuleTypeTransformer,
    RequireDirectiveTransformer,
    StructTypeTransformer,
    TypeOperatorTransformer,
    TupleTypeTransformer,
    UseDirectiveTransformer
  }

  alias Hologram.Compiler.Context

  # TYPES

  def transform(ast, _) when is_atom(ast) and ast not in [false, true] do
    %AtomType{value: ast}
  end

  def transform(ast, _) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast, _) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform({:__aliases__, _, module_segs}, %Context{} = context) do
    ModuleTypeTransformer.transform(module_segs, context)
  end

  def transform(ast, _) when is_binary(ast) do
    %StringType{value: ast}
  end

  def transform(ast, %Context{} = context) when is_list(ast) do
    ListTypeTransformer.transform(ast, context)
  end

  def transform({:%{}, _, ast}, %Context{} = context) do
    MapTypeTransformer.transform(ast, context)
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

  def transform({:<<>>, _, parts}, %Context{} = context) do
    BinaryTypeTransformer.transform(parts, context)
  end

  # OPERATORS

  def transform({:+, _, [left, right]}, %Context{} = context) do
    AdditionOperatorTransformer.transform(left, right, context)
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}, %Context{} = context) do
    DotOperatorTransformer.transform(left, right, context)
  end

  def transform({:=, _, [left, right]}, %Context{} = context) do
    MatchOperatorTransformer.transform(left, right, context)
  end

  def transform({:@, _, [{name, _, nil}]}, _) do
    %ModuleAttributeOperator{name: name}
  end

  def transform({:"::", _, ast}, %Context{} = context) do
    TypeOperatorTransformer.transform(ast, context)
  end

  # DEFINITIONS

  def transform({:def, _, [{name, _, params}, [do: {:__block__, _, body}]]}, %Context{} = context) do
    FunctionDefinitionTransformer.transform(name, params, body, context)
  end

  def transform({:defmacro, _, _} = ast, %Context{} = context) do
    MacroDefinitionTransformer.transform(ast, context)
  end

  def transform({:defmodule, _, _} = ast, _) do
    ModuleDefinitionTransformer.transform(ast)
  end

  def transform({:@, _, [{name, _, [ast]}]}, %Context{} = context) do
    ModuleAttributeDefinitionTransformer.transform(name, ast, context)
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

  # OTHER

  def transform({{:., _, [{:__aliases__, _, module_segs}, function]}, _, params}, %Context{} = context) do
    FunctionCallTransformer.transform(module_segs, function, params, context)
  end

  def transform({{:., _, [Kernel, :to_string]}, _, params}, %Context{} = context) do
    FunctionCallTransformer.transform([:Kernel], :to_string, params, context)
  end

  def transform({:quote, _, _} = ast, %Context{} = context) do
    QuoteTransformer.transform(ast, context)
  end

  def transform({function, _, params}, %Context{} = context) when is_atom(function) and is_list(params) do
    FunctionCallTransformer.transform([], function, params, context)
  end

  def transform({name, _, nil}, _) when is_atom(name) do
    %Variable{name: name}
  end

  # NOT SUPPORTED

  def transform({{:., _, [_, _]}, _, _} = ast, _) do
    %NotSupportedExpression{ast: ast, type: :erlang_function_call}
  end
end
