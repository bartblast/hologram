alias Hologram.Compiler.{Context, Helpers, JSEncoder, MapKeyEncoder, Opts}
alias Hologram.Compiler.IR.{AtomType, ModuleAttributeOperator}

defimpl JSEncoder, for: ModuleAttributeOperator do
  def encode(%{name: name}, %Context{} = context, %Opts{template: true} = opts) do
    key = MapKeyEncoder.encode(%AtomType{value: name}, context, opts)
    "$state.data['#{key}']"
  end

  def encode(%{name: name}, %Context{} = context, _) do
    class_name = Helpers.class_name(context.module)
    "#{class_name}.$#{name}"
  end
end
