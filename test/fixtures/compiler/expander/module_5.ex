defmodule Hologram.Test.Fixtures.Compiler.Expander.Module5 do
  defmacro __using__(_) do
    quote do
      import Hologram.Test.Fixtures.Compiler.Expander.Module1
      import Hologram.Test.Fixtures.Compiler.Expander.Module3
    end
  end

  def test do
    1
  end
end
