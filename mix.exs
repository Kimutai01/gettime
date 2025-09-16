defmodule Gettime.MixProject do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/Kimutai01/gettime"

  def project do
    [
      app: :gettime,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:tzdata, "~> 1.1"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A simple and configurable Elixir library for converting database timestamps
    to user timezones with customizable formatting.
    """
  end

  defp package do
    [
      name: "gettime",
      licenses: ["MIT"],
      links: %{"GitHub" => @github_url},
      maintainers: ["Your Name"]
    ]
  end

  defp docs do
    [
      main: "Gettime",
      source_ref: "v#{@version}",
      source_url: @github_url
    ]
  end
end
