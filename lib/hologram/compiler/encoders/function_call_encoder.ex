alias Hologram.Compiler.{Context, Encoder, Helpers, Opts}
alias Hologram.Compiler.IR.{FunctionCall, Variable}
alias Hologram.Template.{Parser, Transformer}
alias Hologram.Template.Encoder, as: TemplateEncoder

defimpl Encoder, for: FunctionCall do
  import Hologram.Compiler.Encoder.Commons

  def encode(%{function: :sigil_H} = ir, %Context{} = context, _) do
    ir
    |> Map.get(:params)
    |> hd()
    |> Map.get(:parts)
    |> hd()
    |> Map.get(:value)
    |> String.trim()
    |> Parser.parse!()
    |> Transformer.transform(context.aliases)
    |> TemplateEncoder.encode()
  end

  def encode(%{module: module, function: function, params: params}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    function = encode_function_name(function)
    params = encode_params(params, context, opts)

    "#{class_name}.#{function}(#{params})"
  end

  defp encode_params(params, context, opts) do
    Enum.map(params, fn param ->
      case param do
        %Variable{name: name} ->
          name

        _ ->
          Encoder.encode(param, context, opts)
      end
    end)
    |> Enum.join(", ")
  end
end
