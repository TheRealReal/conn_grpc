defmodule ConnGRPC.MixProject do
  use Mix.Project

  @source_url "https://github.com/TheRealReal/conn_grpc"
  @version "0.1.0"

  def project do
    [
      app: :conn_grpc,
      version: @version,
      name: "ConnGRPC",
      description: "Persistent channels, and channel pools for gRPC Elixir",
      elixir: "~> 1.10",
      deps: deps(),
      docs: docs(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp extra_applications(:test), do: extra_applications(:default) ++ [:logger]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:backoff, "~> 1.1"},
      {:grpc, "~> 0.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["TheRealReal"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/conn_grpc",
      source_url: @source_url,
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md": [filename: "changelog", title: "Changelog"],
        "CODE_OF_CONDUCT.md": [filename: "code_of_conduct", title: "Code of Conduct"],
        LICENSE: [filename: "license", title: "License"],
        NOTICE: [filename: "notice", title: "Notice"]
      ]
    ]
  end
end
