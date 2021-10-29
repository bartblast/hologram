defmodule Hologram.Compiler.Resolver do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.{AliasDirective, ImportDirective}
  alias Hologram.Compiler.Typespecs, as: T

  @doc """
  Determines the module based on the given module segments and aliases.

  ## Examples
      iex> aliases = [%AliasDirective{module: Abc.Bcd, as: [:Bcd]}]
      iex> resolve([:Bcd], aliases)
      Abc.Bcd
  """
  @spec resolve(T.module_name_segments(), list(%AliasDirective{})) :: module()

  def resolve(module_segs, aliases) do
    resolve(module_segs, nil, nil, [], aliases, nil)
  end

  @doc """
  Determines the module based on the given module segments, called function, imports, aliases and the calling module.

  ## Examples
      iex> imports = [%ImportDirective{module: Enum}]
      iex> resolve([], :put, 3, imports, [], Hologram.Compiler.Resolver)
      Enum
  """
  @spec resolve(
          T.module_name_segments(),
          T.function_name(),
          integer(),
          list(%ImportDirective{}),
          list(%AliasDirective{}),
          module()
        ) :: module()

  def resolve([], function, arity, imports, _aliases, calling_module) do
    imported_module = resolve_to_imported_module(function, arity, imports)

    cond do
      imported_module -> imported_module
      resolve_to_kernel_module(function, arity) -> Kernel
      true -> calling_module
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

  defp resolve_to_kernel_module(function, arity) do
    if function_exported?(Kernel, function, arity) || macro_exported?(Kernel, function, arity) do
      Kernel
    else
      nil
    end
  end

  # TODO: take into account "only" and "except" import opts
  defp resolve_to_imported_module(function, arity, imports) do
    resolved = Enum.find(imports, &function_exported?(&1.module, function, arity))

    if resolved, do: resolved.module, else: nil
  end
end
