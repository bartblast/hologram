alias Hologram.Compiler.{Context, JSEncoder, Opts}

alias Hologram.Compiler.IR.{
  MatchOperator,
  VariableAccess
}

defimpl JSEncoder, for: MatchOperator do
  import Hologram.Commons.Encoder, only: [encode_vars: 3]

  @var_name "window.hologramExpressionRightHandSide"

  def encode(%{bindings: bindings, right: right}, %Context{} = context, %Opts{} = opts) do
    right = JSEncoder.encode(right, context, opts)
    bindings = Enum.map(bindings, &prepend_variable_access/1)

    """
    #{@var_name} = #{right};
    #{encode_vars(bindings, context, opts)}\
    """
  end

  defp prepend_variable_access(binding) do
    %{binding | access_path: [%VariableAccess{name: @var_name} | binding.access_path]}
  end
end
