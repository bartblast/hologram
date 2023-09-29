defmodule Hologram.Runtime.Application do
  use Application

  alias Hologram.Commons.Reflection
  alias Hologram.Router.PageResolver
  alias Hologram.Runtime.AssetPathLookup
  alias Hologram.Runtime.PageDigestLookup

  @impl Application
  def start(_type, _args) do
    page_digest_dump_file =
      Path.join([Reflection.build_dir(), Reflection.page_digest_plt_dump_file_name()])

    static_path = Reflection.release_static_path()

    children = [
      {AssetPathLookup,
       process_name: AssetPathLookup, static_path: static_path, store_key: AssetPathLookup},
      {PageDigestLookup, store_key: PageDigestLookup, dump_path: page_digest_dump_file},
      {PageResolver, store_key: PageResolver}
    ]

    opts = [strategy: :one_for_one, name: Hologram.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
