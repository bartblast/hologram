defmodule Hologram.Typespecs do
  alias Hologram.Compiler.IR.ModuleDefinition

  @typedoc """
  e.g. %{[:Hologram, :Typespecs] => %ModuleDefinition{}}
  """
  @type module_definitions_map :: %{module_name_segments => %ModuleDefinition{}}

  @typedoc """
  e.g. [:Hologram, :Typespecs]
  """
  @type module_name_segments :: list(atom())
end
