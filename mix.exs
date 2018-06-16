defmodule Cluster.Strategy.ECS.MixProject do
  use Mix.Project

  def project do
    [
      app: :libcluster_ecs,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libcluster, "~> 2.1"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_ecs, "~> 0.1.1"}
    ]
  end
end
