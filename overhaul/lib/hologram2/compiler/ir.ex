defmodule Hologram.Compiler.IR do
  alias Hologram.Commons.Types, as: T

  @type ir ::
          IR.AnonymousFunctionCall.t()
          | IR.Alias.t()
          | IR.DotOperator.t()
          | IR.ModuleAttributeOperator.t()
          | IR.ModuleType.t()
          | IR.Symbol.t()

  defmodule AnonymousFunctionCall do
    defstruct name: nil, args: nil

    @type t :: %__MODULE__{name: atom, args: list(IR.t())}
  end

  defmodule Alias do
    defstruct segments: nil

    @type t :: %__MODULE__{segments: T.alias_segments()}
  end

  defmodule Call do
    defstruct module: nil, function: nil, args: nil

    @type t :: %__MODULE__{module: module | nil, function: atom, args: list(IR.t())}
  end

  defmodule DotOperator do
    defstruct left: nil, right: nil

    @type t :: %__MODULE__{left: IR.t(), right: IR.t()}
  end

  defmodule ModuleAttributeOperator do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end

  defmodule ModuleType do
    defstruct module: nil, segments: nil

    @type t :: %__MODULE__{module: module, segments: T.alias_segments()}
  end

  defmodule Symbol do
    defstruct name: nil

    @type t :: %__MODULE__{name: atom}
  end
end
