alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.{FunctionCall, Variable}
alias Hologram.Template.{Parser, Transformer}
alias Hologram.Template.Encoder, as: TemplateEncoder

defimpl JSEncoder, for: FunctionCall do
  use Hologram.Commons.Encoder

  def encode(%{function: :sigil_H} = ir, %Context{} = context, _) do
    ir
    |> Map.get(:args)
    |> hd()
    |> Map.get(:parts)
    |> hd()
    |> Map.get(:value)
    |> String.trim()
    |> Parser.parse!()
    |> Transformer.transform(context.aliases)
    |> TemplateEncoder.encode()
  end

  def encode(%{module: module, function: function, args: args}, %Context{} = context, %Opts{} = opts) do
    class_name = Helpers.class_name(module)
    function = encode_function_name(function)
    args = encode_args(args, context, opts)

    "#{class_name}.#{function}(#{args})"
  end

  defp encode_args(args, context, opts) do
    Enum.map(args, fn arg ->
      case arg do
        %Variable{name: name} ->
          name

        _ ->
          JSEncoder.encode(arg, context, opts)
      end
    end)
    |> Enum.join(", ")
  end
end
