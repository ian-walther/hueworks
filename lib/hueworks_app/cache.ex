defmodule HueworksApp.Cache do
  @moduledoc """
  Runtime cache API backed by `HueworksApp.Cache.Store`.
  """

  alias HueworksApp.Cache.Store

  def get(namespace, key, default \\ nil) do
    case Store.get(namespace, key) do
      {:hit, value} -> value
      :miss -> default
    end
  end

  def put(namespace, key, value, opts \\ []) do
    Store.put(namespace, key, value, opts)
  end

  def delete(namespace, key) do
    Store.delete(namespace, key)
  end

  def flush_namespace(namespace) do
    Store.flush_namespace(namespace)
  end

  def flush_all do
    Store.flush_all()
  end

  def get_or_load(namespace, key, loader_fun, opts \\ []) when is_function(loader_fun, 0) do
    case Store.get(namespace, key) do
      {:hit, value} ->
        value

      :miss ->
        value = loader_fun.()
        :ok = Store.put(namespace, key, value, opts)
        value
    end
  end
end
