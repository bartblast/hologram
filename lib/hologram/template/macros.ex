defmodule Hologram.Template.Macros do
  defmacro assemble(context, status, tokens, do: body) do
    quote do
      def assemble(
            unquote(context) = evaluated_context,
            unquote(status) = evaluated_status,
            unquote(tokens) = evaluated_tokens
          ) do
        if Application.get_env(:hologram, :debug_tag_assembler) do
          IO.puts("\n........................................\n")
          IO.puts("context")
          IO.inspect(evaluated_context)
          IO.puts("")
          IO.puts("status")
          IO.inspect(evaluated_status)
          IO.puts("")
          IO.puts("tokens")
          IO.inspect(evaluated_tokens)
        end

        unquote(body)
      end
    end
  end
end
