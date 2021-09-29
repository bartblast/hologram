defmodule Hologram.Commons.Encoder do
  def wrap_with_array(data) do
    if data != "", do: "[ #{data} ]", else: "[]"
  end

  def wrap_with_object(data) do
    if data != "", do: "{ #{data} }", else: "{}"
  end
end
