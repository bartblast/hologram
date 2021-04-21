defmodule Hologram.Transpiler.Normalizer do
  def normalize({:defmodule, line, [aliases, [do: {:__block__, [], block}]]}) do
    {:defmodule, line, [aliases, [do: {:__block__, [], normalize(block)}]]}
  end

  def normalize({:defmodule, line, [aliases, [do: block]]}) do
    {:defmodule, line, [aliases, [do: {:__block__, [], normalize([block])}]]}
  end

  def normalize(ast) do
    ast
  end
end
