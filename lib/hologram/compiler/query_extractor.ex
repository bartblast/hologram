defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Compiler.IR
  alias Hologram.Query
  alias Hologram.Query.Param

  @doc """
  Extracts the registered query terms declared by the given module - the normalized
  terms of every `from_query:` capture on the module's prop declarations.

  A zero-arity capture is invoked at build time (query builders are pure term
  constructors) and its result normalized. A capture with arguments is invoked
  with param sentinels - each argument flows into the term as a `{:param, name}`
  leaf named after the argument. Argument names are read from the captured
  function's IR, resolving through the generated from_query shim when the
  capture points at one. Modules without prop declarations declare no queries.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  when a capture argument is destructured instead of a plain name, or when a
  capture argument is named vars (reserved).
  """
  @spec extract_module_queries(module) :: list(%{atom => any})
  def extract_module_queries(module) do
    if function_exported?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_queries!(module, &1))
    else
      []
    end
  end

  @doc """
  Extracts the registered query terms declared by the given modules - the
  concatenated extract_module_queries/1 results in module order.
  """
  @spec extract_queries(list(module)) :: list(%{atom => any})
  def extract_queries(modules) do
    Enum.flat_map(modules, &extract_module_queries/1)
  end

  defp capture_param_names!(module, prop_name, capture) do
    capture_info = Function.info(capture)
    funs = module_funs(capture_info[:module])

    fun_name = shim_target(funs, module, prop_name, capture_info)
    fun_key = {fun_name, capture_info[:arity]}

    {^fun_key, {_visibility, [first_clause | _other_clauses]}} = List.keyfind(funs, fun_key, 0)

    Enum.map(first_clause.params, &param_name!(module, prop_name, &1))
  end

  defp module_funs(module) do
    module
    |> IR.for_module()
    |> IR.aggregate_module_funs()
  end

  # TODO: an argument named vars will bind the full assigns bag once that
  # convention lands - until then the name is reserved.
  defp param_name!(module, prop_name, %IR.Variable{name: :vars}) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} names an argument vars - the name is reserved, name arguments after the component assigns they bind to"
  end

  defp param_name!(_module, _prop_name, %IR.Variable{name: name}), do: name

  defp param_name!(module, prop_name, _param_ir) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} destructures an argument - arguments must be plain names, each binding to the like-named component assign"
  end

  defp prop_queries!(module, {name, _type, opts}) do
    case Keyword.fetch(opts, :from_query) do
      {:ok, capture} -> [prop_query!(module, name, capture)]
      :error -> []
    end
  end

  defp prop_query!(_module, _prop_name, capture) when is_function(capture, 0) do
    Query.normalize(capture.())
  end

  defp prop_query!(module, prop_name, capture) when is_function(capture) do
    sentinels =
      module
      |> capture_param_names!(prop_name, capture)
      |> Enum.map(&%Param{name: &1})

    term = apply(capture, sentinels)

    Query.normalize(term)
  end

  defp prop_query!(module, prop_name, value) do
    raise Hologram.CompileError,
      message:
        "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}"
  end

  defp shim_target(funs, module, prop_name, capture_info) do
    fun_name = capture_info[:name]

    shim? =
      capture_info[:module] == module and
        Atom.to_string(fun_name) == "__#{prop_name}_from_query__"

    if shim? do
      fun_key = {fun_name, capture_info[:arity]}

      {^fun_key, {_visibility, [shim_clause]}} = List.keyfind(funs, fun_key, 0)

      %IR.Block{expressions: [%IR.LocalFunctionCall{function: target_name}]} = shim_clause.body

      target_name
    else
      fun_name
    end
  end
end
