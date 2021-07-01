defmodule Hologram.Typespecs do
  alias Hologram.Compiler.IR.ModuleDefinition

  @typedoc """
  e.g. %{[:Hologram, :Typespecs] => %ModuleDefinition{}}
  """
  @type modules_map :: %{module_segments => %ModuleDefinition{}}

  @typedoc """
  e.g. [:Hologram, :Typespecs]
  """
  @type module_segments :: list(atom())
end
