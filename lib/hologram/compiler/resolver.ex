defmodule Hologram.Compiler.Resolver do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.{Alias, Import}
  alias Hologram.Compiler.Typespecs, as: T

  @doc """
  Determines the module based on the given module segments and aliases.

  ## Examples
      iex> aliases = [%Alias{module: Abc.Bcd, as: [:Bcd]}]
      iex> resolve([:Bcd], aliases)
      Abc.Bcd
  """
  @spec resolve(T.module_segments(), list(%Alias{})) :: module()

  def resolve(module_segs, aliases) do
    resolve(module_segs, nil, nil, [], aliases, nil)
  end

  @doc """
  Determines the module based on the given module segments, called function, imports, aliases and the calling module.

  ## Examples
      iex> imports = [%Import{module: Enum}]
      iex> resolve([], :put, 3, imports, [], Hologram.Compiler.Resolver)
      Enum
  """
  @spec resolve(
          T.module_segments(),
          T.function_name(),
          integer(),
          list(%Import{}),
          list(%Alias{}),
          module()
        ) :: module()

  def resolve([], function, arity, imports, _aliases, calling_module) do
    imported_module = resolve_to_imported_module(function, arity, imports)

    if imported_module do
      imported_module
    else
      calling_module = resolve_to_calling_module(calling_module, function, arity)
      if calling_module, do: calling_module, else: Kernel
    end
  end

  def resolve(module_segs, _function, _arity, _imports, aliases, _calling_module) do
    aliased_module = resolve_to_aliased_module(module_segs, aliases)
    if aliased_module, do: aliased_module, else: Helpers.module(module_segs)
  end

  defp resolve_to_aliased_module(module_segs, aliases) do
    resolved = Enum.find(aliases, &(&1.as == module_segs))
    if resolved, do: resolved.module, else: nil
  end

  defp resolve_to_calling_module(module, function, arity) do
    if function_exported?(module, function, arity), do: module, else: nil
  end

  # TODO: take into account "only" and "except" import opts
  defp resolve_to_imported_module(function, arity, imports) do
    resolved =
      Enum.find(imports, &function_exported?(&1.module, function, arity))

    if resolved, do: resolved.module, else: nil
  end
end
