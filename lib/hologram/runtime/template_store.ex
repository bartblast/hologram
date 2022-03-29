defmodule Hologram.Runtime.TemplateStore do
  use Hologram.Commons.MemoryStore

  @dump_path Hologram.Compiler.Reflection.release_template_store_path()

  @impl true
  def populate_table do
    @dump_path
    |> File.read!()
    |> Utils.deserialize()
    |> Enum.each(fn {key, value} -> put(key, value) end)
  end
  
  @impl true
  def table_name, do: :hologram_template_store
end
