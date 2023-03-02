defmodule Hologram.Compiler.Macros do
  defmacro expand(ir, context, do: body) do
    quote do
      def expand(
            unquote(ir) = evaluated_ir,
            unquote(context) = evaluated_context
          ) do
        if Application.get_env(:hologram, :debug_expander) do
          IO.puts("\n........................................EXPAND\n")
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

  defmacro transform({:when, _, [{:_, _, [ast]}, guard]}, do: body) do
    quote do
      def transform(unquote(ast) = evaluated_ast) when unquote(guard) do
        if Application.get_env(:hologram, :debug_transformer) do
          IO.puts("\n........................................TRANSFORM\n")
          IO.puts("ast")
          IO.inspect(evaluated_ast)
        end

        unquote(body)
      end
    end
  end

  defmacro transform(ast, do: body) do
    quote do
      def transform(unquote(ast) = evaluated_ast) do
        if Application.get_env(:hologram, :debug_transformer) do
          IO.puts("\n........................................TRANSFORM\n")
          IO.puts("ast")
          IO.inspect(evaluated_ast)
        end

        unquote(body)
      end
    end
  end
end
