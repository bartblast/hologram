defmodule Hologram.Compiler.IR do
  @type ir :: IR.Alias.t()

  defmodule Alias do
    defstruct segments: nil

    @type t :: %__MODULE__{segments: T.alias_segments()}
  end
end
