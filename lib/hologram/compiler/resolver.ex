defmodule Hologram.Compiler.Resolver do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.{Alias, Import}
  alias Hologram.Compiler.Typespecs, as: T

  @doc """
  Returns the called module's name segments.

  ## Examples
      iex> imports = [%Import{module: [:Enum]}]
      iex> resolve([], :put, 3, imports, [], [:Hologram, :Compiler, :Resolver])
      [:Enum]
  """
  @spec resolve(T.module_name_segments, T.function_name, integer(), list(%Import{}), list(%Alias{}), T.module_name_segments) :: T.module_name_segments

  def resolve(verbatim_module, function, arity, imports, aliases, calling_module) do
    case verbatim_module do
      [] ->
        imported_module = resolve_to_imported_module(function, arity, imports)
        if imported_module do
          imported_module
        else
          calling_module = resolve_to_calling_module(calling_module, function, arity)
          if calling_module, do: calling_module, else: [:Kernel]
        end

      _ ->
        aliased_module = resolve_to_aliased_module(verbatim_module, aliases)
        if aliased_module, do: aliased_module, else: verbatim_module
    end
  end

  defp resolve_to_aliased_module(verbatim_module, aliases) do
    resolved = Enum.find(aliases, &(&1.as == verbatim_module))
    if resolved, do: resolved.module, else: nil
  end

  defp resolve_to_calling_module(calling_module, function, arity) do
    module = Helpers.module(calling_module)

    if function_exported?(module, function, arity) do
      calling_module
    else
      nil
    end
  end

  # TODO: take into account "only" and "except" import opts
  defp resolve_to_imported_module(function, arity, imports) do
    resolved =
      Enum.find(imports, fn i ->
        module = Helpers.module(i.module)
        function_exported?(module, function, arity)
      end)

    if resolved, do: resolved.module, else: nil
  end
end
