defmodule KinoTuition.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ausimian/kino_tuition"

  def project do
    [
      app: :kino_tuition,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "KinoTuition",
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs(),
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:kino, "~> 0.16"},
      # tuition is a zero-dependency, rebar3-built Erlang library and is not yet
      # published to Hex; consume it straight from GitHub. `Mix.install/2` in a
      # Livebook resolves this transitively, so notebook users need no extra
      # setup. Swap for a Hex dependency once tuition is published.
      {:tuition, github: "ausimian/tuition"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end

  defp description do
    "A Livebook (Kino) terminal widget that renders a tuition TUI in the browser " <>
      "over xterm.js."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "tuition" => "https://github.com/ausimian/tuition"
      },
      files: ~w(lib mix.exs README.md RELEASE.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url,
      source_ref: "#{@version}"
    ]
  end
end
