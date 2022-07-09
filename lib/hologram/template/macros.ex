defmodule Hologram.Template.Macros do
  defmacro assemble(context, status, tokens, do: body) do
    context = Macro.escape(context, unquote: true)
    status = Macro.escape(status, unquote: true)
    tokens = Macro.escape(tokens, unquote: true)

    body =
      quote do
        unquote(body)
      end

    body = Macro.escape(body, unquote: true)

    quote bind_quoted: [context: context, status: status, tokens: tokens, body: body] do
      def assemble(unquote(context), unquote(status), unquote(tokens)), do: unquote(body)
    end
  end
end
