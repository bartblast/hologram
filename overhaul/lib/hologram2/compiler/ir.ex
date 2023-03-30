defmodule Hologram.Compiler.IR do
  @type ir :: IR.Alias.t()

  defmodule Alias do
    defstruct segments: nil

    @type t :: %__MODULE__{segments: T.alias_segments()}
  end

  defmodule Call do
    defstruct module: nil, function: nil, args: nil

    @type t :: %__MODULE__{module: module | nil, function: atom, args: list(IR.t())}
  end
end
