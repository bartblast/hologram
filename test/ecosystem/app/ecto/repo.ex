# A repo the data flow rules answer for. The tests never start it: it only has to compile.
defmodule HologramEcosystemTests.Ecto.Repo do
  use Ecto.Repo, otp_app: :hologram_ecosystem_tests, adapter: Ecto.Adapters.Postgres
end
