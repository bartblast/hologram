defmodule HologramFeatureTests.Policies.PubliclyReadable do
  use Hologram.Policy

  allow :read, public: true
end
