defmodule Hologram.Compiler.Serializer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.JSEncoder
  alias Hologram.Compiler.Opts

  def serialize(state) do
    # TODO: fix
    context = %Hologram.Compiler.Context{}

    state
    |> Helpers.term_to_ir()
    |> JSEncoder.encode(context, %Opts{})
  end
end
