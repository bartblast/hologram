defmodule Hologram.Runtime.PageDigestStore do
  use Hologram.Commons.MemoryStore
  alias Hologram.Compiler.Reflection

  @impl true
  def populate_table do
    Reflection.release_page_digest_store_path()
    |> populate_table_from_file()
  end

  @impl true
  def table_name, do: :hologram_page_digest_store
end
