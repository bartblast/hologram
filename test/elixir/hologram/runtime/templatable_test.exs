defmodule Hologram.Runtime.TemplatableTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Templatable

  test "colocated_template_path/1" do
    assert colocated_template_path("/my_dir_1/my_dir_2/my_dir_3/my_file.ex") ==
             "/my_dir_1/my_dir_2/my_dir_3/my_file.holo"
  end

  describe "maybe_define_template_fun/1" do
    test "valid template path" do
      template_path = "#{@fixtures_path}/runtime/templatable/template_1.holo"

      assert maybe_define_template_fun(template_path) ==
               {:def,
                [context: Hologram.Runtime.Templatable, imports: [{1, Kernel}, {2, Kernel}]],
                [
                  {:template, [context: Hologram.Runtime.Templatable],
                   Hologram.Runtime.Templatable},
                  [do: {:sigil_H, [], ["My template 1", []]}]
                ]}
    end

    test "invalid template path" do
      refute maybe_define_template_fun("/my_invalid_template_path.holo")
    end
  end
end
