defmodule Hologram.Typespecs do
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}

  @type document_node :: %Component{} | %ElementNode{} | %Expression{} | %TextNode{}

  @type function_name :: atom()

  @typedoc """
  e.g. MapSet.new([{Hologram.Compiler.Processor, :compile}])
  """
  @type function_set :: MapSet.t({module, function_name})

  @typedoc """
  e.g. %{Hologram.Typespecs => %ModuleDefinition{}}
  """
  @type module_definitions_map :: %{module() => %ModuleDefinition{}}

  @typedoc """
  e.g. [:Hologram, :Typespecs]
  """
  @type module_segments :: list(atom())
end
