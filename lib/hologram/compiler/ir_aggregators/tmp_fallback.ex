# TODO: remove

alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: Any do
  def aggregate(_), do: nil
end
