defmodule Hologram.Compiler.FunctionCallTransformer do
  alias Hologram.Compiler.AST.FunctionCall
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Resolver
  alias Hologram.Compiler.Transformer

  def transform(called_module, function, params, context) do
    params = transform_call_params(params, context)

    resolved_module =
      resolve_called_module(called_module, function, params, context)

    %FunctionCall{module: resolved_module, function: function, params: params}
  end

  defp resolve_called_module(called_module, function, params, context) do
    arity = Enum.count(params)

    if Enum.count(called_module) == 0 do
      imported_module = resolve_imported_module(function, arity, context[:imports])
      if imported_module, do: imported_module, else: context[:module]
    else
      aliased_module = Resolver.resolve(called_module, context[:aliases])
      if aliased_module, do: aliased_module, else: called_module
    end
  end

  defp resolve_imported_module(function, arity, imports) do
    resolved =
      Enum.find(imports, fn i ->
        module = Helpers.fully_qualified_module(i.module)
        {function, arity} in module.module_info()[:exports]
      end)

    if resolved, do: resolved.module, else: nil
  end

  defp transform_call_params(params, context) do
    Enum.map(params, &Transformer.transform(&1, context))
  end
end
