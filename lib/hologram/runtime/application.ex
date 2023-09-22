defmodule Hologram.Runtime.Application do
  use Application

  alias Hologram.Commons.Reflection
  alias Hologram.Router.PageResolver
  alias Hologram.Runtime.PageDigestLookup

  @impl Application
  def start(_type, _args) do
    page_digest_dump_file =
      Path.join([Reflection.build_dir(), Reflection.page_digest_plt_dump_file_name()])

    children = [
      {PageDigestLookup, table_name: PageDigestLookup, dump_path: page_digest_dump_file},
      {PageResolver, persistent_term_key: PageResolver.default_persistent_term_key()}
    ]

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
