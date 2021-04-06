defmodule Hologram.TemplateEngine.AST do
  defmodule ComponentNode do
    defstruct module: nil, children: nil
  end

  defmodule Expression do
    defstruct ast: nil
  end

  defmodule TagNode do
    defstruct tag: nil, attrs: nil, children: nil
  end

  defmodule TextNode do
    defstruct text: nil
  end
end
