alias Hologram.Compiler.{Config, Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.MatchOperator

defimpl JSEncoder, for: MatchOperator do
  import Hologram.Commons.Encoder, only: [encode_vars: 3]

  def encode(%{bindings: bindings, right: right}, %Context{} = context, %Opts{} = opts) do
    right = JSEncoder.encode(right, context, opts)

    """
    #{Config.match_access_js()} = #{right};
    #{encode_vars(bindings, context, opts)}\
    """
  end
end
