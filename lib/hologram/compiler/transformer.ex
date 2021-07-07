defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.IR.{
    AtomType,
    BooleanType,
    Import,
    IntegerType,
    ModuleAttributeOperator,
    StringType,
    UseDirective,
    Variable
  }

  alias Hologram.Compiler.{
    AdditionOperatorTransformer,
    AliasTransformer,
    DotOperatorTransformer,
    FunctionDefinitionTransformer,
    FunctionCallTransformer,
    ListTypeTransformer,
    MapTypeTransformer,
    MatchOperatorTransformer,
    ModuleAttributeDefinitionTransformer,
    ModuleDefinitionTransformer,
    StructTypeTransformer
  }

  def transform(ast, context \\ [module: [], imports: [], aliases: []])

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

  def transform(ast, _) when is_binary(ast) do
    %StringType{value: ast}
  end

  def transform(ast, context) when is_list(ast) do
    ListTypeTransformer.transform(ast, context)
  end

  def transform({:%{}, _, ast}, context) do
    MapTypeTransformer.transform(ast, context)
  end

  def transform({:%, _, [{_, _, module}, ast]}, context) do
    StructTypeTransformer.transform(ast, module, context)
  end

  # OPERATORS

  def transform({:+, _, [left, right]}, context) do
    AdditionOperatorTransformer.transform(left, right, context)
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}, context) do
    DotOperatorTransformer.transform(left, right, context)
  end

  def transform({:=, _, [left, right]}, context) do
    MatchOperatorTransformer.transform(left, right, context)
  end

  def transform({:@, _, [{name, _, nil}]}, _) do
    %ModuleAttributeOperator{name: name}
  end

  # DEFINITIONS

  def transform({:def, _, [{name, _, params}, [do: {:__block__, _, body}]]}, context) do
    FunctionDefinitionTransformer.transform(name, params, body, context)
  end

  def transform({:defmodule, _, _} = ast, _) do
    ModuleDefinitionTransformer.transform(ast)
  end

  def transform({:@, _, [{name, _, [ast]}]}, context) do
    ModuleAttributeDefinitionTransformer.transform(name, ast, context)
  end

  # DIRECTIVES

  def transform({:alias, _, ast}, _) do
    AliasTransformer.transform(ast)
  end

  def transform({:import, _, [{:__aliases__, _, module}]}, _) do
    %Import{module: module, only: []}
  end

  def transform({:import, _, [{:__aliases__, _, module}, [only: only]]}, _) do
    %Import{module: module, only: only}
  end

  def transform({:use, _, [{:__aliases__, _, module}]}, _) do
    %UseDirective{module: module}
  end

  # OTHER

  def transform({{:., _, [{:__aliases__, _, module}, function]}, _, params}, context) do
    FunctionCallTransformer.transform(module, function, params, context)
  end

  def transform({function, _, params}, context) when is_atom(function) and is_list(params) do
    FunctionCallTransformer.transform([], function, params, context)
  end

  def transform({name, _, nil}, _) when is_atom(name) do
    %Variable{name: name}
  end
end
