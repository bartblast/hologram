import globals from "globals";
import path from "node:path";
import {fileURLToPath} from "node:url";
import js from "@eslint/js";
import {FlatCompat} from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);

const __dirname = path.dirname(__filename);

const compat = new FlatCompat({
  baseDirectory: __dirname,
  recommendedConfig: js.configs.recommended,
  allConfig: js.configs.all,
});

export default [
  ...compat.extends("eslint:recommended"),
  {
    languageOptions: {
      ecmaVersion: "latest",
      globals: {
        ...globals.browser,
        ...globals.mocha,
        ...globals.node,
        Elixir_Code: "readonly",
        Elixir_Enum: "readonly",
        Elixir_Hologram_Router_Helpers: "readonly",
        Elixir_Kernel: "readonly",
        Elixir_Map: "readonly",
        Elixir_String_Chars: "readonly",
        Erlang: "readonly",
        Erlang_Code: "readonly",
        Erlang_Lists: "readonly",
        Erlang_Maps: "readonly",
      },
      sourceType: "module",
    },
    rules: {
      "no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
    },
  },
  {
    files: ["**/.eslintrc.{js,cjs}"],
    languageOptions: {
      ecmaVersion: 5,
      globals: {
        ...globals.node,
      },
      sourceType: "commonjs",
    },
  },
];
