defmodule Hologram.Middleware.BuilderTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Middleware.Builder.Module1
  alias Hologram.Test.Fixtures.Middleware.Builder.Module2, as: Host

  describe "__middleware__/0" do
    test "compiles declarations into {capture, opts} entries in declaration order" do
      assert [{capture_1, opts_1}, {capture_2, opts_2}, {capture_3, opts_3}] =
               Host.__middleware__()

      assert Function.info(capture_1, :module) == {:module, Module1}
      assert Function.info(capture_1, :name) == {:name, :call}
      assert Function.info(capture_1, :arity) == {:arity, 2}
      assert opts_1 == []

      assert Function.info(capture_2, :module) == {:module, Module1}
      assert opts_2 == [role: :admin]

      assert Function.info(capture_3, :module) == {:module, Host}
      assert Function.info(capture_3, :name) == {:name, :enrich}
      assert opts_3 == []
    end
  end
end
