defmodule Hologram.Compiler.Transformer do
  def transform({{:., _, [module, function]}, _, args}) when not is_atom(module) do
    build_call_ir(module, function, args)
  end

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
