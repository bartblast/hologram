defmodule Hologram.Transpiler.Normalizer do
  def normalize({m_1, m_2, [m_3, [do: {:__block__, [], block}]]}) do
    {m_1, m_2, [m_3, [do: {:__block__, [], normalize(block)}]]}
  end

  def normalize({m_1, m_2, [m_3, [do: expr]]}) do
    {m_1, m_2, [m_3, [do: {:__block__, [], normalize([expr])}]]}
  end

  def normalize(ast) do
    ast
  end
end
