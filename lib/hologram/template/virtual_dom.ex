defmodule Hologram.Template.VirtualDOM do
  # TODO: implement (it's not supported yet)
  defmodule ComponentNode do
    defstruct module: nil, children: nil
  end

  defmodule ElementNode do
    defstruct tag: nil, attrs: nil, children: nil
  end
  
  defmodule Expression do
    defstruct ir: nil
  end

  defmodule TextNode do
    defstruct text: nil
  end
end
