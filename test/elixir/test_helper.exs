alias Hologram.Runtime.PageDigestRegistry

# Create tmp dir if it doesn't exist yet.
tmp_path = "#{File.cwd!()}/tmp"
File.mkdir_p!(tmp_path)

ExUnit.start()

Mox.defmock(PageDigestRegistry.Mock, for: PageDigestRegistry)
Application.put_env(:hologram, :page_digest_registry_impl, PageDigestRegistry.Mock)
