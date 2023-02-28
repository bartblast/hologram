defmodule Hologram.Compiler.Macros do
  defmacro expand(ir, context, do: body) do
    quote do
      def expand(
            unquote(ir) = evaluated_ir,
            unquote(context) = evaluated_context
          ) do
        if Application.get_env(:hologram, :debug_expander) do
          IO.puts("\n........................................\n")
          IO.puts("ir")
          IO.inspect(evaluated_ir)
          IO.puts("")
          IO.puts("context")
          IO.inspect(evaluated_context)
        end

        unquote(body)
      end
    end
  end
end
