# TODO: refactor

defmodule Hologram.Transpiler.Transformer do
  alias Hologram.Transpiler.AST.{AtomType, BooleanType, IntegerType, StringType}
  alias Hologram.Transpiler.AST.{ListType, MapType, StructType}
  alias Hologram.Transpiler.AST.MatchOperator
  alias Hologram.Transpiler.AST.MapAccess
  alias Hologram.Transpiler.AST.{Alias, Call, Function, Import, Module, ModuleAttribute, Variable}
  alias Hologram.Transpiler.Expander
  alias Hologram.Transpiler.Transformers.{CallTransformer, ListTypeTransformer}

  @eliminated_functions [render: 1]

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
    data =
      Enum.map(ast, fn {k, v} ->
        {transform(k, module, imports, aliases), transform(v, module, imports, aliases)}
      end)

    %MapType{data: data}
  end

  def transform({:%, _, [{_, _, module}, ast]}, _module, imports, aliases) do
    data = transform(ast, module, imports, aliases).data

    key = List.last(module)

    module =
      if Map.has_key?(aliases, key) do
        aliases[key]
      else
        module
      end

    %StructType{module: module, data: data}
  end

  # OPERATORS

  def transform({:=, _, [left, right]}, module, imports, aliases) do
    left = transform(left, module, imports, aliases)

    %MatchOperator{
      bindings: aggregate_bindings(left),
      left: left,
      right: transform(right, module, imports, aliases)
    }
  end

  defp aggregate_bindings(_, path \\ [])

  defp aggregate_bindings(%Variable{name: name} = var, path) do
    [[var] ++ path]
  end

  defp aggregate_bindings(%MapType{data: data}, path) do
    Enum.reduce(data, [], fn {k, v}, acc ->
      acc ++ aggregate_bindings(v, path ++ [%MapAccess{key: k}])
    end)
  end

  defp aggregate_bindings(_, path) do
    []
  end

  # DIRECTIVES

  def transform(
        {:alias, _, [{:__aliases__, _, aliased_module}]},
        _current_module,
        _imports,
        _aliases
      ) do
    %Alias{module: aliased_module}
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
    {:defmodule, _, [{:__aliases__, _, name}, [do: {:__block__, _, block}]]} =
      Expander.expand(ast)

    build_module(name, block)
  end

  def transform({:defmodule, _, [_, [do: _]]} = ast, _module, _imports, _aliases) do
    {:defmodule, _, [{:__aliases__, _, name}, [do: expr]]} = Expander.expand(ast)
    build_module(name, [expr])
  end

  def build_module(name, ast) do
    imports = aggregate_imports(ast)
    aliases = aggregate_aliases(ast)
    functions = aggregate_functions(ast, name, imports, aliases)

    %Module{name: name, imports: imports, aliases: aliases, functions: functions}
  end

  # TODO: check
  defp aggregate_aliases(ast) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:alias, _, _} ->
          acc ++ [transform(expr)]

        _ ->
          acc
      end
    end)
  end

  defp aggregate_functions(ast, module, imports, aliases) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:def, _, [{name, _, params}, _]} ->
          if eliminated_function?(name, params) do
            acc
          else
            acc ++ [transform(expr, module, imports, aliases)]
          end

        _ ->
          acc
      end
    end)
  end

  defp aggregate_imports(ast) do
    Enum.reduce(ast, [], fn expr, acc ->
      case expr do
        {:import, _, _} ->
          acc ++ [transform(expr)]

        _ ->
          acc
      end
    end)
  end

  defp eliminated_function?(name, params) do
    count = if params, do: Enum.count(params), else: 0
    count in Keyword.get_values(@eliminated_functions, name)
  end

  def transform({:def, _, [{name, _, nil}, [do: body]]}, module, imports, aliases) do
    body = transform_function_body(body, module, imports, aliases)
    %Function{name: name, params: [], bindings: [], body: body}
  end

  def transform({:def, _, [{name, _, params}, [do: body]]}, module, imports, aliases) do
    params = Enum.map(params, fn param -> transform(param, module, imports, aliases) end)

    bindings =
      Enum.map(params, fn param ->
        case aggregate_bindings(param) do
          [] ->
            nil

          path ->
            path
            |> hd()
        end
      end)
      |> Enum.reject(fn item -> item == nil end)

    body = transform_function_body(body, module, imports, aliases)

    %Function{name: name, params: params, bindings: bindings, body: body}
  end

  defp transform_function_body(body, module, imports, aliases) do
    case body do
      {:__block__, _, block} ->
        block

      expr ->
        [expr]
    end
    |> Enum.map(fn expr -> transform(expr, module, imports, aliases) end)
  end

  def transform({name, _, nil}, _module, _imports, _aliases) when is_atom(name) do
    %Variable{name: name}
  end

  def transform({:@, _, [{name, _, _}]}, _module, _imports, _aliases) do
    %ModuleAttribute{name: name}
  end

  def transform({function, _, params}, module, imports, aliases) when is_atom(function) do
    CallTransformer.transform(module, function, params, imports, aliases)
  end

  def transform(
        {{:., _, [{:__aliases__, _, called_module}, function]}, _, params},
        current_module,
        imports,
        aliases
      ) do
    CallTransformer.transform(called_module, function, params, imports, aliases)
  end
end
