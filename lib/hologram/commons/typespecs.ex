defmodule Hologram.Typespecs do
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, Expression, TextNode}

  @type function_name :: atom()

  @typedoc """
  e.g. MapSet.new([{[:Hologram, :Compiler, :Processor], :compile}])
  """
  @type function_set :: %MapSet.t({module_name_segments, function_name}))

  @typedoc """
  e.g. %{[:Hologram, :Typespecs] => %ModuleDefinition{}}
  """
  @type module_definitions_map :: %{module_name_segments => %ModuleDefinition{}}

  @typedoc """
  e.g. [:Hologram, :Typespecs]
  """
  @type module_name_segments :: list(atom())

  @type virtual_dom_node :: %Component{} | %ElementNode{} | %Expression{} | %TextNode{}
end
