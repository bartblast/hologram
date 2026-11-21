if System.get_env("GITHUB_ACTIONS") == "true" do
  ExUnit.configure(max_cases: 1)
end

ExUnit.start()

# Boot the cluster test databases before the app starts: the app declares entities, which
# activates the Hologram database - the databases themselves must exist before any pool
# connects, on this node or on a peer. Each run gets databases of its own, so runs that
# overlap leave each other's tables alone. The second database is the one the migration
# scenarios claim for the production mechanism, reached by the name this run gave it.
# Positioned after ExUnit.start - the env guard recognizes the test env by the running
# ExUnit server.
databases = Hologram.Test.DatabaseBootstrap.run!(["hologram_cluster_tests_migrations"])

Application.put_env(
  :hologram_cluster_tests,
  :migrations_database,
  databases["hologram_cluster_tests_migrations"]
)

Hologram.Test.setup()

# The peers this suite starts are full distributed-Erlang nodes, so the test runner must
# be one as well. epmd has to be up before a node can enable distribution - `-daemon` is
# a no-op when it already is. Longnames against 127.0.0.1 rather than a short name, since
# short names depend on hostname resolution, which differs between dev machines and CI
# runners. The name carries this BEAM's OS pid, and so do the peers' names, so runs that
# overlap on one machine don't claim the same names with epmd.
System.cmd("epmd", ["-daemon"])

# One name per run, so runtime atom creation is safe here.
# credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
node_name = :"cluster_test_#{System.pid()}@127.0.0.1"

{:ok, _pid} = Node.start(node_name, :longnames)
Node.set_cookie(:hologram_cluster_tests)

# Kills the test browsers that ended runs left behind, then starts Wallaby with ChromeDriver's
# log on, in this run's folder of tmp/chromedriver, restarting it when ChromeDriver doesn't get
# ready. CI uploads tmp/chromedriver when a run fails or hangs.
Hologram.Test.BrowserSession.start_wallaby()

# The proxy is the one origin the browser ever sees - it never talks to a peer directly. Which
# peer serves each request is the routing policy's decision, not the browser's. The port is
# one of the ports this run claims, so runs that overlap on one machine don't share it.
proxy_port = HologramClusterTests.Cluster.proxy_port()
Application.put_env(:hologram_cluster_tests, :proxy_port, proxy_port)
Application.put_env(:wallaby, :base_url, "http://localhost:#{proxy_port}")
