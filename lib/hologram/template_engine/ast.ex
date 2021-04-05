defmodule Hologram.TemplateEngine.AST do
  defmodule AttributeValue do
    defstruct ast: nil, text: nil
  end

  defmodule ComponentNode do
    defstruct module: nil, children: nil
  end

  defmodule TagNode do
    defstruct tag: nil, attrs: nil, children: nil
  end

  defmodule TextNode do
    defstruct text: nil
  end
end
