ExUnit.start()

# Boot the sync test database before the app starts: the app declares entities, which activates
# the Hologram database - the database itself must exist before the pool connects. Each run gets a
# fresh database of its own, so runs that overlap leave each other's tables alone. Positioned after
# ExUnit.start - the env guard recognizes the test env by the running ExUnit server.
Hologram.Test.DatabaseBootstrap.run!()

Hologram.Test.setup()

# The endpoint listens on port 0, so the OS gave it a free port, and runs that overlap on one
# machine never share one. Its URL still says port 0, so the port the listener got is put into
# it: the URL is how the simulated clients reach the app.
endpoint = HologramSyncTestsWeb.Endpoint
{:ok, {_ip, port}} = endpoint.server_info(:http)

endpoint_config =
  :hologram_sync_tests
  |> Application.fetch_env!(endpoint)
  |> Keyword.update!(:url, &Keyword.put(&1, :port, port))

Application.put_env(:hologram_sync_tests, endpoint, endpoint_config)
endpoint.config_change([{endpoint, endpoint_config}], [])

# The simulated clients each hold an SSE stream open on 127.0.0.1, and :httpc's default lets a
# request queue on a connection behind up to five others - so a client's cookie GET or handshake
# POST can wait, with no timeout, behind a stream that never ends. With no queue, a request goes to
# an idle connection or a new one.
:ok = :httpc.set_options(max_keep_alive_length: 0)
