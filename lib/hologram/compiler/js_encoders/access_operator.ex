alias Hologram.Compiler.{Context, Helpers, JSEncoder, Opts}
alias Hologram.Compiler.IR.AccessOperator

defimpl JSEncoder, for: AccessOperator do
  def encode(%{data: data, key: key}, %Context{} = context, %Opts{} = opts) do
    data = JSEncoder.encode(data, context, opts)
    key = JSEncoder.encode(key, context, opts)
    class_name = Helpers.class_name(Access)

    "#{class_name}.get(#{data}, #{key})"
  end
end
