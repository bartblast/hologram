defmodule TestModule2 do
  defmacro __using__(_) do
    quote do
      import TestModule1
    end
  end
end
