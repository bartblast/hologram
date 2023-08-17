defmodule Hologram.Runtime.Templatable do
  defmacro __using__(_opts) do
    quote do
      alias Hologram.Runtime.Templatable

      @callback template() :: (map -> list)
    end
  end

  def colocated_template_path(templatable_file) do
    Path.rootname(templatable_file) <> ".holo"
  end
end
