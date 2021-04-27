# TODO: refactor

defmodule Hologram.Transpiler.Transformer do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, MatchOperator, StringType}
  alias Hologram.Transpiler.AST.MatchOperator
  alias Hologram.Transpiler.AST.{Alias, Import, ModuleAttribute, Variable}
  alias Hologram.Transpiler.Binder
  alias Hologram.Transpiler.{AliasTransformer, FunctionTransformer, FunctionCallTransformer, ListTypeTransformer, MapTypeTransformer, ModuleTransformer, StructTypeTransformer}

  def transform(ast, module \\ nil, imports \\ [], aliases \\ [])

  # PRIMITIVE TYPES

  # boolean must be before atom
  def transform(ast, _module, _imports, _aliases) when is_boolean(ast) do
    %BooleanType{value: ast}
  end

  def transform(ast, _module, _imports, _aliases) when is_atom(ast) do
    %AtomType{value: ast}
  end

  def transform(ast, _module, _imports, _aliases) when is_integer(ast) do
    %IntegerType{value: ast}
  end

  def transform(ast, _module, _imports, _aliases) when is_binary(ast) do
    %StringType{value: ast}
  end

  # DATA STRUCTURES

  def transform(ast, module, imports, aliases) when is_list(ast) do
    ListTypeTransformer.transform(ast, module, imports, aliases)
  end

  def transform({:%{}, _, ast}, module, imports, aliases) do
    MapTypeTransformer.transform(ast, module, imports, aliases)
  end

  def transform({:%, _, [{_, _, struct_module}, ast]}, current_module, imports, aliases) do
    StructTypeTransformer.transform(ast, struct_module, current_module, imports, aliases)
  end

  # OPERATORS

  def transform({:=, _, [left, right]}, module, imports, aliases) do
    left = transform(left, module, imports, aliases)

    %MatchOperator{
      bindings: Binder.bind(left),
      left: left,
      right: transform(right, module, imports, aliases)
    }
  end

  # DIRECTIVES

  def transform({:alias, _, ast}, _, _, _) do
    AliasTransformer.transform(ast)
  end

  def transform(
        {:import, _, [{:__aliases__, _, imported_module}]},
        _current_module,
        _imports,
        _aliases
      ) do
    %Import{module: imported_module}
  end

  # OTHER

  def transform({:defmodule, _, [_, [do: {:__block__, _, _}]]} = ast, _module, _imports, _aliases) do
    ModuleTransformer.transform(ast)
  end

  def transform({:def, _, [{name, _, params}, [do: {:__block__, _, body}]]}, module, imports, aliases) do
    FunctionTransformer.transform(name, params, body, module, imports, aliases)
  end

  def transform({name, _, nil}, _module, _imports, _aliases) when is_atom(name) do
    %Variable{name: name}
  end

  def transform({:@, _, [{name, _, _}]}, _module, _imports, _aliases) do
    %ModuleAttribute{name: name}
  end

  def transform({function, _, params}, module, imports, aliases) when is_atom(function) do
    FunctionCallTransformer.transform([], function, params, module, imports, aliases)
  end

  def transform(
        {{:., _, [{:__aliases__, _, called_module}, function]}, _, params},
        current_module,
        imports,
        aliases
      ) do
    FunctionCallTransformer.transform(called_module, function, params, current_module, imports, aliases)
  end
end
