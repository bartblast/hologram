defmodule Holograf.Page do
  defmacro __using__(_) do
    quote do
      import Holograf.Page
    end
  end

  def assign(_, _, _), do: nil
end
