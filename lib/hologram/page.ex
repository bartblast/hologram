defmodule Hologram.Page do
  defmacro __using__(_) do
    quote do
      import Hologram.Page
    end
  end

  def assign(_, _, _), do: nil
end
