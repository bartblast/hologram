defmodule Hologram.Template.VirtualDOM do
  alias Hologram.Compiler.{Helpers, Processor}
  alias Hologram.Template.{Parser, Transformer}

  defmodule Component do
    defstruct module: nil, children: nil
  end

  defmodule ElementNode do
    defstruct tag: nil, attrs: nil, children: nil
  end

  defmodule Expression do
    defstruct ir: nil
  end

  defmodule TextNode do
    defstruct content: nil
  end

  def build(module) do
    aliases =
      Helpers.module_name_segments(module)
      |> Processor.get_module_definition()
      |> Map.get(:aliases)

    module.template()
    |> Parser.parse!()
    |> Transformer.transform(aliases)
  end
end
