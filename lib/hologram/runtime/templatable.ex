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

  def maybe_define_template_fun(template_path) do
    if File.exists?(template_path) do
      markup = File.read!(template_path)

      quote do
        def template do
          sigil_H(unquote(markup), [])
        end
      end
    end
  end
end
