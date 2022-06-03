defmodule Hologram.Runtime.TemplateStore do
  use Hologram.Commons.MemoryStore
  alias Hologram.Compiler.Reflection

  @impl true
  def populate_table do
    Reflection.release_template_store_path()
    |> populate_table_from_file()
  end

  @impl true
  def table_name, do: :hologram_template_store
end
