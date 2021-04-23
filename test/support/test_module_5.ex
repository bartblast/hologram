defmodule TestModule5 do
  defmacro __using__(_) do
    quote do
      import TestModule1
      import TestModule3
    end
  end

  def test do
    1
  end
end
