defmodule Hologram.Template.VDOM do
  defmodule Component do
    defstruct module: nil, module_def: nil, props: %{}, children: []
  end

  defmodule ElementNode do
    defstruct tag: nil, attrs: nil, children: []
  end

  defmodule Expression do
    defstruct ir: nil
  end

  defmodule TextNode do
    defstruct content: nil
  end
end
