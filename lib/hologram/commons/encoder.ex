defmodule Hologram.Commons.Encoder do
  defmacro __using__(_) do
    quote do
      import Hologram.Commons.Encoder
    end
  end

  def wrap_with_array(data) do
    if data != "", do: "[ #{data} ]", else: "[]"
  end

  def wrap_with_object(data) do
    if data != "", do: "{ #{data} }", else: "{}"
  end
end
