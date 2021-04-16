defmodule TestModule4 do
  defmacro __using__(_) do
    quote do
      import TestModule3
    end
  end
end
