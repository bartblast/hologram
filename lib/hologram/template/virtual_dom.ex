defmodule Hologram.Template.VirtualDOM do
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
    module.template()
    |> Parser.parse!()
    |> Transformer.transform()
  end
end
