defmodule Hologram.Compiler.Macros do
  defmacro expand(ir, context, do: body) do
    quote do
      def expand(
            unquote(ir) = evaluated_ir,
            unquote(context) = evaluated_context
          ) do
        result = unquote(body)

        if Application.get_env(:hologram, :debug_expander) do
          IO.puts("\n........................................EXPAND\n")
          IO.puts("ir")
          IO.inspect(evaluated_ir)
          IO.puts("")
          IO.puts("context")
          IO.inspect(evaluated_context)
          IO.puts("")
          IO.puts("result")
          IO.inspect(result)
        end

        result
      end
    end
  end

  defmacro transform({:when, _, [{:_, _, [ast]}, guard]}, do: body) do
    quote do
      def transform(unquote(ast) = evaluated_ast) when unquote(guard) do
        result = unquote(body)

        if Application.get_env(:hologram, :debug_transformer) do
          IO.puts("\n........................................TRANSFORM\n")
          IO.puts("ast")
          IO.inspect(evaluated_ast)
          IO.puts("")
          IO.puts("result")
          IO.inspect(result)
        end

        result
      end
    end
  end

  defmacro transform(ast, do: body) do
    quote do
      def transform(unquote(ast) = evaluated_ast) do
        result = unquote(body)

        if Application.get_env(:hologram, :debug_transformer) do
          IO.puts("\n........................................TRANSFORM\n")
          IO.puts("ast")
          IO.inspect(evaluated_ast)
          IO.puts("")
          IO.puts("result")
          IO.inspect(result)
        end

        result
      end
    end
  end
end
