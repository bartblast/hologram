defmodule Hologram.Compiler.PrunerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Pruner

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Builder
  alias Hologram.Compiler.Reflection

  @module_digest_plt_dump_path Reflection.root_priv_path() <> "/plt_module_digest_pruner_test.bin"
  @new_module_digest_plt_name :hologram_plt_module_digest_tmp_pruner_test
  @old_module_digest_plt_name :hologram_plt_module_digest_pruner_test

  setup_all do
    new_module_digest_plt = Builder.build_module_digest_plt(@new_module_digest_plt_name)

    old_module_digest_plt =
      PLT.start(name: @old_module_digest_plt_name, dump_path: @module_digest_plt_dump_path)

    diff = Builder.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    :ok
  end

  describe "page module" do
    test "keep entry page actions" do
    end
  end
end
