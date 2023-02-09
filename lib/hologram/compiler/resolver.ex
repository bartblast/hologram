defmodule Hologram.Compiler.Resolver do
  alias Hologram.Compiler.{Context, Helpers, Reflection}
  alias Hologram.Typespecs, as: T

  @doc """
  Resolves to a fully qualified module.

  ## Examples
      iex> aliases = [%AliasDirective{module: Abc.Bcd, as: [:Bcd]}]
      iex> context = %Context{aliases: aliases}
      iex> resolve([:Bcd], context)
      Abc.Bcd
  """
  @spec resolve(T.alias_segments(), %Context{}) :: module()

  def resolve(alias_segs, %Context{} = context) do
    resolve(alias_segs, nil, nil, context)
  end

  @doc """
  Resolves to a fully qualified module.

  ## Examples
      iex> imports = [%ImportDirective{module: Enum}]
      iex> context = %Context{imports: imports}
      iex> resolve([], :put, 3, context)
      Enum
  """
  @spec resolve(
          T.alias_segments(),
          T.function_name(),
          integer(),
          %Context{}
        ) :: module()

  def resolve([], function, arity, %Context{} = context) do
    imported_module = resolve_to_imported_module(function, arity, context.imports)

    cond do
      imported_module -> imported_module
      resolve_to_kernel_module(function, arity) -> Kernel
      true -> context.module
    end
  end

  def resolve(module_segs, _function, _arity, %Context{} = context) do
    aliased_module = resolve_to_aliased_module(module_segs, context.aliases)
    if aliased_module, do: aliased_module, else: Helpers.module(module_segs)
  end

  defp resolve_to_aliased_module(alias_segs, aliases) do
    resolved = Enum.find(aliases, &(&1.as == alias_segs))
    if resolved, do: resolved.module, else: nil
  end

  defp resolve_to_kernel_module(function, arity) do
    if Reflection.has_function?(Kernel, function, arity) ||
         Reflection.has_macro?(Kernel, function, arity) do
      Kernel
    else
      nil
    end
  end

  # TODO: take into account "only" and "except" import opts
  defp resolve_to_imported_module(function, arity, imports) do
    resolved = Enum.find(imports, &Reflection.has_function?(&1.module, function, arity))

    if resolved, do: resolved.module, else: nil
  end
end
