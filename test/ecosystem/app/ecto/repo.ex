# The repo of the Ecto fixtures. Never started: the schemas only have to compile.
defmodule HologramEcosystemTests.Ecto.Repo do
  use Ecto.Repo, otp_app: :hologram_ecosystem_tests, adapter: Ecto.Adapters.Postgres
end
