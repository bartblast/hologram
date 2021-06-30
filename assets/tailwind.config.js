const typography = require("@tailwindcss/typography");

module.exports = {
  mode: "jit",
  purge: [
    "./js/**/*.js",
    "./js/**/*.ts",
    "../lib/**/*.ex",
    "../lib/**/*.leex",
    "../lib/**/*.eex",
    "../lib/**/*.sface",
  ],
  darkMode: false,
  plugins: [typography],
};