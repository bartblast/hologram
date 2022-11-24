defmodule Hologram.Runtime.TemplateStore do
  use Hologram.Commons.MemoryStore
  require Logger
  alias Hologram.Compiler.Reflection

  @impl true
  def populate_table(opts \\ []) do
    Logger.debug("Hologram: populating template store table...")

    file_path = opts[:file_path] || Reflection.release_template_store_path()

    result =
      file_path
      |> populate_table_from_file()

    Logger.debug("Hologram: template store table populated from file")

    result
  end

  @impl true
  def table_name, do: :hologram_template_store
end
