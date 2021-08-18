defmodule Hologram.Template.Document do
  defmodule Component do
    defstruct module: nil, props: %{}, children: []
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
