defmodule Hologram.Compiler.Transformer do
  alias Hologram.Compiler.Helpers

  def transform({{:., _, [{name, _, _}]}, _, args}) do
    %IR.AnonymousFunctionCall{
      name: name,
      args: transform_list(args)
    }
  end

  def transform({{:., _, [{marker, _, _} = left, right]}, [{:no_parens, true} | _], []})
      when marker not in [:__aliases__, :__MODULE__] do
    %IR.DotOperator{
      left: transform(left),
      right: transform(right)
    }
  end

  def transform({:@, _, [{name, _, ast}]}) when not is_list(ast) do
    %IR.ModuleAttributeOperator{name: name}
  end

  def transform({:__aliases__, [alias: module], _alias_segs}) when module != false do
    module_segs = Helpers.alias_segments(module)
    %IR.ModuleType{module: module, segments: module_segs}
  end

  # --- PRESERVE ORDER (BEGIN) ---

  def transform({:__aliases__, _, segments}) do
    %IR.Alias{segments: segments}
  end

  def transform({{:., _, [module, function]}, _, args}) when not is_atom(module) do
    build_call_ir(module, function, args)
  end

  def transform({function, _, args}) when is_atom(function) and is_list(args) do
    build_call_ir(nil, function, args)
  end

  def transform({name, _, _}) when is_atom(name) do
    %IR.Symbol{name: name}
  end

  # --- PRESERVE ORDER (END) ---

  defp build_call_ir(module, function, args) do
    new_module =
      case module do
        nil ->
          nil

        # TODO: uncomment after contextual call transformer is implemented
        # %IR.ModuleType{} ->
        #   module

        module ->
          transform(module)
      end

    %IR.Call{
      module: new_module,
      function: function,
      args: transform_list(args)
    }
  end
end
