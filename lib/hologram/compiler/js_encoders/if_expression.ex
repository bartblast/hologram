alias Hologram.Compiler.{Context, JSEncoder, Opts}
alias Hologram.Compiler.IR.{Block, IfExpression}

defimpl JSEncoder, for: IfExpression do
  import Hologram.Commons.Encoder, only: [encode_as_anonymous_function: 3]

  def encode(
        %{condition: condition_expr, do: do_block, else: else_block},
        %Context{} = context,
        %Opts{} = opts
      ) do
    condition_block = %Block{expressions: [condition_expr]}
    condition_anon_fun = encode_as_anonymous_function(condition_block, context, opts)

    do_anon_fun = encode_as_anonymous_function(do_block, context, opts)
    else_anon_fun = encode_as_anonymous_function(else_block, context, opts)

    "Elixir_Kernel.if(#{condition_anon_fun}, #{do_anon_fun}, #{else_anon_fun})"
  end
end
