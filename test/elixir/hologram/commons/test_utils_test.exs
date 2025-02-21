defmodule Hologram.Commons.TestUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TestUtils

  test "build_argument_error_msg/2" do
    assert build_argument_error_msg(2, "my blame") === """
           errors were found at the given arguments:

             * 2nd argument: my blame
           """
  end

  describe "build_function_clause_error_msg/3" do
    # no args / no attempted clauses
    test "basic case" do
      assert build_function_clause_error_msg("my_fun/2") ==
               "no function clause matching in my_fun/2"
    end

    test "single arg" do
      assert build_function_clause_error_msg("my_fun/2", [:a]) == """
             no function clause matching in my_fun/2

             The following arguments were given to my_fun/2:

                 # 1
                 :a
             """
    end

    test "multiple args" do
      assert build_function_clause_error_msg("my_fun/2", [:a, :b]) == """
             no function clause matching in my_fun/2

             The following arguments were given to my_fun/2:

                 # 1
                 :a

                 # 2
                 :b
             """
    end

    test "single attempted clause" do
      assert build_function_clause_error_msg("my_fun/2", [], ["my attempted clause"]) == """
             no function clause matching in my_fun/2
             Attempted function clauses (showing 1 out of 1):

                 my attempted clause
             """
    end

    test "multiple attempted clasues" do
      assert build_function_clause_error_msg("my_fun/2", [], [
               "my attempted clause 1",
               "my attempted clause 2"
             ]) == """
             no function clause matching in my_fun/2
             Attempted function clauses (showing 2 out of 2):

                 my attempted clause 1
                 my attempted clause 2
             """
    end

    test "multiple args and attempted clauses" do
      assert build_function_clause_error_msg("my_fun/2", [:a, :b], [
               "my attempted clause 1",
               "my attempted clause 2"
             ]) == """
             no function clause matching in my_fun/2

             The following arguments were given to my_fun/2:

                 # 1
                 :a

                 # 2
                 :b

             Attempted function clauses (showing 2 out of 2):

                 my attempted clause 1
                 my attempted clause 2
             """
    end
  end

  describe "build_undefined_function_error/3" do
    # no similar functions / module is available
    test "basic case" do
      assert build_undefined_function_error({MyModule, :my_fun, 2}) ==
               "function MyModule.my_fun/2 is undefined or private"
    end

    test "single similar function" do
      assert build_undefined_function_error({MyModule, :my_fun, 2}, [{:my_other_fun, 3}]) == """
             function MyModule.my_fun/2 is undefined or private. Did you mean:

                   * my_other_fun/3
             """
    end

    test "multiple similar functions" do
      assert build_undefined_function_error({MyModule, :my_fun, 2}, [
               {:my_other_fun_1, 3},
               {:my_other_fun_2, 4}
             ]) == """
             function MyModule.my_fun/2 is undefined or private. Did you mean:

                   * my_other_fun_1/3
                   * my_other_fun_2/4
             """
    end

    test "module is not available" do
      expected =
        if Version.match?(System.version(), ">= 1.18.0") do
          "function MyModule.my_fun/2 is undefined (module MyModule is not available). Make sure the module name is correct and has been specified in full (or that an alias has been defined)"
        else
          "function MyModule.my_fun/2 is undefined (module MyModule is not available)"
        end

      assert build_undefined_function_error({MyModule, :my_fun, 2}, [], false) == expected
    end
  end

  test "prevent_term_typing_violation/1" do
    assert prevent_term_typing_violation(:abc) == :abc
  end

  test "wrap_term/1" do
    assert wrap_term(:abc) == :abc
  end
end
