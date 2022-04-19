alias Hologram.Compiler.Context
alias Hologram.Compiler.IR.AnonymousFunctionCall
alias Hologram.Compiler.JSEncoder
alias Hologram.Compiler.Opts

defimpl JSEncoder, for: AnonymousFunctionCall do
  use Hologram.Commons.Encoder

  def encode(%{name: name, args: args}, %Context{} = context, %Opts{} = opts) do
    var = encode_identifier(name)
    args = encode_args(args, context, opts)

    "#{var}(#{args})"
  end
end
