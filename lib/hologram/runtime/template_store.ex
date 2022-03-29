defmodule Hologram.Runtime.TemplateStore do
  use Hologram.Commons.MemoryStore

  @dump_path Hologram.Compiler.Reflection.release_template_store_path()

  @impl true
  def dump_path, do: @dump_path

  @impl true
  def table_name, do: :hologram_template_store
end
