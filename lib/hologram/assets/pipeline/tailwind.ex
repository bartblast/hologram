defmodule Hologram.Assets.Pipeline.Tailwind do
  def installed? do
    case Code.ensure_loaded(Tailwind) do
      {:module, Tailwind} ->
        true

      _fallback ->
        false
    end
  end
end
