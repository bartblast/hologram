defmodule Hologram.Compiler.QueryExtractor do
  @moduledoc false

  alias Hologram.Query

  @doc """
  Extracts the registered query terms declared by the given module - the normalized
  terms of every `from_query:` capture on the module's prop declarations.

  A zero-arity capture is invoked at build time (query builders are pure term
  constructors) and its result normalized. Modules without prop declarations
  declare no queries.

  Raises Hologram.CompileError when a from_query value is not a function capture,
  or when the capture takes arguments.
  """
  @spec extract_module_queries(module) :: list(%{atom => any})
  def extract_module_queries(module) do
    if function_exported?(module, :__props__, 0) do
      Enum.flat_map(module.__props__(), &prop_queries!(module, &1))
    else
      []
    end
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

  # TODO: symbolic evaluation over the module's IR turns capture arguments into
  # query params (and forks on their branches) - until it exists, parameterized
  # query captures fail the build.
  defp prop_query!(module, prop_name, capture) when is_function(capture) do
    raise Hologram.CompileError,
      message:
        "query capture for prop #{inspect(prop_name)} in #{inspect(module)} takes arguments - parameterized query captures are not extractable yet"
  end

  defp prop_query!(module, prop_name, value) do
    raise Hologram.CompileError,
      message:
        "from_query for prop #{inspect(prop_name)} in #{inspect(module)} must be a function capture, got: #{inspect(value)}"
  end
end
