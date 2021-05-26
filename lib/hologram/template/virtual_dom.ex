defmodule Hologram.Template.VirtualDOM do
  defmodule Component do
    defstruct module: nil
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
end
