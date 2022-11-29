alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.FunctionCall

defimpl JSEncoder, for: FunctionCall do
  use Hologram.Commons.Encoder

  def encode(
        %{module: module, function: function, args: args},
        %Context{} = context,
        %Opts{} = opts
      ) do
    class_name = Helpers.class_name(module)
    function = encode_identifier(function)
    args = encode_args(args, context, opts)

    "#{class_name}.#{function}(#{args})"
  end
end
